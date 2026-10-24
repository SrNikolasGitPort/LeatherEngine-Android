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
 * So every time the game opens it makes sure the needed files were copied from the APK to the engine folder
 * (only the first launch and after an update actually copy something), and moves the working directory there.
 * That folder is also where the user drops their own mods (`<engine folder>/mods/`).
 *
 * Where the engine folder is can be changed in `Options > Mobile Options > Storage`:
 *
 * | Mode       | Folder                                           |
 * |------------|--------------------------------------------------|
 * | `EXTERNAL` | `/storage/emulated/0/.Leather1.1.9` (default)    |
 * | `DATA`     | `Android/data/<package name>/files`              |
 * | `MEDIA`    | `Android/media/<package name>`                   |
 * | `OBB`      | `Android/obb/<package name>`                     |
 *
 * `EXTERNAL` needs the "all files access" permission, the others don't need any permission.
 */
class MobileFiles {
	/**
	 * Every place the engine folder can be.
	 */
	public static final STORAGE_MODES:Array<String> = ["EXTERNAL", "DATA", "MEDIA", "OBB"];

	public static inline var DEFAULT_MODE:String = "EXTERNAL";

	/**
	 * Name of the engine folder inside of the `EXTERNAL` storage.
	 */
	public static inline var EXTERNAL_FOLDER_NAME:String = ".Leather1.1.9";

	/**
	 * Increase this if the bundled mods change in a way that needs to be copied again.
	 */
	static inline var SETUP_VERSION:Int = 2;

	static inline var MARKER:String = ".leather_setup";
	static inline var MODE_FILE:String = "storage_mode.txt";

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

	/**
	 * The folder the game uses as its working directory on mobile.
	 */
	public static var storageDirectory(get, never):String;

	static var _storageDirectory:String = null;

	// ------------------------------------------------------------------ storage mode

	/**
	 * The private app folder. It always exists and doesn't need any permission, this is where the chosen mode is remembered
	 * (the options can't be used for that because they're loaded after the engine folder is known).
	 */
	static function getInternalDirectory():String {
		var dir:String = getNativeDirectory("INTERNAL");
		if (dir == "")
			dir = LimeSystem.applicationStorageDirectory;
		return dir;
	}

	/**
	 * @return the storage mode picked in the options.
	 */
	public static function getStorageMode():String {
		try {
			var file:String = Path.join([getInternalDirectory(), MODE_FILE]);
			if (FileSystem.exists(file)) {
				var mode:String = File.getContent(file).trim().toUpperCase();
				if (STORAGE_MODES.contains(mode))
					return mode;
			}
		} catch (e:Dynamic) {}
		return DEFAULT_MODE;
	}

	/**
	 * Remembers the storage mode, it is used the next time the game opens.
	 */
	public static function setStorageMode(mode:String):Void {
		try {
			File.saveContent(Path.join([getInternalDirectory(), MODE_FILE]), mode);
		} catch (e:Dynamic) {}
	}

	/**
	 * Gets the folder a certain mode uses, `null` if the device doesn't have it.
	 */
	public static function getDirectoryForMode(mode:String):Null<String> {
		var base:String = getNativeDirectory(mode);

		if (base == "") {
			// no JNI (or the folder doesn't exist on this device)
			if (mode == "DATA" || mode == "INTERNAL")
				base = LimeSystem.applicationStorageDirectory;
			else
				return null;
		}

		if (mode == "EXTERNAL")
			base = Path.join([base, EXTERNAL_FOLDER_NAME]);

		return Path.removeTrailingSlashes(Path.normalize(base));
	}

	/**
	 * Returns `true` if the game can use the folder of the chosen storage mode right now.
	 */
	public static function hasStorageAccess():Bool {
		if (getStorageMode() != "EXTERNAL")
			return true;

		#if android
		try {
			var hasAccess:Dynamic = JNI.createStaticMethod("com/leather128/funkin/MobileStorage", "hasStorageAccess", "()Z");
			return hasAccess() == true;
		} catch (e:Dynamic) {
			return false;
		}
		#else
		return true;
		#end
	}

	/**
	 * Opens the system screen where the player can allow the game to use the `EXTERNAL` storage.
	 */
	public static function requestStorageAccess():Void {
		#if android
		try {
			var request:Dynamic = JNI.createStaticMethod("com/leather128/funkin/MobileStorage", "requestStorageAccess", "()V");
			request();
		} catch (e:Dynamic) {}
		#end
	}

	static function getNativeDirectory(mode:String):String {
		#if android
		try {
			var getDir:Dynamic = JNI.createStaticMethod("com/leather128/funkin/MobileStorage", "getDir", "(Ljava/lang/String;)Ljava/lang/String;");
			var dir:String = getDir(mode);
			return dir == null ? "" : dir;
		} catch (e:Dynamic) {}
		#end
		return "";
	}

	static function get_storageDirectory():String {
		if (_storageDirectory != null)
			return _storageDirectory;

		var mode:String = getStorageMode();
		var dir:Null<String> = getDirectoryForMode(mode);

		// can't use the chosen folder (no permission or the device doesn't have it), fall back to the app folder
		if (dir == null || !canWriteTo(dir))
			dir = getDirectoryForMode("DATA");

		_storageDirectory = dir;
		return dir;
	}

	static function canWriteTo(dir:String):Bool {
		try {
			createDirectories(dir);
			var test:String = Path.join([dir, ".write_test"]);
			File.saveContent(test, "ok");
			FileSystem.deleteFile(test);
			return true;
		} catch (e:Dynamic) {
			return false;
		}
	}

	/**
	 * Forgets the folder that was found so it's looked up again (used after the player allowed or changed something).
	 */
	public static function refreshStorageDirectory():Void {
		_storageDirectory = null;
	}

	// ------------------------------------------------------------------ setup

	/**
	 * Moves the working directory to the engine folder so every relative path (`mods/...`, `crash/...`, etc.) works.
	 */
	public static function setWorkingDirectory():Void {
		try {
			Sys.setCwd(storageDirectory);
		} catch (e:Dynamic) {
			error = 'Could not open the engine folder "$storageDirectory": $e';
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
