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
import openfl.events.TextEvent;
import lime.system.JNI;
import flixel.group.FlxGroup.FlxTypedGroup;
import flixel.group.FlxSpriteGroup.FlxTypedSpriteGroup;
import flixel.text.FlxInputText;
import flixel.addons.ui.FlxInputText as LegacyInputText;
import openfl.events.TouchEvent;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import openfl.ui.Keyboard;
import openfl.ui.Multitouch;
import openfl.ui.MultitouchInputMode;
import shaders.NoteColors;
import states.FlashingLightsMenu;
import states.FreeplayState;
import states.LoadingState;
import states.MainMenuState;
import states.PlayState;
import states.StoryMenuState;
import states.TitleState;
import substates.GameOverSubstate;
import substates.PauseSubState;
import substates.ResultsSubstate;
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

	/**
	 * The flashing lights question: only big Y and N buttons.
	 */
	PROMPT;

	/**
	 * Nothing on screen (title screen, loading screens, after a song was picked).
	 */
	HIDDEN;

	/**
	 * No buttons at all, touching anywhere on the screen counts as ENTER (result screen, cutscenes).
	 */
	TAP;

	/**
	 * Game over screen: only A (ENTER, try again) and B (ESC, leave).
	 */
	DEAD;

	/**
	 * Chart editor and the other tools: a bar with the keys the editors use.
	 */
	EDITOR;
}

/**
 * A single on screen button that holds down a keyboard key while it is touched.
 */
private class VirtualButton extends Sprite {
	public var keyCode(default, null):Int;
	public var size(default, null):Float;

	/**
	 * Width of the button, it is the same as `size` unless the button has a description next to its name (editors).
	 */
	public var buttonWidth(default, null):Float;

	/**
	 * Toggle buttons stay held after a touch (SHIFT / CTRL in the editors) and are released by touching them again.
	 */
	public var toggle:Bool = false;

	var label:TextField;
	var pressed:Bool = false;
	var baseAlpha:Float;

	public function new(keyCode:Int, text:String, x:Float, y:Float, size:Float, baseAlpha:Float, ?width:Float) {
		super();
		this.keyCode = keyCode;
		this.size = size;
		this.buttonWidth = width ?? size;
		this.baseAlpha = baseAlpha;

		mouseEnabled = false;
		mouseChildren = false;

		label = new TextField();
		label.selectable = false;
		label.mouseEnabled = false;
		label.autoSize = TextFieldAutoSize.NONE;
		label.width = buttonWidth;
		var fontSize:Int = Std.int(size * (text.length > 2 ? 0.28 : 0.45));
		if (buttonWidth > size)
			fontSize = Std.int(Math.min(size * 0.4, buttonWidth / (text.length * 0.6)));
		label.defaultTextFormat = new TextFormat("_sans", fontSize, 0xFFFFFF, true, null, null, null, null, TextFormatAlign.CENTER);
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
		return stageX >= x - slack && stageX <= x + buttonWidth + slack && stageY >= y - slack && stageY <= y + size + slack;
	}

	public function isPressed():Bool {
		return pressed;
	}

	var idleLayer:Sprite;
	var litLayer:Sprite;

	public function setPressed(value:Bool):Void {
		if (pressed == value)
			return;
		pressed = value;
		litLayer.visible = value;
		idleLayer.visible = !value;
	}

	// both looks are drawn once and only switched when touched
	function redraw():Void {
		idleLayer = new Sprite();
		litLayer = new Sprite();
		drawLayer(idleLayer.graphics, false);
		drawLayer(litLayer.graphics, true);
		litLayer.visible = false;
		addChildAt(idleLayer, 0);
		addChildAt(litLayer, 1);
	}

	function drawLayer(graphics:openfl.display.Graphics, pressed:Bool):Void {
		graphics.lineStyle(3, 0xFFFFFF, pressed ? 0.9 : baseAlpha + 0.2);
		graphics.beginFill(pressed ? 0x5FCBFF : 0x000000, pressed ? 0.55 : baseAlpha);
		graphics.drawRoundRect(0, 0, buttonWidth, size, size * 0.3, size * 0.3);
		graphics.endFill();
	}
}

/**
 * The D-pad of the menus: one round pad split into four directions. It is a single touch area, so the thumb can rest on it and slide
 * from one direction to another without lifting (the four separate buttons it replaces lost the touch at every edge).
 */
private class DPad extends Sprite {
	public static final KEYS:Array<Int> = [Keyboard.UP, Keyboard.RIGHT, Keyboard.DOWN, Keyboard.LEFT];

	public var radius(default, null):Float;
	public var centerX(default, null):Float;
	public var centerY(default, null):Float;

	var layers:Array<Sprite> = [];
	var current:Int = -1;

