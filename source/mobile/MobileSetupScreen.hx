package mobile;

#if mobile
import openfl.Lib;
import openfl.display.Sprite;
import openfl.events.Event;
import openfl.events.MouseEvent;
import openfl.text.TextField;
import openfl.text.TextFormat;
import openfl.text.TextFormatAlign;
import sys.thread.Thread;

private enum Step {
	/**
	 * Waiting for the player to allow the game to use the storage.
	 */
	PERMISSION;

	/**
	 * Copying the bundled game files to the engine folder.
	 */
	COPYING;

	/**
	 * Something went wrong.
	 */
	FAILED;
}

/**
 * Plain OpenFL screen (no Flixel yet) that runs before the game starts and makes sure the engine folder is ready:
 *
 * 1. asks for storage access if the engine folder is in the `EXTERNAL` storage,
 * 2. copies the bundled game files to the engine folder (first launch and after updates only).
 *
 * If there is nothing to do the game starts right away without showing anything.
 */
class MobileSetupScreen extends Sprite {
	var onFinish:Void->Void;
	var step:Step = COPYING;

	var title:TextField;
	var status:TextField;
	var file:TextField;
	var bar:Sprite;
	var allowButton:Sprite;

	var copyFinished:Bool = false;
	var copySuccess:Bool = false;
	var done:Bool = false;

	public function new(onFinish:Void->Void) {
		super();
		this.onFinish = onFinish;

		title = makeText(34, true);
		title.text = "Leather Engine";
		status = makeText(20, false);
		file = makeText(13, false);
		file.alpha = 0.6;
		bar = new Sprite();
		allowButton = makeButton("Allow access");

		allowButton.addEventListener(MouseEvent.CLICK, (_) -> MobileFiles.requestStorageAccess());

		addChild(title);
		addChild(status);
		addChild(file);
		addChild(bar);
		addChild(allowButton);
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

	function makeButton(label:String):Sprite {
		var button:Sprite = new Sprite();
		button.mouseChildren = false;
		button.buttonMode = true;

		var text:TextField = makeText(20, true);
		text.text = label;
		text.name = "label";
		button.addChild(text);
		return button;
	}

	/**
	 * Called once the screen is on the stage.
	 */
	public function start():Void {
		addEventListener(Event.ENTER_FRAME, update);
		begin();
	}

	/**
	 * Checks what is left to do, can be called again after the player changed something.
	 */
	function begin():Void {
		MobileFiles.refreshStorageDirectory();

		if (!MobileFiles.hasStorageAccess()) {
			step = PERMISSION;
			return;
		}

		MobileFiles.setWorkingDirectory();

		if (!MobileFiles.needsSetup()) {
			finish();
			return;
		}

		step = COPYING;
		copyFinished = false;

		Thread.create(() -> {
			copySuccess = MobileFiles.copyBundledFiles();
			copyFinished = true;
		});
	}

	function finish():Void {
		if (done)
			return;

		done = true;
		removeEventListener(Event.ENTER_FRAME, update);
		onFinish();
	}

	function update(_:Event):Void {
		if (done)
			return;

		// the player came back from the settings screen with the access granted
		if (step == PERMISSION && MobileFiles.hasStorageAccess()) {
			begin();
			if (done)
				return;
		}

		if (step == COPYING && copyFinished) {
			if (copySuccess) {
				finish();
				return;
			}
			step = FAILED;
		}

		draw();
	}

	function draw():Void {
		var stageWidth:Float = Lib.current.stage.stageWidth;
		var stageHeight:Float = Lib.current.stage.stageHeight;

		graphics.clear();
		graphics.beginFill(0x000000);
		graphics.drawRect(0, 0, stageWidth, stageHeight);
		graphics.endFill();

		title.width = status.width = file.width = stageWidth * 0.8;
		title.x = status.x = file.x = stageWidth * 0.1;
		title.y = stageHeight * 0.12;
		status.y = title.y + 70;

		bar.graphics.clear();
		bar.visible = step == COPYING;
		allowButton.visible = step == PERMISSION;

		switch (step) {
			case PERMISSION:
				status.text = "Leather Engine keeps its mods in the folder\n\".Leather1.1.9\" in your storage.\nAllow it to access your files to continue.";
				file.text = "You can change this later in Options > Mobile Options > Storage.";
				file.y = stageHeight * 0.86;

				layoutButton(allowButton, stageWidth, stageHeight * 0.52);
			case COPYING:
				status.text = "Preparing the game files...\nThis only happens on the first launch.";
				file.text = MobileFiles.currentFile;
				file.y = stageHeight * 0.72;

				var barWidth:Float = stageWidth * 0.6;
				var barHeight:Float = 14;
				var barX:Float = (stageWidth - barWidth) / 2;
				var barY:Float = stageHeight * 0.62;

				bar.graphics.beginFill(0xFFFFFF, 0.2);
				bar.graphics.drawRoundRect(barX, barY, barWidth, barHeight, barHeight, barHeight);
				bar.graphics.beginFill(0x5FCBFF);
				bar.graphics.drawRoundRect(barX, barY, Math.max(barHeight, barWidth * MobileFiles.progress), barHeight, barHeight, barHeight);
				bar.graphics.endFill();
			case FAILED:
				status.text = "Could not prepare the game files:\n" + MobileFiles.error;
				file.text = "Make sure there is enough free storage space and restart the game.";
				file.y = stageHeight * 0.72;
		}
	}

	function layoutButton(button:Sprite, stageWidth:Float, y:Float):Void {
		var width:Float = stageWidth * 0.6;
		var height:Float = 60;

		var label:TextField = cast button.getChildByName("label");
		label.width = width;
		label.y = (height - label.textHeight) / 2 - 3;

		button.graphics.clear();
		button.graphics.lineStyle(3, 0xFFFFFF, 0.8);
		button.graphics.beginFill(0x5FCBFF, 0.25);
		button.graphics.drawRoundRect(0, 0, width, height, 24, 24);
		button.graphics.endFill();

		button.x = (stageWidth - width) / 2;
		button.y = y;
	}
}
#end
