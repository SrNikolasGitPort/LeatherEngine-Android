package com.leather128.funkin;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Build;
import android.os.Environment;
import android.provider.Settings;
import android.graphics.Rect;
import android.view.View;
import android.view.Window;
import android.view.WindowManager;
import java.util.Collections;
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

	private static final int IMMERSIVE_FLAGS = View.SYSTEM_UI_FLAG_LAYOUT_STABLE | View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
			| View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN | View.SYSTEM_UI_FLAG_HIDE_NAVIGATION | View.SYSTEM_UI_FLAG_FULLSCREEN
			| View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY;

	private static boolean immersiveListenerSet = false;

	/**
	 * Hides the status / navigation bars for good (they stay hidden when the screen is touched near the edges), makes the game
	 * draw behind the camera cutout and stops the system back / home gestures from stealing touches on the left and right edge
	 * (that is what made the first and last lanes of the hitbox fail).
	 */
	public static void enableImmersive() {
		try {
			final Activity activity = (Activity) context();
			activity.runOnUiThread(new Runnable() {
				@Override
				public void run() {
					try {
						Window window = activity.getWindow();
						final View decor = window.getDecorView();

						if (Build.VERSION.SDK_INT >= 28) {
							WindowManager.LayoutParams params = window.getAttributes();
							params.layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES;
							window.setAttributes(params);
						}

						decor.setSystemUiVisibility(IMMERSIVE_FLAGS);

						if (!immersiveListenerSet) {
							immersiveListenerSet = true;

							// whenever the system shows the bars again (a swipe from the edge) hide them again
							decor.setOnSystemUiVisibilityChangeListener(new View.OnSystemUiVisibilityChangeListener() {
								@Override
								public void onSystemUiVisibilityChange(int visibility) {
									if ((visibility & View.SYSTEM_UI_FLAG_HIDE_NAVIGATION) == 0)
										decor.setSystemUiVisibility(IMMERSIVE_FLAGS);
								}
							});

							if (Build.VERSION.SDK_INT >= 29) {
								decor.addOnLayoutChangeListener(new View.OnLayoutChangeListener() {
									@Override
									public void onLayoutChange(View v, int l, int t, int r, int b, int ol, int ot, int or, int ob) {
										// the whole screen is excluded from the system gestures (the limit is 200dp per edge, the system trims it)
										v.setSystemGestureExclusionRects(Collections.singletonList(new Rect(0, 0, r - l, b - t)));
									}
								});
							}
						}
					} catch (Throwable e) {
					}
				}
			});
		} catch (Throwable e) {
		}
	}
}