	public function new(centerX:Float, centerY:Float, radius:Float, alpha:Float) {
		super();
		this.radius = radius;
		this.centerX = centerX;
		this.centerY = centerY;
		mouseEnabled = false;
		mouseChildren = false;
		x = centerX;
		y = centerY;

		// the pad itself
		graphics.lineStyle(3, 0xFFFFFF, alpha + 0.2);
		graphics.beginFill(0x000000, alpha);
		graphics.drawCircle(0, 0, radius);
		graphics.endFill();
		graphics.lineStyle(2, 0xFFFFFF, alpha + 0.1);
		graphics.moveTo(-radius * 0.7, -radius * 0.7);
		graphics.lineTo(radius * 0.7, radius * 0.7);
		graphics.moveTo(radius * 0.7, -radius * 0.7);
		graphics.lineTo(-radius * 0.7, radius * 0.7);

		// one highlight per direction, drawn once and only shown / hidden afterwards
		for (i in 0...4) {
			var layer:Sprite = new Sprite();
			var a0:Float = (i * 90 - 135) * Math.PI / 180;
			layer.graphics.beginFill(0x5FCBFF, 0.5);
			layer.graphics.moveTo(0, 0);
			layer.graphics.lineTo(Math.cos(a0) * radius, Math.sin(a0) * radius);
			for (s in 1...13) {
				var a:Float = a0 + s * (Math.PI / 2) / 12;
				layer.graphics.lineTo(Math.cos(a) * radius, Math.sin(a) * radius);
			}
			layer.graphics.lineTo(0, 0);
			layer.graphics.endFill();
			layer.visible = false;
			layers.push(layer);
			addChild(layer);
		}

		// the arrows
		var marks:Array<String> = ["▲", "▶", "▼", "◀"];
		var marksX:Array<Float> = [0, 1, 0, -1];
		var marksY:Array<Float> = [-1, 0, 1, 0];
		for (i in 0...4) {
			var text:TextField = new TextField();
			text.selectable = false;
			text.mouseEnabled = false;
			text.defaultTextFormat = new TextFormat("_sans", Std.int(radius * 0.4), 0xFFFFFF, true, null, null, null, null, TextFormatAlign.CENTER);
			text.text = marks[i];
			text.width = radius * 0.7;
			text.height = radius * 0.7;
			text.x = marksX[i] * radius * 0.58 - text.width / 2;
			text.y = marksY[i] * radius * 0.58 - text.height * 0.5 + 2;
			addChild(text);
		}
	}

	/**
	 * Direction (0 up, 1 right, 2 down, 3 left) under a point, `-1` outside of the pad or in its middle.
	 */
	public function directionAt(stageX:Float, stageY:Float):Int {
		var dx:Float = stageX - centerX;
		var dy:Float = stageY - centerY;
		var distance:Float = Math.sqrt(dx * dx + dy * dy);

		// the touch area is bigger than what is drawn, a thumb never hits exactly
		if (distance > radius * 1.25 || distance < radius * 0.12)
			return -1;

		if (Math.abs(dx) > Math.abs(dy))
			return dx > 0 ? 1 : 3;
		return dy > 0 ? 2 : 0;
	}

