package shaders;

/**
 * A default value of a `uniform` that was declared with an initializer (`uniform float amount = 1.0;`).
 */
typedef UniformDefault = {
	var name:String;
	var type:String;
	var value:String;
}

/**
 * Makes fragment shaders written for desktop OpenGL compile on phones (OpenGL ES 1.00 / GLSL ES).
 *
 * Desktop drivers accept a lot of things that OpenGL ES refuses, so shaders that run fine on PC (or that were ported from
 * Shadertoy) show a black screen or nothing at all on Android. This fixes the most common ones, without changing what the shader does:
 *
 * - `#version` lines (OpenFL already picks the right version),
 * - `mat2x2` / `mat3x3` / `mat4x4` (written `mat2` / `mat3` / `mat4` in ES),
 * - `float a = 1;` / `vec2(1)` (ES doesn't convert int to float),
 * - `uniform float a = 1.0;` (ES can't initialize uniforms, the value is given back in `defaults` so it can be set after the shader is created),
 * - global variables initialized with something that is not a constant (`vec2 uv = openfl_TextureCoordv;`), the assignment is moved to the start of `main`,
 * - `const` variables initialized with something that is not a constant, the `const` is dropped,
 * - `for` loops with a bound that isn't a constant (`i < amount`), they get a fixed maximum and a `break`,
 * - `textureSize(bitmap, 0)`.
 *
 * Nothing in this class depends on OpenFL / Flixel, it only works on the text of the shader.
 */
class ShaderSanitizer {
	/**
	 * The most iterations a loop with a bound that isn't constant can run (ES needs a constant bound).
	 */
	public static inline var MAX_LOOP:Int = 32;

	static final TYPES:String = "float|int|bool|vec[234]|ivec[234]|bvec[234]|mat[234]";

	public static function fragment(source:Null<String>, ?defaults:Array<UniformDefault>):Null<String> {
		if (source == null)
			return null;

		source = StringTools.replace(source, "\r\n", "\n");

		// #version
		source = source.split("\n").filter(line -> !StringTools.startsWith(StringTools.ltrim(line), "#version")).join("\n");

		// square matrices written the long way
		source = new EReg("\\bmat([234])x\\1\\b", "g").replace(source, "mat$1");

		// int literals where a float is needed
		source = new EReg("(float\\s+\\w+\\s*=\\s*)(-?\\d+)(\\s*[;,])", "g").replace(source, "$1$2.0$3");
		source = new EReg("(vec[234]\\s*\\(\\s*)(-?\\d+)(\\s*\\))", "g").replace(source, "$1$2.0$3");

		// `#define MODE 0` compared with `MODE == 1.0` (int against float)
		var intDefine:EReg = new EReg("^([ \\t]*#define[ \\t]+)(\\w+)([ \\t]+)(-?\\d+)[ \\t]*$", "gm");
		var defineNames:Array<String> = [];
		var scan:String = source;
		while (intDefine.match(scan)) {
			defineNames.push(intDefine.matched(2));
			scan = intDefine.matchedRight();
		}
		for (name in defineNames) {
			var floatCompare:EReg = new EReg("\\b" + name + "\\s*(==|!=|<=|>=|<|>)\\s*-?\\d+\\.|-?\\d+\\.\\d*\\s*(==|!=|<=|>=|<|>)\\s*" + name + "\\b", "");
			if (floatCompare.match(source))
				source = new EReg("^([ \\t]*#define[ \\t]+" + name + "[ \\t]+)(-?\\d+)[ \\t]*$", "m").replace(source, "$1$2.0");
		}

		// textureSize of the main texture
		source = new EReg("\\btextureSize\\s*\\(\\s*(bitmap|iChannel0)\\s*,\\s*[^)]*\\)", "g").replace(source, "openfl_TextureSize");

		// uniforms with initializers
		var uniformInit:EReg = new EReg("^([ \\t]*uniform\\s+(?:(?:highp|mediump|lowp)\\s+)?)(" + TYPES + ")(\\s+)(\\w+)\\s*=\\s*([^;]+);", "");
		var lines:Array<String> = source.split("\n");
		for (i in 0...lines.length) {
			if (uniformInit.match(lines[i])) {
				if (defaults != null)
					defaults.push({name: uniformInit.matched(4), type: uniformInit.matched(2), value: StringTools.trim(uniformInit.matched(5))});
				lines[i] = uniformInit.matched(1) + uniformInit.matched(2) + uniformInit.matched(3) + uniformInit.matched(4) + ";" + uniformInit.matchedRight();
			}
		}
		source = lines.join("\n");

		source = fixLoops(source);
		source = fixLocalConsts(source);
		source = moveGlobalInitializers(source);
		source = addShadertoyGlobals(source);

		return source;
	}

