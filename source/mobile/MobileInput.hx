package mobile;

#if mobile
import flixel.FlxG;
import flixel.input.keyboard.FlxKey;
import haxe.Json;
import lime.utils.Assets;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.KeyboardEvent;
import openfl.events.TouchEvent;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.ui.Keyboard;
import openfl.ui.Multitouch;
import openfl.ui.MultitouchInputMode;
import shaders.NoteColors;
import states.PlayState;
import states.TitleState;
import utilities.NoteVariables;

/**
 * Which set of touch controls is on screen.
 */
private enum Mode {
	/**
	 * Menus: a D-pad plus accept / back buttons.
	 */
	MENU;

	/**
	 * Playing a song: the whole screen is split into one lane per note column.
	 */
	GAME;
}

/**
 * A single on screen button that holds down a keyboard key while it is touched.
 */
private class VirtualButton extends Sprite {
	public var keyCode(default, null):Int;
	public var size(default, null):Float;

	var label:TextField;
	var pressed:Bool = false;
	var baseAlpha:Float;

	public function new(keyCode:Int, text:String, x:Float, y:Float, size:Float, baseAlpha:Float) {
		super();
		this.keyCode = keyCode;
		this.size = size;
		this.baseAlpha = baseAlpha;

		mouseEnabled = false;
		mouseChildren = false;

		label = new TextField();
		label.selectable = false;
		label.mouseEnabled = false;
		label.autoSize = TextFieldAutoSize.NONE;
		label.width = size;
		label.defaultTextFormat = new TextFormat("_sans", Std.int(size * (text.length > 2 ? 0.28 : 0.45)), 0xFFFFFF, true, null, null, null, null,
			TextFormatAlign.CENTER);
		label.text = text;
		label.height = size;
		label.y = (size - label.textHeight) / 2 - 3;
		addChild(label);

		this.x = x;
		this.y = y;
		redraw();
	}

	public function hits(stageX:Float, stageY:Float):Bool {
		// a bit of slack around the visible button makes them way easier to hit
		var slack:Float = size * 0.15;
		return stageX >= x - slack && stageX <= x + size + slack && stageY >= y - slack && stageY <= y + size + slack;
	}

	public function setPressed(value:Bool):Void {
		if (pressed == value)
			return;
		pressed = value;
		redraw();
	}

	function redraw():Void {
		graphics.clear();
		graphics.lineStyle(3, 0xFFFFFF, pressed ? 0.9 : baseAlpha + 0.2);
		graphics.beginFill(pressed ? 0x5FCBFF : 0x000000, pressed ? 0.55 : baseAlpha);
		graphics.drawRoundRect(0, 0, size, size, size * 0.3, size * 0.3);
		graphics.endFill();
	}
}

/**
 * One lane of the hitbox: a tall transparent column in the color of the arrow, it lights up while it's touched.
 */
private class HitboxLane extends Sprite {
	var laneWidth:Float;
	var laneHeight:Float;
	var color:Int;
	var opacity:Float;
	var pressed:Bool = false;

	public function new(x:Float, laneWidth:Float, laneHeight:Float, color:Int, opacity:Float) {
		super();
		this.laneWidth = laneWidth;
		this.laneHeight = laneHeight;
		this.color = color;
		this.opacity = opacity;

		mouseEnabled = false;
		mouseChildren = false;

		this.x = x;
		redraw();
	}

	public function setPressed(value:Bool):Void {
		if (pressed == value)
			return;
		pressed = value;
		redraw();
	}

	function redraw():Void {
		graphics.clear();

		// the column itself
		graphics.beginFill(color, pressed ? Math.min(1, opacity * 2.4) : opacity);
		graphics.drawRect(0, 0, laneWidth, laneHeight);
		graphics.endFill();

		// a brighter edge on the sides so the lanes are easy to tell apart
		graphics.lineStyle(2, color, pressed ? 0.9 : Math.min(1, opacity * 2));
		graphics.drawRect(1, 1, laneWidth - 2, laneHeight - 2);
	}
}

