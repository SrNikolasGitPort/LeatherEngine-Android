# Building the game

Step 1. [Install git-scm](https://git-scm.com/downloads) if you don't have it already.

Step 2. [Install Haxe](https://haxe.org/download/)

Step 3. [Install HaxeFlixel](https://haxeflixel.com/documentation/install-haxeflixel/)

Step 4. Run the .bat/.sh file to install the required libraries.

# NOTE:
If a library asks if you would like to switch to a specific version, just say no

Dependencies for compiling:

## Windows Only

Install [Visual Studio](https://visualstudio.microsoft.com/), and while installing instead of selecting the normal options, only select these components in the 'individual components' instead (or the closest equivalents).

```
* MSVC v142 - VS 2019 C++ x64/x86 build tools
* Windows 10 / 11 SDK (Latest)
```

## Linux Only

In your package manager, install the following packages:

```sh
sudo apt-get install libvlc-dev
sudo apt-get install libvlccore-dev
sudo apt-get install vlc-bin
sudo apt-get install luajit
```

```sh
sudo pacman -S vlc
sudo pacman -S luajit
```

Step 5. Run `lime test [platform]` in the project directory while replacing '[platform]' with your build target (usually `html5`, `windows`, `linux`, `mac`, or whatever platform you are building for).

# NOTE:
If you are having issues when compiling due to a library giving you an error, try removing the library with
```
haxelib remove library
```
replacing library with the name of the library you would like to remove
and then re install it with the commands in step 4



# Android

The easiest way is the **Build Android** GitHub Action (`.github/workflows/Android.yml`): run it from the Actions tab and download the `LeatherEngine-Android` artifact (an APK for 64 bit ARM devices, Android 9+).

To build it yourself you need, on top of the steps above:

* Java 17
* Android SDK platform 35, build-tools 35.0.0 and NDK r27c (`27.2.12479018`)

```sh
haxelib run lime config ANDROID_SDK /path/to/android-sdk
haxelib run lime config ANDROID_NDK_ROOT /path/to/android-sdk/ndk/27.2.12479018
haxelib run lime config JAVA_HOME /path/to/jdk-17
haxelib run lime config ANDROID_SETUP true
haxelib run lime build android -release -arm64
```

## How it works on Android

* **Touch controls** (`source/mobile/MobileInput.hx`). They press and release the same keys a keyboard would, so your key binds, the options menu and every mod keep working.
  * In menus there is a D-pad plus A / B buttons.
  * In songs the whole screen is the **hitbox**: one transparent column per lane, in the color of that lane's arrow. It adapts to the screen size and to the key count (every extra key adds one lane) and lights up while you touch it. There is also a small pause button in the top right corner.
* **Options > Mobile Options**
  * *Hitbox Visible*: hide the colored lanes (they still work).
  * *Hitbox Opacity*: how visible the lanes are.
  * *Fullscreen*: hides the system bars.
  * *Storage*: where the engine folder is (see below), applied the next time the game opens.
* **Engine folder and mods.** Assets live inside the APK, but Polymod needs real files. Every time the game opens `source/mobile/MobileFiles.hx` makes sure the needed files were copied to the engine folder (the first launch and updates are the only times something is actually copied) and uses it as the working directory. Put your mods in its `mods/` folder.

  | Storage mode         | Engine folder                                         |
  |----------------------|-------------------------------------------------------|
  | `EXTERNAL` (default) | `/storage/emulated/0/.Leather1.1.9`                   |
  | `DATA`               | `Android/data/com.leather128.funkin/files`            |
  | `MEDIA`              | `Android/media/com.leather128.funkin`                 |
  | `OBB`                | `Android/obb/com.leather128.funkin`                   |

  `EXTERNAL` needs the "all files access" permission, the game asks for it on the first launch (or you can use the app folder instead). Changing the storage mode doesn't move the files, the new folder is filled with the bundled files the next time the game opens, copy your mods over if you want to keep them.
* Lua scripts, video cutscenes and Discord Rich Presence are desktop only for now (HScript works).
