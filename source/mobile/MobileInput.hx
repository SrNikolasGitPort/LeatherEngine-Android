package mobile;

import haxe.Json;
import lime.utils.Assets;
import openfl.display.Sprite;
import openfl.events.KeyboardEvent;
import openfl.events.TouchEvent;
import openfl.Lib;
import openfl.ui.Keyboard;

class MobileInput extends Sprite {
	static var instance:MobileInput;

	var touchIdToColumn:Map<Int, Int> = new Map();
	var touchIdToStartX:Map<Int, Float> = new Map();
	var touchIdToStartY:Map<Int, Float> = new Map();
	var debugEnabled:Bool = true;

	public static function initialize():Void {
		if (instance != null)
			return;

		instance = new MobileInput();
		if (Lib.current == null || Lib.current.stage == null)
			return;

		Lib.current.stage.addChild(instance);
		Lib.current.stage.addEventListener(TouchEvent.TOUCH_BEGIN, instance.onTouchBegin);
		Lib.current.stage.addEventListener(TouchEvent.TOUCH_MOVE, instance.onTouchMove);
		Lib.current.stage.addEventListener(TouchEvent.TOUCH_END, instance.onTouchEnd);
		Lib.current.stage.addEventListener(TouchEvent.TOUCH_OUT, instance.onTouchEnd);
		instance.layoutOverlay();
	}

	function new() {
		super();
		mouseEnabled = false;
		mouseChildren = false;
		var config = readConfig();
		if (config != null && Reflect.hasField(config, "overlayEnabled"))
			debugEnabled = Reflect.field(config, "overlayEnabled") == true;
	}

	function readConfig():Dynamic {
		try {
			if (Assets.exists("mobile_config.json")) {
				var text = Assets.getText("mobile_config.json");
				if (text != null && text.length > 0)
					return Json.parse(text);
			}
		} catch (e:Dynamic) {
			// Ignore invalid config and fall back to defaults.
		}
		return null;
	}

	function layoutOverlay():Void {
		graphics.clear();
		if (!debugEnabled || Lib.current == null || Lib.current.stage == null)
			return;

		var stageWidth:Float = Lib.current.stage.stageWidth;
		var stageHeight:Float = Lib.current.stage.stageHeight;
		var columns:Int = getColumnCount();
		var segmentWidth:Float = stageWidth / columns;
		var bottomY:Float = stageHeight * 0.55;
		var bottomHeight:Float = stageHeight * 0.45;

		graphics.beginFill(0x5fcbff, 0.12);
		for (i in 0...columns) {
			var x:Float = i * segmentWidth + 2;
			graphics.drawRect(x, bottomY, segmentWidth - 4, bottomHeight);
		}
		graphics.endFill();
	}

	function onTouchBegin(event:TouchEvent):Void {
		var id:Int = event.touchPointID;
		var x:Float = event.stageX;
		var y:Float = event.stageY;
		touchIdToStartX.set(id, x);
		touchIdToStartY.set(id, y);

		if (isGameplayTouch(x, y)) {
			var col:Int = getGameplayColumn(x);
			touchIdToColumn.set(id, col);
			if (col != null)
				dispatchKey(keyCodeForColumn(col), true);
			return;
		}

		// Menu navigation / general engine controls.
		var dx:Float = x - touchIdToStartX.get(id);
		var dy:Float = y - touchIdToStartY.get(id);
		if (Math.abs(dx) > 60 || Math.abs(dy) > 60) {
			if (Math.abs(dx) > Math.abs(dy)) {
				dispatchKey(dx > 0 ? Keyboard.RIGHT : Keyboard.LEFT, true);
			} else {
				dispatchKey(dy > 0 ? Keyboard.DOWN : Keyboard.UP, true);
			}
			return;
		}

		dispatchKey(Keyboard.ENTER, true);
	}

	function onTouchMove(event:TouchEvent):Void {
		var id:Int = event.touchPointID;
		if (!touchIdToColumn.exists(id))
			return;

		var currentCol:Int = getGameplayColumn(event.stageX);
		var previousCol:Int = touchIdToColumn.get(id);
		if (previousCol == currentCol)
			return;

		dispatchKey(keyCodeForColumn(previousCol), false);
		if (currentCol != null) {
			touchIdToColumn.set(id, currentCol);
			dispatchKey(keyCodeForColumn(currentCol), true);
		} else {
			touchIdToColumn.remove(id);
		}
	}

	function onTouchEnd(event:TouchEvent):Void {
		var id:Int = event.touchPointID;
		if (touchIdToColumn.exists(id)) {
			dispatchKey(keyCodeForColumn(touchIdToColumn.get(id)), false);
			touchIdToColumn.remove(id);
		}
	}

	static function getColumnCount():Int {
		var config:Dynamic = null;
		try {
			if (Assets.exists("mobile_config.json")) {
				config = Json.parse(Assets.getText("mobile_config.json"));
			}
		} catch (e:Dynamic) {
			config = null;
		}
		if (config != null && Reflect.hasField(config, "columns")) {
			var value:Int = Std.int(Reflect.field(config, "columns"));
			if (value > 0)
				return value;
		}
		return 4;
	}

	static function isGameplayTouch(x:Float, y:Float):Bool {
		if (Lib.current == null || Lib.current.stage == null)
			return false;
		return y >= Lib.current.stage.stageHeight * 0.55;
	}

	static function getGameplayColumn(x:Float):Int {
		if (Lib.current == null || Lib.current.stage == null)
			return null;
		var count:Int = getColumnCount();
		var segment:Float = Lib.current.stage.stageWidth / count;
		var index:Int = Std.int(x / segment);
		return Math.max(0, Math.min(count - 1, index));
	}

	static function keyCodeForColumn(column:Int):Int {
		var columns:Int = getColumnCount();
		var index:Int = Std.int(Math.abs(column)) % columns;
		var codes:Array<Int> = [
			Keyboard.LEFT,
			Keyboard.DOWN,
			Keyboard.UP,
			Keyboard.RIGHT,
			Keyboard.A,
			Keyboard.S,
			Keyboard.W,
			Keyboard.D,
			Keyboard.F,
			Keyboard.G,
			Keyboard.H,
			Keyboard.J,
			Keyboard.K,
			Keyboard.L,
			Keyboard.Z,
			Keyboard.X,
			Keyboard.C,
			Keyboard.V,
			Keyboard.B,
			Keyboard.N,
			Keyboard.M
		];
		return codes[Math.max(0, Math.min(codes.length - 1, index))];
	}

	static function dispatchKey(code:Int, down:Bool):Void {
		if (code == 0 || Lib.current == null || Lib.current.stage == null)
			return;
		var type:String = down ? KeyboardEvent.KEY_DOWN : KeyboardEvent.KEY_UP;
		var event:KeyboardEvent = new KeyboardEvent(type, true, false, 0, code, 0, false, false, false, false);
		Lib.current.stage.dispatchEvent(event);
	}
}
