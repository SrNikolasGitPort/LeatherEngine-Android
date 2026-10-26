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
		graphics.drawRoundRect(0, 0, buttonWidth, size, size * 0.3, size * 0.3);
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

	public function setPressed(value:Bool):Void {
		if (pressed == value)
			return;
		pressed = value;
		redraw();
	}

	function redraw():Void {
		graphics.clear();

		if (hideIdle && !pressed)
			return;

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

	function onFrame(_:Event):Void {
		frame++;

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

		if (mode == TAP) {
			tapTouches.set(id, true);
			pressKey(Keyboard.ENTER);
			return;
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
		// Flixel treats "charCode 0 + keyCode 80..90" as the F1..F11 keys (a quirk of the native keyboard on desktop),
		// so a letter pressed with charCode 0 (P Q R S T U V W X Y Z) would never arrive as that letter.
		// Giving letters their real character code avoids it.
		var charCode:Int = (code >= 65 && code <= 90) ? code + 32 : 0;
		Lib.current.stage.dispatchEvent(new KeyboardEvent(type, true, false, charCode, code, 0, false, false, false, false));
	}
}
#end
