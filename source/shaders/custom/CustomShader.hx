package shaders.custom;

import flixel.math.FlxMath;
import states.PlayState;
import flixel.addons.display.FlxRuntimeShader;
import flixel.tweens.FlxEase;
import flixel.tweens.FlxTween;
import shaders.ShaderSanitizer;

/**
 * Basically just FlxRuntimeShader but it has tween support
 */
class CustomShader extends FlxRuntimeShader {
	override public function new(?fragmentSource:String, ?vertexSource:String) {
		#if mobile
		var defaults:Array<ShaderSanitizer.UniformDefault> = [];
		fragmentSource = ShaderSanitizer.fragment(fragmentSource, defaults);
		vertexSource = ShaderSanitizer.vertex(vertexSource);
		#end

		try {
			super(fragmentSource, vertexSource);
		} catch (e) {
			trace(e.details(), ERROR);
			trace(e, ERROR);
		}

		#if mobile
		applyDefaults(defaults);
		#end
	}

	#if mobile
	/**
	 * OpenGL ES can't give a uniform a value in the shader (`uniform float amount = 1.0;`), so the sanitizer takes it out
	 * and the value is set here.
	 */
	function applyDefaults(defaults:Array<ShaderSanitizer.UniformDefault>):Void {
		for (uniform in defaults) {
			try {
				var numbers:EReg = new EReg("-?\\d*\\.?\\d+(?:[eE][-+]?\\d+)?", "g");
				var values:Array<Float> = [];
				var text:String = uniform.value;
				while (numbers.match(text)) {
					values.push(Std.parseFloat(numbers.matched(0)));
					text = numbers.matchedRight();
				}

				switch (uniform.type) {
					case "float":
						if (values.length > 0)
							setFloat(uniform.name, values[0]);
					case "int":
						if (values.length > 0)
							setInt(uniform.name, Std.int(values[0]));
					case "bool":
						setBool(uniform.name, uniform.value == "true" || (values.length > 0 && values[0] != 0));
					case "vec2" | "vec3" | "vec4":
						var count:Int = Std.parseInt(uniform.type.substr(3));
						// vec3(1.0) fills every component
						while (values.length > 0 && values.length < count)
							values.push(values[values.length - 1]);
						if (values.length >= count)
							setFloatArray(uniform.name, values.slice(0, count));
					default:
				}
			} catch (e:Dynamic) {}
		}
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
