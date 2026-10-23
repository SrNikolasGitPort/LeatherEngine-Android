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

* The touch controls live in `source/mobile/MobileInput.hx`. They press and release the same keys a keyboard would, so your key binds, the options menu and every mod keep working. Menus get a D-pad plus A / B buttons, songs get one lane per column over the whole screen and a pause button. The look can be tweaked in `assets/mobile_config.json`.
* Assets live inside the APK, but Polymod needs real files. On the first launch (and after an update) `source/mobile/MobileFiles.hx` copies the bundled `mods/` folder to the app's storage folder and uses it as the working directory.
* **Adding mods:** copy them into `Android/data/com.leather128.funkin/files/mods/` using a file manager or by connecting the phone to a computer.
* Lua scripts, video cutscenes and Discord Rich Presence are desktop only for now (HScript works).