	/**
	 * Vertex shaders only need the `#version` line out of the way.
	 */
	public static function vertex(source:Null<String>):Null<String> {
		if (source == null)
			return null;

		source = StringTools.replace(source, "\r\n", "\n");
		return source.split("\n").filter(line -> !StringTools.startsWith(StringTools.ltrim(line), "#version")).join("\n");
	}

	// ------------------------------------------------------------------ globals

	/**
	 * `const vec2 size = vec2(1.0 / openfl_TextureSize.x, ...)` inside a function: desktop drivers accept it, ES wants a constant.
	 */
	static function fixLocalConsts(source:String):String {
		var constants:Map<String, Bool> = constantNames(source);
		var declaration:EReg = new EReg("^([ \\t]*)const(\\s+(?:(?:highp|mediump|lowp)\\s+)?(?:" + TYPES + ")\\s+)(\\w+)(\\s*=\\s*)([^;]+);", "");
		var lines:Array<String> = source.split("\n");
		var depth:Int = 0;

		for (i in 0...lines.length) {
			var code:String = stripComment(lines[i]);
			if (depth > 0 && declaration.match(code)) {
				if (isConstantExpression(declaration.matched(5), constants))
					constants.set(declaration.matched(3), true);
				else {
					constants.remove(declaration.matched(3));
					lines[i] = declaration.matched(1) + StringTools.ltrim(declaration.matched(2)) + declaration.matched(3) + declaration.matched(4)
						+ declaration.matched(5) + ";" + declaration.matchedRight();
				}
			}

			for (k in 0...code.length) {
				var ch:String = code.charAt(k);
				if (ch == "{")
					depth++;
				else if (ch == "}")
					depth--;
			}
		}

		return lines.join("\n");
	}

	/**
	 * Shadertoy shaders use `fragCoord` (the pixel position) without declaring it, the shader is only given `openfl_TextureCoordv`.
	 */
	static function addShadertoyGlobals(source:String):String {
		var uses:Bool = new EReg("\\bfragCoord\\b", "").match(source);
		var declared:Bool = new EReg("\\b(vec2|in\\s+vec2|inout\\s+vec2)\\s+fragCoord\\b", "").match(source);
		var defined:Bool = new EReg("^[ \\t]*#define[ \\t]+fragCoord\\b", "m").match(source);
		if (!uses || declared || defined)
			return source;

		var pragma:Int = source.indexOf("#pragma header");
		var body:Int = findMainBody(source);
		if (pragma == -1 || body == -1)
			return source;

		var insertAt:Int = pragma + "#pragma header".length;
		var withGlobal:String = source.substr(0, insertAt) + "\nvec2 fragCoord;" + source.substr(insertAt);
		body = findMainBody(withGlobal);
		return withGlobal.substr(0, body) + "\nfragCoord = openfl_TextureCoordv * openfl_TextureSize;\n" + withGlobal.substr(body);
	}

	/**
	 * Names that are constants for the compiler: `const` variables and `#define`s.
	 */
	static function constantNames(source:String):Map<String, Bool> {
		var names:Map<String, Bool> = new Map();

		var constDecl:EReg = new EReg("\\bconst\\s+(?:(?:highp|mediump|lowp)\\s+)?(?:" + TYPES + ")\\s+(\\w+)", "g");
		var text:String = source;
		while (constDecl.match(text)) {
			names.set(constDecl.matched(1), true);
			text = constDecl.matchedRight();
		}

		var define:EReg = new EReg("^[ \\t]*#define[ \\t]+(\\w+)", "gm");
		text = source;
		while (define.match(text)) {
			names.set(define.matched(1), true);
			text = define.matchedRight();
		}

		return names;
	}