	public function setDirection(direction:Int):Void {
		if (direction == current)
			return;
		if (current >= 0)
			layers[current].visible = false;
		current = direction;
		if (current >= 0)
			layers[current].visible = true;
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

	/**
	 * `Hide Hitbox Hint`: the lane is invisible until it is touched.
	 */
	var hideIdle:Bool;

	/**
	 * V-Slice style: the color fades in from the top of the screen to the strum line at the bottom.
	 */
	var gradient:Bool;

	public function new(x:Float, laneWidth:Float, laneHeight:Float, color:Int, opacity:Float, hideIdle:Bool = false, gradient:Bool = false) {
		super();
		this.hideIdle = hideIdle;
		this.gradient = gradient;
		this.laneWidth = laneWidth;
		this.laneHeight = laneHeight;
		this.color = color;
		this.opacity = opacity;

		mouseEnabled = false;
		mouseChildren = false;

		this.x = x;
		redraw();
	}

	// Both looks are drawn once. Drawing the vector graphics again every time a lane is touched or let go (a whole screen tall column)
	// took long enough to be felt as a delay when tapping.
	var idleLayer:Sprite;
	var litLayer:Sprite;

	public function setPressed(value:Bool):Void {
		if (pressed == value)
			return;
		pressed = value;
		litLayer.visible = value;
		idleLayer.visible = !value && !hideIdle;
	}

	function redraw():Void {
		idleLayer = new Sprite();
		litLayer = new Sprite();
		idleLayer.mouseEnabled = litLayer.mouseEnabled = false;
		drawLayer(idleLayer.graphics, false);
		drawLayer(litLayer.graphics, true);
		idleLayer.visible = !hideIdle;
		litLayer.visible = false;
		addChild(idleLayer);
		addChild(litLayer);
	}

	function drawLayer(graphics:openfl.display.Graphics, pressed:Bool):Void {
		var fill:Float = pressed ? Math.min(1, opacity * 2.4) : opacity;

		// the column itself
		if (gradient) {
			var matrix:openfl.geom.Matrix = new openfl.geom.Matrix();
			matrix.createGradientBox(laneWidth, laneHeight, Math.PI / 2, 0, 0);
			graphics.beginGradientFill(openfl.display.GradientType.LINEAR, [color, color], [0, Math.min(1, fill * 2.2)], [0, 255], matrix);
		} else
			graphics.beginFill(color, fill);
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
 *   "slideLanes": true        // let a finger slide from one lane to another while holding
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
	var slideLanes:Bool = true;

	/**
	 * Set when a song / week was picked: the buttons go away until the next state is ready.
	 */
	static var hideFlag:Bool = false;

	/**
	 * Fingers that are holding the "C" (speed) button, and where they started.
	 */
	var speedTouches:Map<Int, Float> = new Map();

	/**
	 * Fingers that are tapping the screen in `TAP` mode.
	 */
	var tapTouches:Map<Int, Bool> = new Map();

	var speedSteps:Int = 0;
	var nextTapFrame:Int = 0;

	var buttons:Array<VirtualButton> = [];
	var lanes:Array<HitboxLane> = [];
	var laneKeys:Array<Int> = [];
	var laneColors:Array<Int> = [];

	/**
	 * Settings from `Options > Mobile Options`.
	 */
	var hitboxVisible:Bool = true;
	var hitboxOpacity:Float = 0.2;
	var hitboxOnGame:Bool = false;
	var hideHint:Bool = false;
	var vSliceStyle:Bool = false;

	/**
	 * V-Slice style: no hitbox columns, the arrows themselves are the buttons. `zones` has one `[left, top, width, height]` (in stage
	 * coordinates) around every arrow of the player's strum line, they are followed every frame because the strums can move.
	 */
	var useZones:Bool = false;

	var zones:Array<Array<Float>> = [];
	var zoneGlows:Array<Sprite> = [];

	/**
	 * Where the lanes are: the whole screen, or only the game image (after the black bars).
	 */
	var areaX:Float = 0;

	var areaWidth:Float = 1;

	/**
	 * Which button / lane each finger is currently holding.
	 */
	var touchButtons:Map<Int, VirtualButton> = new Map();

	var dpad:Null<DPad> = null;
	var dpadTouch:Int = -1;
	var dpadDirection:Int = -1;

	var touchLanes:Map<Int, Int> = new Map();

	/**
	 * How many fingers hold each key and the frame it was pressed on.
	 */
	var keyHolds:Map<Int, Int> = new Map();

	var keyPressFrame:Map<Int, Int> = new Map();
	var pendingReleases:Array<Int> = [];

	/**
	 * Hides the buttons until the next state is on screen (the lanes show up again once the song starts).
	 */
	public static function hideUntilNextState():Void {
		hideFlag = true;
		if (instance != null)
			instance.releaseEverything();
	}

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
		// the phone's keyboard types through text events, the legacy text boxes of the editors only understand key events
		stage.addEventListener(KeyboardEvent.KEY_DOWN, instance.onRealKeyDown, false, 100);
		stage.addEventListener(TextEvent.TEXT_INPUT, instance.onTextInput);

		// the Android back button / gesture works like ESC
		lime.app.Application.current.window.onKeyDown.add(instance.onSystemKeyDown);
		lime.app.Application.current.window.onKeyUp.add(instance.onSystemKeyUp);

		FlxG.signals.postStateSwitch.add(() -> hideFlag = false);
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

	// ------------------------------------------------------------------ phone keyboard

	var typing:Bool = false;
	var legacyTyping:Bool = false;
	var lastRealCharFrame:Int = -10;

	/**
	 * True while a text box (of the editors) is waiting for text.
	 */
	function findTyping():Bool {
		var manager = FlxInputText.globalManager;
		if (manager != null && manager.focus != null) {
			legacyTyping = false;
			return true;
		}
		legacyTyping = hasLegacyFocus(FlxG.state, 0) || (FlxG.state.subState != null && hasLegacyFocus(FlxG.state.subState, 0));
		return legacyTyping;
	}

	function hasLegacyFocus(group:Dynamic, depth:Int):Bool {
		if (group == null || depth > 8)
			return false;
		var members:Array<Dynamic> = null;
		if (Std.isOfType(group, FlxTypedGroup))
			members = cast(group, FlxTypedGroup<Dynamic>).members;
		else if (Std.isOfType(group, FlxTypedSpriteGroup))
			members = cast(group, FlxTypedSpriteGroup<Dynamic>).group.members;
		if (members == null)
			return false;
		for (m in members) {
			if (m == null)
				continue;
			if (Std.isOfType(m, LegacyInputText)) {
				if (cast(m, LegacyInputText).hasFocus)
					return true;
			} else if (hasLegacyFocus(m, depth + 1))
				return true;
		}
		return false;
	}

	function updateKeyboard():Void {
		// looking through every object each frame is wasteful, a few times a second is plenty
		if (frame % 6 != 0)
			return;

		var now:Bool = (mode == EDITOR || mode == MENU) && findTyping();
		if (now == typing)
			return;
		typing = now;

		var window = lime.app.Application.current.window;
		window.textInputEnabled = now;
		#if android
		try {
			var set:Dynamic = JNI.createStaticMethod("com/leather128/funkin/MobileStorage", "setKeyboard", "(Z)V");
			set(now);
		} catch (e:Dynamic) {}
		#end

		// the buttons would only be in the way (and be pressed by accident) while typing
		visible = !now;
		if (now)
			releaseEverything();
	}

	function onRealKeyDown(e:KeyboardEvent):Void {
		if (e.charCode != 0)
			lastRealCharFrame = frame;
	}

	function onTextInput(e:TextEvent):Void {
		// Flixel's own text boxes already read the text events
		if (!legacyTyping || e.text == null || frame - lastRealCharFrame < 3)
			return;
		for (i in 0...e.text.length) {
			var charCode:Int = e.text.charCodeAt(i);
			var keyCode:Int = FlxKey.fromString(e.text.charAt(i).toUpperCase());
			Lib.current.stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_DOWN, true, false, charCode, keyCode, 0, false, false, false, false));
			Lib.current.stage.dispatchEvent(new KeyboardEvent(KeyboardEvent.KEY_UP, true, false, charCode, keyCode, 0, false, false, false, false));
		}
	}