/**
 * On screen touch controls.
 *
 * The engine reads its input from the keyboard (`FlxG.keys` and `Controls`), so instead of changing every state
 * the touch controls simply press and release the same keys the player would use, this means
 * the key binds set in the options menu are respected and every mod / script keeps working.
 *
 * - In menus a D-pad and accept / back buttons are shown. Touching the screen also works like a mouse click (handled by Flixel).
 * - While playing a song the screen is split into one lane per note column (using the player's binds for that key count)
 *   and there is a pause button in the top right corner.
 *
 * Optional settings are read from `mobile_config.json`:
 * ```json
 * {
 *   "overlayEnabled": true,   // show the buttons / lane guides
 *   "buttonAlpha": 0.35,      // how visible the buttons are
 *   "slideLanes": false       // let a finger slide from one lane to another while holding
 * }
 * ```
 */
class MobileInput extends Sprite {
	static var instance:MobileInput;

	var mode:Mode = MENU;
	var layoutKey:String = "";
	var frame:Int = 0;

	var overlayEnabled:Bool = true;
	var buttonAlpha:Float = 0.35;
	var slideLanes:Bool = false;

	var buttons:Array<VirtualButton> = [];
	var lanes:Array<HitboxLane> = [];
	var laneKeys:Array<Int> = [];
	var laneColors:Array<Int> = [];

	/**
	 * Settings from `Options > Mobile Options`.
	 */
	var hitboxVisible:Bool = true;
	var hitboxOpacity:Float = 0.2;

	/**
	 * Which button / lane each finger is currently holding.
	 */
	var touchButtons:Map<Int, VirtualButton> = new Map();

	var touchLanes:Map<Int, Int> = new Map();

	/**
	 * How many fingers hold each key and the frame it was pressed on.
	 */
	var keyHolds:Map<Int, Int> = new Map();

	var keyPressFrame:Map<Int, Int> = new Map();
	var pendingReleases:Array<Int> = [];

	public static function initialize():Void {
		if (instance != null || Lib.current == null || Lib.current.stage == null)
			return;

		Multitouch.inputMode = MultitouchInputMode.TOUCH_POINT;

		instance = new MobileInput();

		var stage = Lib.current.stage;
		stage.addChild(instance);
		stage.addEventListener(TouchEvent.TOUCH_BEGIN, instance.onTouchBegin);
		stage.addEventListener(TouchEvent.TOUCH_MOVE, instance.onTouchMove);
		stage.addEventListener(TouchEvent.TOUCH_END, instance.onTouchEnd);
		stage.addEventListener(Event.ENTER_FRAME, instance.onFrame);
		stage.addEventListener(Event.DEACTIVATE, instance.onDeactivate);
	}

	function new() {
		super();
		mouseEnabled = false;
		mouseChildren = false;
		readConfig();
	}

	function readConfig():Void {
		try {
			if (Assets.exists("mobile_config.json")) {
				var config:Dynamic = Json.parse(Assets.getText("mobile_config.json"));
				if (Reflect.hasField(config, "overlayEnabled"))
					overlayEnabled = Reflect.field(config, "overlayEnabled") == true;
				if (Reflect.hasField(config, "buttonAlpha"))
					buttonAlpha = Math.max(0.05, Math.min(1, Reflect.field(config, "buttonAlpha")));
				if (Reflect.hasField(config, "slideLanes"))
					slideLanes = Reflect.field(config, "slideLanes") == true;
			}
		} catch (e:Dynamic) {
			// invalid config, the defaults are fine
		}
	}

	// ------------------------------------------------------------------ layout

	function onFrame(_:Event):Void {
		frame++;

		var newMode:Mode = getWantedMode();
		var newKey:String = '$newMode:${Lib.current.stage.stageWidth}x${Lib.current.stage.stageHeight}';

		readOptions();

		if (newMode == GAME) {
			laneKeys = getLaneKeys();
			newKey += ':${laneKeys.join(",")}:$hitboxVisible:$hitboxOpacity';
		} else if (FlxG.state is TitleState) {
			newKey += ":title";
		}

		if (newKey != layoutKey) {
			releaseEverything();
			mode = newMode;
			layoutKey = newKey;
			buildLayout();
		}

		// light up the lanes that are being held
		for (i in 0...lanes.length) {
			var holds:Int = keyHolds.exists(laneKeys[i]) ? keyHolds.get(laneKeys[i]) : 0;
			lanes[i].setPressed(holds > 0);
		}

		// a key must stay down for a couple of frames, otherwise very quick taps could
		// be pressed and released before the game ever gets to see them
		var i:Int = pendingReleases.length;
		while (i-- > 0) {
			var code:Int = pendingReleases[i];
			if (frame >= keyPressFrame.get(code) + 2) {
				pendingReleases.splice(i, 1);
				dispatchKey(code, false);
			}
		}
	}