	/**
	 * `true` if the expression only uses numbers, operators, constructors / built in functions and names that are constants.
	 */
	static function isConstantExpression(expression:String, constants:Map<String, Bool>):Bool {
		var identifier:EReg = new EReg("[A-Za-z_]\\w*", "g");
		var text:String = expression;
		var builtins:Array<String> = [
			"float", "int", "bool", "vec2", "vec3", "vec4", "ivec2", "ivec3", "ivec4", "bvec2", "bvec3", "bvec4", "mat2", "mat3", "mat4", "true", "false",
			"sin", "cos", "tan", "pow", "sqrt", "abs", "min", "max", "floor", "ceil", "fract", "mod", "exp", "log", "radians", "degrees", "sign", "clamp", "mix",
			"length", "normalize", "dot", "cross", "step", "smoothstep", "atan", "asin", "acos", "exp2", "log2", "inversesqrt"
		];

		while (identifier.match(text)) {
			var name:String = identifier.matched(0);
			var before:String = identifier.matchedLeft();
			// a number like 1e5 or 0x1F is not an identifier
			var isPartOfNumber:Bool = before.length > 0 && new EReg("[0-9.]$", "").match(before);
			if (!isPartOfNumber && !constants.exists(name) && builtins.indexOf(name) == -1)
				return false;
			text = identifier.matchedRight();
		}
		return true;
	}

	/**
	 * Finds the `main` function (it can be called something else with `#define mainImage main`) and returns the index right after its `{`, or -1.
	 */
	static function findMainBody(source:String):Int {
		var entries:Array<String> = ["main"];
		var alias:EReg = new EReg("^[ \\t]*#define[ \\t]+(\\w+)[ \\t]+main\\b", "gm");
		var text:String = source;
		while (alias.match(text)) {
			entries.push(alias.matched(1));
			text = alias.matchedRight();
		}

		for (entry in entries) {
			var header:EReg = new EReg("\\bvoid\\s+" + entry + "\\s*\\(\\s*(?:void)?\\s*\\)\\s*\\{", "");
			if (header.match(source))
				return header.matchedPos().pos + header.matchedPos().len;
		}
		return -1;
	}

	static function stripComment(line:String):String {
		var index:Int = line.indexOf("//");
		return index == -1 ? line : line.substr(0, index);
	}

	/**
	 * ES only allows constants as the initial value of a global variable, so the assignment moves to the beginning of `main`.
	 */
	static function moveGlobalInitializers(source:String):String {
		var constants:Map<String, Bool> = constantNames(source);
		var declaration:EReg = new EReg("^([ \\t]*)(const\\s+)?((?:(?:highp|mediump|lowp)\\s+)?(" + TYPES + "))\\s+(\\w+)\\s*=\\s*([^;]+);[ \\t]*$", "");

		var lines:Array<String> = source.split("\n");
		var moved:Array<String> = [];
		var depth:Int = 0;
		var inBlockComment:Bool = false;

		for (i in 0...lines.length) {
			var code:String = lines[i];
			var startDepth:Int = depth;
			var startedInComment:Bool = inBlockComment;

			// keep track of the block comments and braces
			var clean:String = "";
			var c:Int = 0;
			while (c < code.length) {
				if (inBlockComment) {
					if (code.substr(c, 2) == "*/") {
						inBlockComment = false;
						c += 2;
					} else
						c++;
				} else if (code.substr(c, 2) == "/*") {
					inBlockComment = true;
					c += 2;
				} else if (code.substr(c, 2) == "//") {
					break;
				} else {
					clean += code.charAt(c);
					c++;
				}
			}
			for (k in 0...clean.length) {
				var ch:String = clean.charAt(k);
				if (ch == "{")
					depth++;
				else if (ch == "}")
					depth--;
			}

			if (startDepth != 0 || startedInComment || StringTools.startsWith(StringTools.ltrim(clean), "#"))
				continue;

			if (declaration.match(stripComment(lines[i]))) {
				var isConst:Bool = declaration.matched(2) != null;
				var name:String = declaration.matched(5);
				var value:String = StringTools.trim(declaration.matched(6));
				var constantValue:Bool = isConstantExpression(value, constants);

				if (isConst) {
					if (constantValue) {
						constants.set(name, true);
						continue;
					}
					// a const that isn't really constant: it becomes a normal variable (and gets the same treatment below)
					lines[i] = declaration.matched(1) + declaration.matched(3) + " " + name + ";";
					moved.push(name + " = " + value + ";");
				} else if (!constantValue) {
					lines[i] = declaration.matched(1) + declaration.matched(3) + " " + name + ";";
					moved.push(name + " = " + value + ";");
				}
			}
		}

		if (moved.length == 0)
			return source;

		source = lines.join("\n");
		var body:Int = findMainBody(source);
		if (body == -1)
			return source;

		return source.substr(0, body) + "\n" + moved.join("\n") + "\n" + source.substr(body);
	}

