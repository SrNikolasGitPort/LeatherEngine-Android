package mobile;

#if mobile
import lime.system.Clipboard;
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFieldAutoSize;
import openfl.text.TextFormat;
import sys.FileSystem;
import sys.io.File;

/**
 * Shown on top of everything when the engine crashes: the error, where the log was saved (`<engine folder>/crash/`)
 * and a button that copies the whole log to the clipboard.
 */
class CrashScreen extends Sprite {
	static var instance:CrashScreen = null;

	/**
	 * Remembers a crash that can't be shown right away (the process dies), it's shown the next time the engine opens.
	 */
	public static function remember(log:String, path:String):Void {
		try {
			if (!FileSystem.exists("./crash/"))
				FileSystem.createDirectory("./crash/");
			File.saveContent("./crash/last.txt", path + "\n" + log);
		} catch (e:Dynamic) {}
	}

	/**
	 * Shows the crash that happened in the last run, if there was one.
	 */
	public static function showPending():Void {
		try {
			if (!FileSystem.exists("./crash/last.txt"))
				return;
			var content:String = File.getContent("./crash/last.txt");
			FileSystem.deleteFile("./crash/last.txt");
			var split:Int = content.indexOf("\n");
			show(content.substr(split + 1), content.substr(0, split), true);
		} catch (e:Dynamic) {}
	}

	public static function show(log:String, path:String, ?previousRun:Bool = false):Void {
		try {
			if (instance != null && instance.parent != null)
				instance.parent.removeChild(instance);
			instance = new CrashScreen(log, path, previousRun);
			Lib.current.stage.addChild(instance);
		} catch (e:Dynamic) {}
	}

	var field:TextField;
	var copyLabel:TextField;
	var log:String;
	var dragY:Float = -1;

	function new(log:String, path:String, previousRun:Bool) {
		super();
		this.log = log;

		var w:Float = Lib.current.stage.stageWidth;
		var h:Float = Lib.current.stage.stageHeight;
		var unit:Float = Math.min(w, h) / 20;

		graphics.beginFill(0x120000, 0.96);
		graphics.drawRect(0, 0, w, h);
		graphics.endFill();

		var title:TextField = makeText(previousRun ? "The engine crashed last time" : "The engine crashed", unit * 1.3, 0xFF5555, true);
		title.x = unit;
		title.y = unit * 0.5;
		addChild(title);

		var where:TextField = makeText('Log saved in: $path', unit * 0.75, 0xCCCCCC, false);
		where.x = unit;
		where.y = title.y + title.height + unit * 0.2;
		where.width = w - unit * 2;
		where.wordWrap = true;
		addChild(where);

		var buttonHeight:Float = unit * 2.4;
		var top:Float = where.y + where.height + unit * 0.5;

		field = makeText(log, unit * 0.7, 0xFFFFFF, false);
		field.x = unit;
		field.y = top;
		field.width = w - unit * 2;
		field.height = h - top - buttonHeight - unit * 1.5;
		field.autoSize = TextFieldAutoSize.NONE;
		field.wordWrap = true;
		field.multiline = true;
		field.selectable = false;
		addChild(field);

		var buttonWidth:Float = Math.min(w * 0.4, unit * 12);
		var copy:Sprite = makeButton("COPY LOG", buttonWidth, buttonHeight, unit, 0x2E7D32);
		copy.x = w / 2 - buttonWidth - unit * 0.5;
		copy.y = h - buttonHeight - unit * 0.6;
		copyLabel = cast copy.getChildAt(0);
		copy.addEventListener(MouseEvent.CLICK, onCopy);
		addChild(copy);

		var close:Sprite = makeButton("CONTINUE", buttonWidth, buttonHeight, unit, 0x555555);
		close.x = w / 2 + unit * 0.5;
		close.y = copy.y;
		close.addEventListener(MouseEvent.CLICK, onClose);
		addChild(close);

		// drag the log to scroll it
		field.addEventListener(MouseEvent.MOUSE_DOWN, (e:MouseEvent) -> dragY = e.stageY);
		addEventListener(Event.ENTER_FRAME, onFrame);
		Lib.current.stage.addEventListener(MouseEvent.MOUSE_UP, onUp);
	}

	function makeText(text:String, size:Float, color:Int, bold:Bool):TextField {
		var t:TextField = new TextField();
		t.defaultTextFormat = new TextFormat("_sans", Std.int(size), color, bold);
		t.text = text;
		t.autoSize = TextFieldAutoSize.LEFT;
		t.mouseEnabled = false;
		return t;
	}

	function makeButton(text:String, w:Float, h:Float, unit:Float, color:Int):Sprite {
		var s:Sprite = new Sprite();
		var label:TextField = makeText(text, unit * 0.95, 0xFFFFFF, true);
		label.autoSize = TextFieldAutoSize.NONE;
		label.width = w;
		label.height = h;
		label.y = (h - unit * 1.3) / 2;
		var f:TextFormat = label.defaultTextFormat;
		f.align = openfl.text.TextFormatAlign.CENTER;
		label.defaultTextFormat = f;
		label.text = text;
		s.graphics.beginFill(color, 1);
		s.graphics.drawRoundRect(0, 0, w, h, unit, unit);
		s.graphics.endFill();
		s.addChild(label);
		s.buttonMode = true;
		return s;
	}

	function onFrame(_:Event):Void {
		if (dragY >= 0) {
			var y:Float = Lib.current.stage.mouseY;
			var lineHeight:Float = field.textHeight / Math.max(field.numLines, 1);
			var lines:Int = Std.int((dragY - y) / Math.max(lineHeight, 1));
			if (lines != 0) {
				field.scrollV = Std.int(Math.max(1, Math.min(field.maxScrollV, field.scrollV + lines)));
				dragY = y;
			}
		}
	}

	function onUp(_:MouseEvent):Void {
		dragY = -1;
	}

	function onCopy(_:MouseEvent):Void {
		try {
			Clipboard.text = log;
			copyLabel.text = "COPIED!";
		} catch (e:Dynamic) {
			copyLabel.text = "COULD NOT COPY";
		}
	}

	function onClose(_:MouseEvent):Void {
		removeEventListener(Event.ENTER_FRAME, onFrame);
		Lib.current.stage.removeEventListener(MouseEvent.MOUSE_UP, onUp);
		if (parent != null)
			parent.removeChild(this);
		instance = null;
	}
}
#end