	/**
	 * Reads the settings from `Options > Mobile Options`.
	 */
	function readOptions():Void {
		try {
			var visible:Dynamic = Options.getData("hitboxVisible");
			if (visible != null)
				hitboxVisible = visible == true;

			var opacity:Dynamic = Options.getData("hitboxOpacity");
			if (opacity != null)
				hitboxOpacity = Math.max(0.05, Math.min(0.9, Std.parseFloat(Std.string(opacity)) / 100));
		} catch (e:Dynamic) {
			// the options aren't loaded yet, the defaults are fine
		}
	}

	/**
	 * The color of every lane, the same as the arrow of that column.
	 */
	function getLaneColors(count:Int):Array<Int> {
		var colors:Array<Int> = [];
		var fallback:Array<Int> = [0xC24B99, 0x00FFFF, 0x12FA05, 0xF9393F];

		for (i in 0...count) {
			var color:Int = fallback[i % fallback.length];

			try {
				var keyCount:Int = PlayState.SONG.playerKeyCount;
				var direction:String = NoteVariables.animationDirections[keyCount - 1][i];
				var rgb:Array<Int> = NoteColors.getNoteColor(direction);
				color = (Std.int(rgb[0]) << 16) | (Std.int(rgb[1]) << 8) | Std.int(rgb[2]);
			} catch (e:Dynamic) {}

			colors.push(color);
		}

		return colors;
	}

	function getWantedMode():Mode {
		var state = FlxG.state;
		if (state is PlayState && state.subState == null)
			return GAME;
		return MENU;
	}

	/**
	 * The keys of every lane, taken from the player's binds for the current key count.
	 */
	function getLaneKeys():Array<Int> {
		var keys:Array<Int> = [];

		try {
			var count:Int = PlayState.SONG.playerKeyCount;
			var binds:Array<String> = Options.getData("binds", "binds")[count - 1];

			for (bind in binds)
				keys.push(FlxKey.fromString(bind));
		} catch (e:Dynamic) {
			keys = [];
		}

		if (keys.length == 0)
			keys = [Keyboard.LEFT, Keyboard.DOWN, Keyboard.UP, Keyboard.RIGHT];

		return keys;
	}

	function getPauseKey():Int {
		try {
			var key:Int = FlxKey.fromString(Options.getData("pauseBind", "binds"));
			if (key > 0)
				return key;
		} catch (e:Dynamic) {}
		return Keyboard.ENTER;
	}

	function buildLayout():Void {
		for (button in buttons)
			removeChild(button);
		buttons = [];

		for (lane in lanes)
			removeChild(lane);
		lanes = [];

		graphics.clear();

		var stageWidth:Float = Lib.current.stage.stageWidth;
		var stageHeight:Float = Lib.current.stage.stageHeight;

		switch (mode) {
			case GAME:
				// the hitbox: one column per lane over the whole screen, it adapts to any key count and any screen size
				laneColors = getLaneColors(laneKeys.length);

				var laneWidth:Float = stageWidth / laneKeys.length;
				for (i in 0...laneKeys.length) {
					var lane:HitboxLane = new HitboxLane(laneWidth * i, laneWidth, stageHeight, laneColors[i], hitboxOpacity);
					lane.visible = hitboxVisible;
					lanes.push(lane);
					addChild(lane);
				}

				var size:Float = Math.min(stageWidth, stageHeight) * 0.11;
				addButton(getPauseKey(), "II", stageWidth - size - size * 0.4, size * 0.4, size);
			case MENU:
				{
					var size:Float = Math.min(stageWidth, stageHeight) * 0.14;
					var margin:Float = size * 0.35;

					// D-pad (bottom left)
					var dpadX:Float = margin;
					var dpadY:Float = stageHeight - margin - size * 3;
					addButton(Keyboard.UP, "▲", dpadX + size, dpadY, size);
					addButton(Keyboard.LEFT, "◀", dpadX, dpadY + size, size);
					addButton(Keyboard.RIGHT, "▶", dpadX + size * 2, dpadY + size, size);
					addButton(Keyboard.DOWN, "▼", dpadX + size, dpadY + size * 2, size);

					// accept / back (bottom right)
					var bigSize:Float = size * 1.15;
					addButton(Keyboard.ENTER, "A", stageWidth - margin - bigSize, stageHeight - margin - bigSize * 1.9, bigSize);
					addButton(Keyboard.ESCAPE, "B", stageWidth - margin - bigSize * 2.2, stageHeight - margin - bigSize, bigSize);

					#if MODDING_ALLOWED
					// the mod switcher lives on TAB in the title screen
					if (FlxG.state is TitleState)
						addButton(Keyboard.TAB, "MODS", stageWidth - size * 1.4, size * 0.4, size);
					#end
				}
		}
	}

