package mobile;

#if mobile
import haxe.io.Path;
import lime.system.System as LimeSystem;
import lime.utils.Assets as LimeAssets;
import sys.FileSystem;
import sys.io.File;
#if android
import lime.system.JNI;
#end

/**
 * Prepares the file system on mobile.
 *
 * Mods (and the base game "mod" that ships with the engine) are read straight from the disk by Polymod,
 * but on Android the assets are packed inside the APK where `sys.FileSystem` can't see them.
 * So on the first launch (and after every update) the bundled `mods/` folder is copied to the app's storage
 * folder, and the working directory is moved there. This also gives the user a normal folder to drop their own mods into:
 *
 * `Android/data/<package name>/files/mods/`
 */
class MobileFiles {
	/**
	 * Increase this if the bundled mods change in a way that needs to be copied again.
	 */
	static inline var SETUP_VERSION:Int = 1;

	static inline var MARKER:String = ".leather_setup";

	/**
	 * The folder the game uses as its working directory on mobile.
	 */
	public static var storageDirectory(get, null):String;

	/**
	 * Gets set to a value between `0` and `1` while `copyBundledFiles` is running.
	 */
	public static var progress(default, null):Float = 0;

	/**
	 * Name of the file currently being copied (for the loading screen).
	 */
	public static var currentFile(default, null):String = "";

	/**
	 * Error message if the setup failed.
	 */
	public static var error(default, null):Null<String> = null;

	static var _storageDirectory:String = null;

	static function get_storageDirectory():String {
		if (_storageDirectory != null)
			return _storageDirectory;

		var dir:String = null;

		#if android
		try {
			// app specific "external" storage: no permissions needed and the user can reach it with a file manager / USB
			var getContext:Dynamic = JNI.createStaticMethod("org/libsdl/app/SDLActivity", "getContext", "()Landroid/content/Context;");
			var getExternalFilesDir:Dynamic = JNI.createMemberMethod("android/content/Context", "getExternalFilesDir", "(Ljava/lang/String;)Ljava/io/File;");
			var getAbsolutePath:Dynamic = JNI.createMemberMethod("java/io/File", "getAbsolutePath", "()Ljava/lang/String;");

			var file:Dynamic = getExternalFilesDir(getContext(), "");
			if (file != null)
				dir = getAbsolutePath(file);
		} catch (e:Dynamic) {
			dir = null;
		}
		#end

		// fallback: the internal app storage
		if (dir == null || dir.length == 0)
			dir = LimeSystem.applicationStorageDirectory;

		dir = Path.removeTrailingSlashes(Path.normalize(dir));

		try {
			if (!FileSystem.exists(dir))
				FileSystem.createDirectory(dir);
		} catch (e:Dynamic) {}

		_storageDirectory = dir;
		return dir;
	}

	/**
	 * Moves the working directory to the storage folder so every relative path (`mods/...`, `crash/...`, etc.) works.
	 */
	public static function setWorkingDirectory():Void {
		try {
			Sys.setCwd(storageDirectory);
		} catch (e:Dynamic) {
			error = 'Could not open the storage directory "$storageDirectory": $e';
		}
	}

	/**
	 * Returns `true` if the bundled files still need to be copied.
	 */
	public static function needsSetup():Bool {
		#if MODDING_ALLOWED
		var marker:String = Path.join([storageDirectory, MARKER]);
		try {
			if (FileSystem.exists(marker) && File.getContent(marker).trim() == Std.string(SETUP_VERSION))
				return false;
		} catch (e:Dynamic) {}
		return true;
		#else
		return false;
		#end
	}

	/**
	 * Copies every bundled `mods/` file that doesn't exist on the disk yet (files the user changed are never overwritten).
	 *
	 * Meant to run on a background thread, `progress` and `currentFile` are updated while it runs.
	 *
	 * @return `true` if everything was copied.
	 */
	public static function copyBundledFiles():Bool {
		#if MODDING_ALLOWED
		progress = 0;
		error = null;

		try {
			var ids:Array<String> = [];
			for (id in LimeAssets.list()) {
				if (id.startsWith("mods/"))
					ids.push(id);
			}

			var done:Int = 0;
			for (id in ids) {
				currentFile = id;

				var target:String = Path.join([storageDirectory, id]);
				if (!FileSystem.exists(target)) {
					createDirectories(Path.directory(target));

					var bytes = LimeAssets.getBytes(id);
					if (bytes != null) {
						// write to a temporary file first so a killed app never leaves a half written file behind
						var temp:String = target + ".part";
						File.saveBytes(temp, bytes);
						FileSystem.rename(temp, target);
					}
				}

				done++;
				progress = done / ids.length;
			}

			File.saveContent(Path.join([storageDirectory, MARKER]), Std.string(SETUP_VERSION));
			progress = 1;
			return true;
		} catch (e:Dynamic) {
			error = Std.string(e);
			return false;
		}
		#else
		return true;
		#end
	}

	static function createDirectories(path:String):Void {
		if (path == "" || FileSystem.exists(path))
			return;

		createDirectories(Path.directory(path));
		FileSystem.createDirectory(path);
	}
}
#end
