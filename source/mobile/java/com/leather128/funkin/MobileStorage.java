package com.leather128.funkin;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.Settings;
import java.io.File;
import org.libsdl.app.SDLActivity;

/**
 * Small helper used by the game (through lime's JNI) to find the storage folders and ask for storage access.
 */
public class MobileStorage {
	private static Context context() {
		return SDLActivity.getContext();
	}

	/**
	 * @param mode one of INTERNAL, EXTERNAL, DATA, MEDIA or OBB
	 * @return the absolute path of that folder or an empty string if it isn't available
	 */
	public static String getDir(String mode) {
		try {
			Context context = context();
			File dir = null;

			if (mode.equals("EXTERNAL")) {
				// the root of the internal storage ("/storage/emulated/0")
				dir = Environment.getExternalStorageDirectory();
			} else if (mode.equals("DATA")) {
				// Android/data/<package>/files
				dir = context.getExternalFilesDir(null);
			} else if (mode.equals("MEDIA")) {
				// Android/media/<package>
				File[] dirs = context.getExternalMediaDirs();
				if (dirs != null && dirs.length > 0)
					dir = dirs[0];
			} else if (mode.equals("OBB")) {
				// Android/obb/<package>
				dir = context.getObbDir();
			} else {
				// private app folder, always available
				dir = context.getFilesDir();
			}

			if (dir == null)
				return "";

			if (!dir.exists())
				dir.mkdirs();

			return dir.getAbsolutePath();
		} catch (Exception e) {
			return "";
		}
	}

	/**
	 * @return true if the game is allowed to use the "EXTERNAL" folder
	 */
	public static boolean hasStorageAccess() {
		try {
			if (Build.VERSION.SDK_INT >= 30)
				return Environment.isExternalStorageManager();

			return context().checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED;
		} catch (Exception e) {
			return false;
		}
	}

	/**
	 * Opens the system screen (Android 11+) or shows the permission dialog (older versions) to grant storage access.
	 */
	public static void requestStorageAccess() {
		final Activity activity = (Activity) context();

		activity.runOnUiThread(new Runnable() {
			@Override
			public void run() {
				try {
					if (Build.VERSION.SDK_INT >= 30) {
						try {
							Intent intent = new Intent(Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION);
							intent.setData(Uri.parse("package:" + activity.getPackageName()));
							activity.startActivity(intent);
						} catch (Exception e) {
							activity.startActivity(new Intent(Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION));
						}
					} else {
						activity.requestPermissions(new String[] {
							android.Manifest.permission.READ_EXTERNAL_STORAGE,
							android.Manifest.permission.WRITE_EXTERNAL_STORAGE
						}, 1);
					}
				} catch (Exception e) {
					// nothing else we can do, the game falls back to the app folder
				}
			}
		});
	}
}