	function onFrame(_:Event):Void {
		frame++;
		updateKeyboard();

		// working out the layout builds strings and reads the options, which made garbage (and little hiccups) on every frame
		// of a song. The touch handling itself doesn't depend on it, so a few frames between the checks change nothing.
		if (frame % 4 == 0 || layoutKey == "")
			updateLayout();

		updateRest();
	}

	function updateLayout():Void {
		var newMode:Mode = getWantedMode();
		var newKey:String = '$newMode:${Lib.current.stage.stageWidth}x${Lib.current.stage.stageHeight}';

		readOptions();
		updateArea();

		if (newMode == GAME) {
			laneKeys = getLaneKeys();
			useZones = vSliceStyle && laneKeys.length == 4;
			newKey += ':${laneKeys.join(",")}:$hitboxVisible:$hitboxOpacity:$areaX:$areaWidth:$hideHint:$vSliceStyle';
		} else if (newMode == MENU || newMode == EDITOR) {
			newKey += ':' + Type.getClassName(Type.getClass(FlxG.state));
			// the mod switcher (TAB) opens over the menus and needs the full controls
			if (FlxG.state.subState != null)
				newKey += ':' + Type.getClassName(Type.getClass(FlxG.state.subState));
		}

		if (newKey != layoutKey) {
			releaseEverything();
			mode = newMode;
			layoutKey = newKey;
			buildLayout();
		}
	}