	// ------------------------------------------------------------------ loops

	static var loopCounter:Int = 0;


	/**
	 * Splits the step of a loop (`i++`, `++i`, `i += 0.5`) in the variable and the amount added. `null` if it's something else.
	 */
	static function parseStep(step:String, variable:String):Null<String> {
		step = StringTools.trim(step);
		if (new EReg("^(" + variable + "\\s*\\+\\+|\\+\\+\\s*" + variable + ")$", "").match(step))
			return "1";
		var plusEquals:EReg = new EReg("^" + variable + "\\s*\\+=\\s*(.+)$", "");
		if (plusEquals.match(step))
			return StringTools.trim(plusEquals.matched(1));
		return null;
	}

	/**
	 * ES only runs `for` loops whose bound and step are constants (`for (float i = 0.0; i < amount; i += step)` doesn't compile when `amount` or
	 * `step` come from a uniform or a variable). Those loops are rewritten to run at most `MAX_LOOP` times, with the loop variable calculated
	 * from a counter and a `break` as soon as the original condition fails.
	 */
	static function fixLoops(source:String):String {
		var constants:Map<String, Bool> = constantNames(source);
		var loop:EReg = new EReg("for\\s*\\(\\s*(int|float)\\s+(\\w+)\\s*=\\s*([^;]+);\\s*(\\2)\\s*(<=|<)\\s*([^;]+);\\s*([^;{}]*?)\\)\\s*", "");

		var result:String = "";
		var rest:String = source;

		while (loop.match(rest)) {
			var type:String = loop.matched(1);
			var variable:String = loop.matched(2);
			var start:String = StringTools.trim(loop.matched(3));
			var comparison:String = loop.matched(5);
			var bound:String = StringTools.trim(loop.matched(6));
			var stepText:String = loop.matched(7);
			var amount:Null<String> = parseStep(stepText, variable);

			var matchStart:Int = loop.matchedPos().pos;
			var matchLength:Int = loop.matchedPos().len;
			var after:String = rest.substr(matchStart + matchLength);

			result += rest.substr(0, matchStart);

			var constantLoop:Bool = isConstantExpression(bound, constants) && (amount == null || isConstantExpression(amount, constants));
			if (constantLoop || amount == null) {
				result += rest.substr(matchStart, matchLength);
				rest = after;
				continue;
			}

			var counter:String = "_loop" + (loopCounter++);
			var setup:String = type + " " + variable + " = " + start + " + " + (type == "float" ? "float(" + counter + ")" : counter) + " * (" + amount + "); "
				+ "if (!(" + variable + " " + comparison + " " + bound + ")) break;";
			var header:String = "for (int " + counter + " = 0; " + counter + " < " + MAX_LOOP + "; " + counter + "++) ";

			if (StringTools.startsWith(after, "{")) {
				result += header + "{ " + setup;
				rest = after.substr(1);
			} else {
				// a single statement as the body, it ends at the first `;` that isn't inside parentheses
				var depth:Int = 0;
				var end:Int = -1;
				for (k in 0...after.length) {
					var ch:String = after.charAt(k);
					if (ch == "(")
						depth++;
					else if (ch == ")")
						depth--;
					else if (ch == ";" && depth == 0) {
						end = k;
						break;
					}
				}

				if (end == -1) {
					result += rest.substr(matchStart, matchLength);
					rest = after;
				} else {
					result += header + "{ " + setup + " " + after.substr(0, end + 1) + " }";
					rest = after.substr(end + 1);
				}
			}
		}

		return result + rest;
	}
}
