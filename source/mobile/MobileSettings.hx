package mobile;

#if mobile
import lime.app.Application;

/**
 * Applies the settings from `Options > Mobile Options` that need to be pushed to the system.
 */
class MobileSettings {
	/**
	 * Sets the fullscreen mode (hides the system bars) from the `mobileFullscreen` option, or from `value` if it is given.
	 */
	public static function applyFullscreen(?value:Bool):Void {
		var fullscreen:Bool = value ?? (Options.getData("mobileFullscreen") != false);

		try {
			Application.current.window.fullscreen = fullscreen;
		} catch (e:Dynamic) {}
	}
}
#end