	function addButton(keyCode:Int, text:String, x:Float, y:Float, size:Float):Void {
		var button:VirtualButton = new VirtualButton(keyCode, text, x, y, size, buttonAlpha);
		// with the overlay turned off the buttons are invisible but can still be touched
		button.visible = overlayEnabled;
		buttons.push(button);
		addChild(button);
	}

	// ------------------------------------------------------------------ touch handling

	function getButtonAt(x:Float, y:Float):Null<VirtualButton> {
		for (button in buttons) {
			if (button.hits(x, y))
				return button;
		}
		return null;
	}

	function getLaneAt(x:Float):Int {
		var count:Int = laneKeys.length;
		var lane:Int = Std.int(x / (Lib.current.stage.stageWidth / count));
		return Std.int(Math.max(0, Math.min(count - 1, lane)));
	}

	function onTouchBegin(event:TouchEvent):Void {
		var id:Int = event.touchPointID;

		var button:Null<VirtualButton> = getButtonAt(event.stageX, event.stageY);
		if (button != null) {
			touchButtons.set(id, button);
			button.setPressed(true);
			pressKey(button.keyCode);
			return;
		}

		if (mode == GAME) {
			var lane:Int = getLaneAt(event.stageX);
			touchLanes.set(id, lane);
			pressKey(laneKeys[lane]);
		}
	}

	function onTouchMove(event:TouchEvent):Void {
		if (mode != GAME || !slideLanes)
			return;

		var id:Int = event.touchPointID;
		if (!touchLanes.exists(id))
			return;

		var previous:Int = touchLanes.get(id);
		var current:Int = getLaneAt(event.stageX);
		if (previous == current)
			return;

		releaseKey(laneKeys[previous]);
		touchLanes.set(id, current);
		pressKey(laneKeys[current]);
	}

	function onTouchEnd(event:TouchEvent):Void {
		var id:Int = event.touchPointID;

		if (touchButtons.exists(id)) {
			var button:VirtualButton = touchButtons.get(id);
			touchButtons.remove(id);
			button.setPressed(false);
			releaseKey(button.keyCode);
		}

		if (touchLanes.exists(id)) {
			var lane:Int = touchLanes.get(id);
			touchLanes.remove(id);
			if (lane < laneKeys.length)
				releaseKey(laneKeys[lane]);
		}
	}

	function onDeactivate(_:Event):Void {
		// the app went to the background, don't leave keys stuck
		releaseEverything();
	}

	function releaseEverything():Void {
		for (button in touchButtons)
			button.setPressed(false);

		touchButtons.clear();
		touchLanes.clear();

		for (code in pendingReleases)
			dispatchKey(code, false);
		pendingReleases = [];

		for (code in keyHolds.keys()) {
			if (keyHolds.get(code) > 0)
				dispatchKey(code, false);
		}
		keyHolds.clear();
	}

	// ------------------------------------------------------------------ keys

	function pressKey(code:Int):Void {
		var holds:Int = keyHolds.exists(code) ? keyHolds.get(code) : 0;
		keyHolds.set(code, holds + 1);

		// it's being held again so a release that was waiting is cancelled
		pendingReleases.remove(code);

		if (holds == 0) {
			keyPressFrame.set(code, frame);
			dispatchKey(code, true);
		}
	}

	function releaseKey(code:Int):Void {
		var holds:Int = keyHolds.exists(code) ? keyHolds.get(code) : 0;
		if (holds <= 0)
			return;

		keyHolds.set(code, holds - 1);
		if (holds - 1 > 0)
			return;

		if (frame >= keyPressFrame.get(code) + 2)
			dispatchKey(code, false);
		else
			pendingReleases.push(code);
	}

	static function dispatchKey(code:Int, down:Bool):Void {
		if (code <= 0 || Lib.current == null || Lib.current.stage == null)
			return;

		var type:String = down ? KeyboardEvent.KEY_DOWN : KeyboardEvent.KEY_UP;
		Lib.current.stage.dispatchEvent(new KeyboardEvent(type, true, false, 0, code, 0, false, false, false, false));
	}
}
#end
