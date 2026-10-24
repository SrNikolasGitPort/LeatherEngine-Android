package mobile;

#if mobile
import flixel.FlxG;
import flixel.system.scaleModes.FillScaleMode;
import flixel.system.scaleModes.RatioScaleMode;
import lime.app.Application;
import openfl.Lib;
import openfl.events.Event;
#if android
import lime.system.JNI;
#end

/**
 * Applies the settings from `Options > Mobile Options` that need to be pushed to the system.
 *
 * The system bars (status / navigation bar) are always hidden. The `Fullscreen` option only decides how the game fits the screen:
 * ON stretches it over the whole screen (no black bars on the sides), OFF keeps the original proportions.
 */
class MobileSettings {
	static var started:Bool = false;

	/**
	 * Hides the system bars and keeps them hidden, also when the app comes back to the front.
	 */
	public static function initialize():Void {
		if (started)
			return;
		started = true;

		enableImmersive();
		Lib.current.stage.addEventListener(Event.ACTIVATE, (_) -> enableImmersive());
		Application.current.window.onFocusIn.add(enableImmersive);
	}

	public static function enableImmersive():Void {
		#if android
		try {
			var enable:Dynamic = JNI.createStaticMethod("com/leather128/funkin/MobileStorage", "enableImmersive", "()V");
			enable();
		} catch (e:Dynamic) {}
		#end
	}

	/**
	 * Sets the fullscreen mode from the `mobileFullscreen` option, or from `value` if it is given.
	 */
	public static function applyFullscreen(?value:Bool):Void {
		var fullscreen:Bool = value ?? (Options.getData("mobileFullscreen") != false);

		enableImmersive();

		try {
			if (fullscreen) {
				if (!(FlxG.scaleMode is FillScaleMode))
					FlxG.scaleMode = new FillScaleMode();
			} else if (!(FlxG.scaleMode is RatioScaleMode) || (FlxG.scaleMode is FillScaleMode)) {
				FlxG.scaleMode = new RatioScaleMode();
			}
		} catch (e:Dynamic) {}
	}
}
#end
