package mobile;

#if mobile
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import sys.thread.Thread;

/**
 * Plain OpenFL loading screen (no Flixel yet) shown while the bundled game files are copied to the storage folder.
 * This only happens on the first launch and after the app gets updated.
 */
class MobileSetupScreen extends Sprite {
	var onFinish:Void->Void;

	var title:TextField;
	var status:TextField;
	var file:TextField;
	var bar:Sprite;

	var finished:Bool = false;
	var success:Bool = false;

	public function new(onFinish:Void->Void) {
		super();
		this.onFinish = onFinish;

		title = makeText(34, true);
		title.text = "Leather Engine";
		status = makeText(20, false);
		status.text = "Preparing the game files...\nThis only happens on the first launch.";
		file = makeText(13, false);
		file.alpha = 0.6;
		bar = new Sprite();

		addChild(title);
		addChild(status);
		addChild(file);
		addChild(bar);
	}

	function makeText(size:Int, bold:Bool):TextField {
		var text:TextField = new TextField();
		text.selectable = false;
		text.mouseEnabled = false;
		text.multiline = true;
		text.wordWrap = true;
		text.defaultTextFormat = new TextFormat("_sans", size, 0xFFFFFF, bold, null, null, null, null, TextFormatAlign.CENTER);
		return text;
	}

	public function start():Void {
		addEventListener(Event.ENTER_FRAME, update);

		Thread.create(() -> {
			success = MobileFiles.copyBundledFiles();
			finished = true;
		});
	}

	function update(_:Event):Void {
		var stageWidth:Float = Lib.current.stage.stageWidth;
		var stageHeight:Float = Lib.current.stage.stageHeight;

		graphics.clear();
		graphics.beginFill(0x000000);
		graphics.drawRect(0, 0, stageWidth, stageHeight);
		graphics.endFill();

		title.width = status.width = file.width = stageWidth * 0.8;
		title.x = status.x = file.x = stageWidth * 0.1;
		title.y = stageHeight * 0.2;
		status.y = title.y + 70;
		file.y = stageHeight * 0.72;
		file.text = MobileFiles.currentFile;

		var barWidth:Float = stageWidth * 0.6;
		var barHeight:Float = 14;
		var barX:Float = (stageWidth - barWidth) / 2;
		var barY:Float = stageHeight * 0.62;

		bar.graphics.clear();
		bar.graphics.beginFill(0xFFFFFF, 0.2);
		bar.graphics.drawRoundRect(barX, barY, barWidth, barHeight, barHeight, barHeight);
		bar.graphics.beginFill(0x5FCBFF);
		bar.graphics.drawRoundRect(barX, barY, Math.max(barHeight, barWidth * MobileFiles.progress), barHeight, barHeight, barHeight);
		bar.graphics.endFill();

		if (!finished)
			return;

		if (success) {
			removeEventListener(Event.ENTER_FRAME, update);
			onFinish();
		} else {
			status.text = "Could not prepare the game files:\n" + MobileFiles.error;
			file.text = "Make sure there is enough free storage space and restart the game.";
			removeEventListener(Event.ENTER_FRAME, update);
		}
	}
}
#end
