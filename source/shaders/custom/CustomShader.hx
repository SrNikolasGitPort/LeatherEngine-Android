package shaders.custom;

import flixel.math.FlxMath;
import states.PlayState;
import flixel.addons.display.FlxRuntimeShader;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;

/**
 * Basically just FlxRuntimeShader but it has tween support
 */
class CustomShader extends FlxRuntimeShader {
	override public function new(?fragmentSource:String, ?vertexSource:String) {
		#if mobile
		fragmentSource = fixSource(fragmentSource, true);
		vertexSource = fixSource(vertexSource, false);
		#end

		try {
			super(fragmentSource, vertexSource);
		} catch (e) {
			trace(e.details(), ERROR);
			trace(e, ERROR);
		}
	}

	#if mobile
	/**
	 * Shaders made for desktop OpenGL often don't compile on phones (OpenGL ES):
	 * - a `#version 120` line (or any other) is removed, the right version is added by OpenFL,
	 * - phones default to low precision floats which breaks a lot of shaders (banding, black screens), so `highp` is asked for.
	 */
	static function fixSource(source:Null<String>, fragment:Bool):Null<String> {
		if (source == null)
			return null;

		var lines:Array<String> = source.split("\n").filter(line -> !StringTools.startsWith(StringTools.ltrim(line), "#version"));
		source = lines.join("\n");

		if (fragment && source.indexOf("#pragma header") != -1) {
			source = StringTools.replace(source, "#pragma header", "#pragma header\n#ifdef GL_ES\n#ifdef GL_FRAGMENT_PRECISION_HIGH\nprecision highp float;\n#endif\n#endif");
		}

		return source;
	}
	#end

	/**
	 * Tweens a shader to a value
	 * @param property The property to tween
	 * @param to The value of the property to end up at
	 * @param duration How long it will take
	 * @param ease What ease should be used
	 * @param startDelay The delay to start
	 * @param onComplete When to do when the tween is done
	 */
	public function tween(property:String, to:Float, duration:Float = 1, ease:EaseFunction, ?startDelay:Float = 0.0, ?onComplete:Dynamic) {
		PlayState.instance.tweenManager.num(getFloat(property), to, duration, {
			ease: ease,
			onComplete: (_) -> {
				setFloat(property, to); // make sure
				if (onComplete != null)
					onComplete();
			},
			startDelay: startDelay,
		}, value -> {
			setFloat(property, value);
		});
	}
}