	function updateRest():Void {
		// every step of a slide on the "C" button taps LEFT / RIGHT (with SHIFT held that changes the speed)
		if (speedSteps != 0 && frame >= nextTapFrame) {
			var key:Int = speedSteps > 0 ? Keyboard.RIGHT : Keyboard.LEFT;
			speedSteps += speedSteps > 0 ? -1 : 1;
			pressKey(key);
			releaseKey(key);
			nextTapFrame = frame + 4;
		}

		if (useZones && mode == GAME)
			updateZones();

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
	 * Works out where the lanes go, see `hitboxOnGame`.
	 */
	function updateArea():Void {
		var stageWidth:Float = Lib.current.stage.stageWidth;
		areaX = 0;
		areaWidth = stageWidth;

		if (!hitboxOnGame)
			return;

		try {
			var x:Float = Math.max(0, FlxG.game.x);
			var width:Float = FlxG.scaleMode.gameSize.x;
			if (width > 0 && x + width <= stageWidth + 1) {
				areaX = Math.round(x);
				areaWidth = Math.round(width);
			}
		} catch (e:Dynamic) {}
	}

	/**
	 * Reads the settings from `Options > Mobile Options`.
	 */
	function readOptions():Void {
		try {
			var visible:Dynamic = Options.getData("hitboxVisible");
			if (visible != null)
				hitboxVisible = visible == true;

			hitboxOnGame = Options.getData("hitboxArea") == "GAME";
			hideHint = Options.getData("hideHitboxHint") == true;
			vSliceStyle = Options.getData("hitboxStyle") == "V-SLICE";

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

		if (state is PlayState) {
			var sub = state.subState;
			if (sub == null)
				return @:privateAccess cast(state, PlayState).inCutscene ? TAP : GAME;
			// the result screen has no buttons, tapping the screen is ENTER
			if (sub is GameOverSubstate)
				return DEAD;
			return sub is ResultsSubstate ? TAP : MENU;
		}

		if (hideFlag || state is TitleState || state is LoadingState)
			return HIDDEN;

		if (state is FlashingLightsMenu)
			return cast(state, FlashingLightsMenu).canInput ? PROMPT : HIDDEN;

		if (isEditor(state))
			return EDITOR;

		return MENU;
	}

	/**
	 * Keys of the open editor, `[key, label]` or `[key, label, true]` for keys that stay held (SHIFT / CTRL).
	 */
	function getEditorKeys():Array<Array<Dynamic>> {
		var name:String = Type.getClassName(Type.getClass(FlxG.state));
		// [key, text on the button, toggle]
		var shift:Array<Dynamic> = [Keyboard.SHIFT, "SHIFT - modifier", true];
		var ctrl:Array<Dynamic> = [Keyboard.CONTROL, "CTRL - modifier", true];
		var esc:Array<Dynamic> = [Keyboard.ESCAPE, "ESC - back"];

		if (name == "toolbox.ChartingState") {
			return [
				[Keyboard.SPACE, "SPACE - play / pause"],
				[Keyboard.ENTER, "ENTER - test song"],
				[Keyboard.W, "W - scroll up"],
				[Keyboard.S, "S - scroll down"],
				[Keyboard.LEFT, "◀ - previous section"],
				[Keyboard.RIGHT, "▶ - next section"],
				[Keyboard.Q, "Q - shorter hold"],
				[Keyboard.E, "E - longer hold"],
				[Keyboard.Z, "Z - zoom out"],
				[Keyboard.X, "X - zoom in"],
				[Keyboard.R, "R - reset section"],
				[Keyboard.TAB, "TAB - next tab"],
				shift,
				ctrl,
				esc
			];
		} else if (name == "toolbox.CharacterCreator") {
			return [
				[Keyboard.SPACE, "SPACE - play anim"],
				[Keyboard.W, "W - previous anim"],
				[Keyboard.S, "S - next anim"],
				[Keyboard.UP, "▲ - offset up"],
				[Keyboard.DOWN, "▼ - offset down"],
				[Keyboard.LEFT, "◀ - offset left"],
				[Keyboard.RIGHT, "▶ - offset right"],
				[Keyboard.Q, "Q - zoom out"],
				[Keyboard.E, "E - zoom in"],
				[Keyboard.Z, "Z - show stage"],
				[Keyboard.X, "X - flip side"],
				shift,
				esc
			];
		} else if (name == "toolbox.StageMakingState") {
			return [
				[Keyboard.I, "I - move up"],
				[Keyboard.K, "K - move down"],
				[Keyboard.J, "J - move left"],
				[Keyboard.L, "L - move right"],
				[Keyboard.Q, "Q - zoom out"],
				[Keyboard.E, "E - zoom in"],
				shift,
				esc
			];
		}

		// any other editor (the modcharting tools for example)
		return [
			[Keyboard.SPACE, "SPACE - play / pause"],
			[Keyboard.ENTER, "ENTER - accept"],
			[Keyboard.UP, "▲ - up"],
			[Keyboard.DOWN, "▼ - down"],
			[Keyboard.LEFT, "◀ - left"],
			[Keyboard.RIGHT, "▶ - right"],
			shift,
			ctrl,
			esc
		];
	}

	/**
	 * The tools (chart editor, character creator, stage maker...) and the modcharting tools editor.
	 */
	function isEditor(state:Dynamic):Bool {
		var name:String = Type.getClassName(Type.getClass(state));
		return (name.indexOf("toolbox.") == 0 && name != "toolbox.ToolboxState") || name.indexOf("ModchartEditor") != -1;
	}

	/**
	 * The keys of every lane, taken from the player's binds for the current key count.
	 */
	var cachedBinds:Array<String> = null;
	var cachedBindsText:String = "";
	var cachedKeys:Array<Int> = [];

	function getLaneKeys():Array<Int> {
		try {
			var count:Int = PlayState.SONG.playerKeyCount;
			var binds:Array<String> = Options.getData("binds", "binds")[count - 1];

			// this runs every frame during a song, the keys are only worked out again when the binds change
			var text:String = binds.join(",");
			if (binds == cachedBinds && text == cachedBindsText)
				return cachedKeys;

			var keys:Array<Int> = [];
			for (bind in binds)
				keys.push(FlxKey.fromString(bind));

			if (keys.length > 0) {
				cachedBinds = binds;
				cachedBindsText = text;
				cachedKeys = keys;
				return keys;
			}
		} catch (e:Dynamic) {}

		return [Keyboard.LEFT, Keyboard.DOWN, Keyboard.UP, Keyboard.RIGHT];
	}

	function getBind(name:String, fallback:Int):Int {
		try {
			var key:Int = FlxKey.fromString(Options.getData(name, "binds"));
			if (key > 0)
				return key;
		} catch (e:Dynamic) {}
		return fallback;
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

		if (dpad != null)
			removeChild(dpad);
		dpad = null;

		for (lane in lanes)
			removeChild(lane);
		lanes = [];

		for (glow in zoneGlows)
			removeChild(glow);
		zoneGlows = [];
		zones = [];

		graphics.clear();

		var stageWidth:Float = Lib.current.stage.stageWidth;
		var stageHeight:Float = Lib.current.stage.stageHeight;

		switch (mode) {
			case HIDDEN | TAP:
			case DEAD:
				{
					var size:Float = Math.min(stageWidth, stageHeight) * 0.14 * 1.15;
					var margin:Float = Math.min(stageWidth, stageHeight) * 0.14 * 0.35;
					addButton(Keyboard.ENTER, "A", stageWidth - margin - size, stageHeight - margin - size * 1.9, size);
					addButton(Keyboard.ESCAPE, "B", stageWidth - margin - size * 2.2, stageHeight - margin - size, size);
				}
			case EDITOR:
				{
					// only the keys the open editor really uses, in columns on the right edge, each one says what it does
					var size:Float = Math.min(stageWidth, stageHeight) * 0.075;
					var width:Float = size * 3.6;
					var gap:Float = size * 0.12;
					var keys:Array<Array<Dynamic>> = getEditorKeys();

					var perColumn:Int = Std.int(Math.max(1, Math.floor((stageHeight - gap) / (size + gap))));
					for (i in 0...keys.length) {
						var column:Int = Std.int(i / perColumn);
						var row:Int = i % perColumn;
						var count:Int = Std.int(Math.min(perColumn, keys.length - column * perColumn));
						var button:VirtualButton = addButton(keys[i][0], keys[i][1], stageWidth - (column + 1) * (width + gap),
							(stageHeight - count * (size + gap)) / 2 + row * (size + gap) + gap / 2, size, width);
						button.toggle = keys[i].length > 2 && keys[i][2] == true;
					}
				}
			case PROMPT:
				{
					var size:Float = Math.min(stageWidth, stageHeight) * 0.26;
					var gap:Float = size * 0.5;
					var left:Float = (stageWidth - size * 2 - gap) / 2;
					var top:Float = stageHeight - size * 1.5;
					addButton(Keyboard.Y, "Y", left, top, size);
					addButton(Keyboard.N, "N", left + size + gap, top, size);
				}
			case GAME:
				// the hitbox: one column per lane over the whole screen, it adapts to any key count and any screen size
				laneColors = getLaneColors(laneKeys.length);

				var laneWidth:Float = areaWidth / laneKeys.length;
				for (i in 0...laneKeys.length) {
					if (useZones) {
						// V-Slice style: only a soft glow on the arrow that is being touched
						var glow:Sprite = new Sprite();
						glow.mouseEnabled = false;
						glow.graphics.beginFill(laneColors[i], 1);
						glow.graphics.drawCircle(0, 0, 100);
						glow.graphics.endFill();
						glow.visible = false;
						zoneGlows.push(glow);
						addChild(glow);
						continue;
					}

					var lane:HitboxLane = new HitboxLane(areaX + laneWidth * i, laneWidth, stageHeight, laneColors[i], hitboxOpacity, hideHint);
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

					// the main menu is moved by touch, the only button there is MODS
					if (FlxG.state is MainMenuState && FlxG.state.subState == null) {
						#if MODDING_ALLOWED
						addButton(Keyboard.TAB, "MODS", stageWidth - size * 1.4, size * 0.4, size);
						#end
						return;
					}

					// D-pad (bottom left): a single round pad
					var padRadius:Float = size * 1.5;
					dpad = new DPad(margin + padRadius, stageHeight - margin - padRadius, padRadius, buttonAlpha);
					dpad.visible = overlayEnabled;
					addChild(dpad);

					// accept / back (bottom right)
					var bigSize:Float = size * 1.15;
					addButton(Keyboard.ENTER, "A", stageWidth - margin - bigSize, stageHeight - margin - bigSize * 1.9, bigSize);
					addButton(Keyboard.ESCAPE, "B", stageWidth - margin - bigSize * 2.2, stageHeight - margin - bigSize, bigSize);

					#if MODDING_ALLOWED
					// the mod switcher lives on TAB
					if (FlxG.state is MainMenuState || FlxG.state is FreeplayState)
						addButton(Keyboard.TAB, "MODS", stageWidth - size * 1.4, size * 0.4, size);
					#end

					var extraX:Float = stageWidth - margin - bigSize * 3.4;
					var extraY:Float = stageHeight - margin - bigSize * 2.2;
					var resetX:Float = stageWidth - margin - bigSize * 2.2;

					if (FlxG.state is FreeplayState) {
						// hold C (SHIFT) and slide left / right to change the song speed
						addButton(Keyboard.SHIFT, "C", extraX, stageHeight - margin - bigSize, bigSize);
						// X listens to the song, Y resets the score
						addButton(Keyboard.SPACE, "X", extraX, extraY, bigSize);
						addButton(getBind("kill", Keyboard.R), "Y", resetX, extraY, bigSize);
					} else if (FlxG.state is StoryMenuState) {
						// Q / E change the week group, Y resets the score of the week
						addButton(Keyboard.Q, "Q", extraX, stageHeight - margin - bigSize, bigSize);
						addButton(Keyboard.E, "E", extraX, extraY, bigSize);
						addButton(getBind("kill", Keyboard.R), "Y", resetX, extraY, bigSize);
						#if MODDING_ALLOWED
						addButton(Keyboard.TAB, "MODS", stageWidth - size * 1.4, size * 0.4, size);
						#end
					}
				}
		}
	}

	function addButton(keyCode:Int, text:String, x:Float, y:Float, size:Float, ?width:Float):VirtualButton {
		var button:VirtualButton = new VirtualButton(keyCode, text, x, y, size, buttonAlpha, width);
		// with the overlay turned off the buttons are invisible but can still be touched
		button.visible = overlayEnabled;
		buttons.push(button);
		addChild(button);
		return button;
	}

	// ------------------------------------------------------------------ touch handling

	/**
	 * Finds where the arrows of the player's strum line are on the screen and builds the touch area of each one.
	 */
	function updateZones():Void {
		var strums = @:privateAccess PlayState.playerStrums;
		var cam = @:privateAccess PlayState.instance?.camHUD;
		if (strums == null || cam == null || strums.members.length < 4)
			return;

		var scaleX:Float = FlxG.scaleMode.scale.x;
		var scaleY:Float = FlxG.scaleMode.scale.y;
		var centers:Array<Float> = [];
		var middles:Array<Float> = [];
		var heights:Array<Float> = [];

		for (i in 0...4) {
			var strum = strums.members[i];
			if (strum == null)
				return;
			var position = strum.getScreenPosition(cam);
			centers.push(FlxG.game.x + (position.x + strum.width / 2) * scaleX);
			middles.push(FlxG.game.y + (position.y + strum.height / 2) * scaleY);
			heights.push(strum.height * scaleY);
			position.put();
		}

		var stageHeight:Float = Lib.current.stage.stageHeight;
		var newZones:Array<Array<Float>> = [];

		for (i in 0...4) {
			var spacing:Float = i < 3 ? centers[i + 1] - centers[i] : centers[i] - centers[i - 1];
			var left:Float = i == 0 ? centers[i] - spacing / 2 : (centers[i] + centers[i - 1]) / 2;
			var right:Float = i == 3 ? centers[i] + spacing / 2 : (centers[i] + centers[i + 1]) / 2;
			// a generous area around the arrow, a bit more below it (where the thumb lands)
			var top:Float = Math.max(0, middles[i] - heights[i] * 1.0);
			var bottom:Float = Math.min(stageHeight, middles[i] + heights[i] * 1.4);
			newZones.push([left, top, right - left, bottom - top]);
		}
		zones = newZones;

		for (i in 0...zoneGlows.length) {
			var glow:Sprite = zoneGlows[i];
			var holds:Int = keyHolds.exists(laneKeys[i]) ? keyHolds.get(laneKeys[i]) : 0;
			glow.visible = holds > 0 && hitboxVisible && !hideHint;
			glow.alpha = Math.min(0.6, hitboxOpacity * 2.5);
			glow.x = centers[i];
			glow.y = middles[i];
			glow.scaleX = glow.scaleY = heights[i] * 0.55 / 100;
		}
	}

	function getZoneAt(x:Float, y:Float):Int {
		for (i in 0...zones.length) {
			var zone:Array<Float> = zones[i];
			if (x >= zone[0] && x <= zone[0] + zone[2] && y >= zone[1] && y <= zone[1] + zone[3])
				return i;
		}
		return -1;
	}

	function getButtonAt(x:Float, y:Float):Null<VirtualButton> {
		for (button in buttons) {
			if (button.hits(x, y))
				return button;
		}
		return null;
	}

	function getLaneAt(x:Float):Int {
		var count:Int = laneKeys.length;
		var lane:Int = Std.int((x - areaX) / (areaWidth / count));
		return Std.int(Math.max(0, Math.min(count - 1, lane)));
	}

	function onTouchBegin(event:TouchEvent):Void {
		var id:Int = event.touchPointID;

		if (typing)
			return;

		if (mode == TAP) {
			tapTouches.set(id, true);
			pressKey(Keyboard.ENTER);
			return;
		}

		if (dpad != null && dpadTouch < 0) {
			var direction:Int = dpad.directionAt(event.stageX, event.stageY);
			if (direction >= 0) {
				dpadTouch = id;
				dpadDirection = direction;
				dpad.setDirection(direction);
				pressKey(DPad.KEYS[direction]);
				return;
			}
		}

		var button:Null<VirtualButton> = getButtonAt(event.stageX, event.stageY);
		if (button != null && button.toggle) {
			// stays held until it is touched again
			var held:Bool = !button.isPressed();
			button.setPressed(held);
			if (held)
				pressKey(button.keyCode);
			else
				releaseKey(button.keyCode);
			return;
		}

		if (button != null) {
			touchButtons.set(id, button);
			if (button.keyCode == Keyboard.SHIFT)
				speedTouches.set(id, event.stageX);
			button.setPressed(true);
			pressKey(button.keyCode);
			return;
		}

		if (mode == GAME && useZones) {
			// V-Slice style: only a touch on an arrow counts
			var zone:Int = getZoneAt(event.stageX, event.stageY);
			touchLanes.set(id, zone);
			if (zone >= 0)
				pressKey(laneKeys[zone]);
		} else if (mode == GAME) {
			var lane:Int = getLaneAt(event.stageX);
			touchLanes.set(id, lane);
			pressKey(laneKeys[lane]);
		}
	}

	function onTouchMove(event:TouchEvent):Void {
		var id:Int = event.touchPointID;

		if (id == dpadTouch && dpad != null) {
			// sliding to another direction changes the key without lifting the finger
			var direction:Int = dpad.directionAt(event.stageX, event.stageY);
			if (direction != dpadDirection) {
				if (dpadDirection >= 0)
					releaseKey(DPad.KEYS[dpadDirection]);
				dpadDirection = direction;
				dpad.setDirection(direction);
				if (direction >= 0)
					pressKey(DPad.KEYS[direction]);
			}
			return;
		}

		if (speedTouches.exists(id)) {
			var step:Float = Lib.current.stage.stageWidth * 0.03;
			var moved:Float = event.stageX - speedTouches.get(id);
			var steps:Int = Std.int(moved / step);
			if (steps != 0) {
				speedTouches.set(id, speedTouches.get(id) + steps * step);
				speedSteps += steps;
			}
			return;
		}

		if (mode != GAME || !slideLanes)
			return;

		if (!touchLanes.exists(id))
			return;

		var previous:Int = touchLanes.get(id);
		var current:Int = useZones ? getZoneAt(event.stageX, event.stageY) : getLaneAt(event.stageX);
		if (previous == current)
			return;

		if (previous >= 0)
			releaseKey(laneKeys[previous]);
		touchLanes.set(id, current);
		if (current >= 0)
			pressKey(laneKeys[current]);
	}

	function onTouchEnd(event:TouchEvent):Void {
		var id:Int = event.touchPointID;

		speedTouches.remove(id);

		if (id == dpadTouch) {
			dpadTouch = -1;
			if (dpadDirection >= 0)
				releaseKey(DPad.KEYS[dpadDirection]);
			dpadDirection = -1;
			if (dpad != null)
				dpad.setDirection(-1);
		}

		if (tapTouches.exists(id)) {
			tapTouches.remove(id);
			releaseKey(Keyboard.ENTER);
		}

		if (touchButtons.exists(id)) {
			var button:VirtualButton = touchButtons.get(id);
			touchButtons.remove(id);
			button.setPressed(false);
			releaseKey(button.keyCode);
		}

		if (touchLanes.exists(id)) {
			var lane:Int = touchLanes.get(id);
			touchLanes.remove(id);
			if (lane >= 0 && lane < laneKeys.length)
				releaseKey(laneKeys[lane]);
		}
	}

	function onSystemKeyDown(code:lime.ui.KeyCode, modifier:lime.ui.KeyModifier):Void {
		if (code == lime.ui.KeyCode.APP_CONTROL_BACK)
			pressKey(Keyboard.ESCAPE);
	}

	function onSystemKeyUp(code:lime.ui.KeyCode, modifier:lime.ui.KeyModifier):Void {
		if (code == lime.ui.KeyCode.APP_CONTROL_BACK)
			releaseKey(Keyboard.ESCAPE);
	}

	function onDeactivate(_:Event):Void {
		// the app went to the background, don't leave keys stuck
		releaseEverything();
	}

	function releaseEverything():Void {
		for (button in touchButtons)
			button.setPressed(false);

		for (button in buttons) {
			if (button.toggle)
				button.setPressed(false);
		}

		touchButtons.clear();
		dpadTouch = -1;
		dpadDirection = -1;
		if (dpad != null)
			dpad.setDirection(-1);
		touchLanes.clear();
		tapTouches.clear();
		speedTouches.clear();
		speedSteps = 0;

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

		// a release was still waiting (the key was let go less than two frames ago): it is done now, otherwise the game would still
		// see the key as held and the new tap would be lost
		if (pendingReleases.remove(code)) {
			dispatchKey(code, false);
			holds = 0;
			keyHolds.set(code, 1);
		}

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
		// Flixel treats "charCode 0 + keyCode 80..90" as the F1..F11 keys (a quirk of the native keyboard on desktop),
		// so a letter pressed with charCode 0 (P Q R S T U V W X Y Z) would never arrive as that letter.
		// Giving letters their real character code avoids it.
		var charCode:Int = (code >= 65 && code <= 90) ? code + 32 : 0;
		Lib.current.stage.dispatchEvent(new KeyboardEvent(type, true, false, charCode, code, 0, false, false, false, false));
	}
}
#end
