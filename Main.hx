/*
 * doxygen2hxcpp - Extern generator for hxcpp using doxygen xml output
 * Copyright 2015 Valentin Lemière, Guillaume Desquesnes
 *
 * This file is part of doxygen2hxcpp.
 *
 * doxygen2hxcpp is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * doxygen2hxcpp is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with doxygen2hxcpp. If not, see <http://www.gnu.org/licenses/>.
 */

import haxe.io.Path;
import sys.io.File;
import sys.io.FileOutput;
import sys.FileSystem;

#if cpp
import cpp.Lib;
#else
import neko.Lib;
#end

import data.*;

using StringTools;

class Main
{
	private static inline var PROG_NAME = "doxygen2hxcpp";
	private static inline var PROG_VERSION = "0.0.1";
	private static inline var PROG_README = "https://github.com/lemdes/doxygen2hxcpp/blob/master/README.md";

	public static function main ()
	{
		new Main();
	}

	private var typedefs_list = new Map<String, String>();
	private var global : FileData;
	private var files : Map<String, FileData>;
	private var patches : PatchFile;
	private var used = new Map<String, Bool>();
	private var nb = 0;
	private var counter = { classes: 0, typedefs: 0, unions: 0, enums: 0 };
	private var isCurrentlySkipping : Bool = null;
	private var inputPath : String;
	private var outputPath : String;
	private var basePack : String;
	private var indentLevel (default, set) : Int = 0;
	private var _indent : String = "";
	private function set_indentLevel (value:Int) : Int
	{
		var a = [];

		for (i in 0...value)
		{
			a.push("\t");
		}

		_indent = a.join("");

		return indentLevel = value;
	}

	public function new ()
	{
		var args = Sys.args();

		if (args.length != 3 && args.length != 4)
		{
			Lib.println("neko gen.n inputPath outputPath basePackage [patchFile]");
			return;
		}

		inputPath = args[0];
		outputPath = args[1];
		basePack = args[2];

		if (args.length == 4)
		{
			// load patches
			//TODO: actually use them
			patches = new PatchFile(Xml.parse(File.getContent(args[3])));
		}
		else
		{
			patches = new PatchFile(null);
		}

		if (!FileSystem.exists(outputPath))
		{
			FileSystem.createDirectory(outputPath);
		}

		files = new Map<String, FileData>();
		global = getFile("Global");
		var c : ClassData = { name: "Global", typedefs: [], doc: null, variables: [], functions: [], variables_stat: [], functions_stat: [], include: "", native: "", sup: "" };
		global.classes.push(c);

		for (td in patches.typedefs)
		{
			getFile(td.name).typedefs.push({ name: td.name, value: td.value, doc: null });
		}

		var index = Xml.parse(File.getContent(Path.join([ inputPath, "index.xml" ]))).firstElement();

		if (!index.get("version").startsWith("1.8."))
		{
			Lib.println("The xml isn't version 1.8.*, may not work");
		}

		Sys.print(".");

		var file;
		for (compound in index.elements())
		{
			var compoundName = compound.firstChild().firstChild().nodeValue;
			if (patches.ignores(compoundName))
			{
				Lib.println("\nIgnoring "+compoundName + " as specified by the patch file");
				continue;
			}

			Sys.print(".");

			file = Path.join([ inputPath, compound.get("refid") + ".xml" ]);

			switch (compound.get("kind"))
			{
				case "class", "struct":
					var data = Xml.parse(File.getContent(file)).firstElement();
					for (compounddef in data.elements())
					{
						buildClass(compounddef);
					}

				case "union":
					var data = Xml.parse(File.getContent(file)).firstElement();
					for (compounddef in data.elements())
					{
						buildUnion(compounddef);
					}

				case "file":
					var data = Xml.parse(File.getContent(file)).firstElement();
					for (compounddef in data.elements())
					{
						buildFile(compounddef, true);
					}

				case "group":
					var data = Xml.parse(File.getContent(file)).firstElement();
					for (compounddef in data.elements())
					{
						buildFile(compounddef, false);
					}

				case "dir", "page":
					// ignore
					//TODO: check the xmls to be sure
					continue;

				default:
					// no "interface" wxWidgets, ignore for now
					trace("ignored (for now) compound type: " + compound.get("kind"));
					continue;
			}
		}

		Lib.println("\n");
		var i = 0;
		for (f in files)
		{
			i++;
			Lib.print('\r$i              ');
			genFile(f);
		}

		Lib.println('\rDone! $nb files generated from ${counter.classes} class(es), ${counter.typedefs} typedef(s), ${counter.enums} enum(s) and ${counter.unions} union(s).');
	}

	private function getValue (v:TypeValue) : String
	{
		return switch (v)
		{
			case Haxe(s):
				s;

			case Cpp(s):
				getValue(toHaxeType(s));

			case Unresolved(s):
				//TODO: resolve it
				"";
		}
	}

	private function getFile (name:String) : FileData
	{
		if (files.exists(name))
		{
			return files.get(name);
		}
		else
		{
			var f:FileData = { unions:[], typedefs: [], pack: [], name: name, enums: [], classes: [] };
			files.set(name, f);
			return f;
		}
	}

	private function getOutputFileStream (pack:Array<String>, classname:String) : FileOutput
	{
		var pack = pack.copy();
		pack.unshift(outputPath);
		var path = Path.join(pack);

		if (!FileSystem.exists(path))
		{
			FileSystem.createDirectory(path);
		}

		var i = classname.indexOf("<");
		if (i > -1)
		{
			classname = classname.substr(0, i) + classname.substr(classname.indexOf(">")+1);
		}

		pack.push(classname + ".hx");
		path = Path.join(pack);

		nb++;

		if (used.exists(path))
		{
			// we have a problem
			//TODO: throw
			Lib.println('$path was already asked');
		}
		else
		{
			used.set(path, true);
		}

		return File.write(path, false);
	}

	private function genPackage (pack:Array<String>) : String
	{
		return " " + pack.join(".");
	}

	private function toHaxeName (name:String, lower:Bool=false) : String
	{
		//TODO: if ALL_CAP name ignore lower flag

		if (name == "")
		{
			return "";
		}
		
		if (name.startsWith(basePack))
		{
			name = name.substr(basePack.length);
		}

		return (lower ? name.substr(0,1).toLowerCase() : name.substr(0,1).toUpperCase()) + name.substr(1);
	}

	private function docRemoveTag (doc:String, tag:String, encase:String, ?replace:String->String) : String
	{
		var pos:Int;
		var pos2:Int;
		var pos3:Int;

		var tagStart = '<$tag';
		var tagEnd = '</$tag>';
		var l = tagEnd.length;

		if (replace == null)
		{
			replace = function (s:String) : String { return s; };
		}

		while ((pos = doc.indexOf(tagStart)) > -1)
		{
			pos2 = doc.indexOf(">", pos);
			pos3 = doc.indexOf(tagEnd, pos);

			doc = doc.substr(0, pos) + encase + replace(doc.substr(pos2+1, pos3-pos2-1)) + encase + doc.substr(pos3+l);
		}

		return doc;
	}

	private function genDoc (xml:Xml, file:FileOutput) : Void
	{
		if (xml == null)
		{
			return;
		}

		var briefDoc = xml.elementsNamed("briefdescription").next();
		var longDoc = xml.elementsNamed("detaileddescription").next();

		writeLine(file, "/**");

		for (element in briefDoc.elements())
		{
			var para = element.toString();
			para = para.substr(para.indexOf(">") + 1);
			para = para.substr(0, para.lastIndexOf("<"));

			para = docRemoveTag(para, "ref", "`", function (s) return toHaxeName(s));
			para = docRemoveTag(para, "computeroutput", "```");
			para = docRemoveTag(para, "emphasis", "*");

			writeLine(file, ' * ${para.trim()}');
		}
		//TODO: hidden for now to ease check of generated files
		//TODO: need to clean the <parameterlist>  and <itemizedlist>
		/*
		for (element in longDoc.elements())
		{
			writeLine(file, " * ");

			var para = element.toString();
			para = para.substr(para.indexOf(">") + 1);
			para = para.substr(0, para.lastIndexOf("<"));

			para = docRemoveTag(para, "ref", "`");
			para = docRemoveTag(para, "computeroutput", "```");
			para = docRemoveTag(para, "emphasis", "*");

			writeLine(file, ' * ${para.trim()}');
		}
		*/
		writeLine(file, " */");
	}

	private function getXmlContent (xml:Xml, nodename:String) : String
	{
		var element = xml.elementsNamed(nodename).next();

		if (element == null)
		{
			return "";
		}
		else
		{
			return element.firstChild().nodeValue;
		}
	}

	private function getType(memberDef:Xml) : String
	{
		var type = "";
		var e = memberDef.elementsNamed("type").next();

		if (e != null)
		{
			var it = e.iterator();
			var n;
			while (it.hasNext())
			{
				n = it.next();

				if (n.nodeType == Xml.PCData)
				{
					type += n.nodeValue;
				}
				else
				{
					type += n.firstChild().nodeValue;
				}

			}
		}

		if (type.startsWith("const "))
		{
			return type.substr(6);
		}
		else
		{
			return type;
		}
	}

	private function fuseType (a:TypeValue, b:TypeValue) : TypeValue
	{
		return switch ([a, b]) {
			case [Haxe(s1), Haxe(s2)]:
				Haxe(s1 + s2);

			case [Cpp(s1), Cpp(s2)]:
				Cpp(s1 + s2);

			case [Unresolved(s1), Unresolved(s2)]:
				Unresolved(s1 + s2);

			default:
				throw "Cannot fuse two different type of TypeValue";
		}
	}

	private function toHaxeType (cppType:String) : TypeValue
	{
		if (cppType == "void *")
		{
			// any pointer
			return Haxe("Dynamic");
		}

		if (cppType.startsWith("struct "))
		{
			//TODO: what to do with that?
			cppType = cppType.substr(7);
		}

		if (cppType.indexOf("(") > -1)
		{

			// returnType(*|T::*)(Type a, Type b)
			var tmp = cppType.split("(");
			var returnType = toHaxeType(tmp[0]);

			var paramString = tmp[tmp.length-1];
			var parameters = paramString.substr(0,paramString.length-1).split(",");

			var type = Haxe("");
			for (param in parameters)
			{
				type = Haxe(getValue(type) + getValue(toHaxeType(param.ltrim().split(" ")[0])) + " -> ");
			}

			type = fuseType(type, returnType);

			return type;
		}

		if (cppType.indexOf("::") > -1 && !cppType.startsWith("std::"))
		{
			var tmp = cppType.split("::");

			if (tmp[1].startsWith("const_iterator"))
			{
				return Haxe("Dynamic");
			}
			else
			{
				return Haxe('${getValue(toHaxeType(tmp[0]))}.${getValue(toHaxeType(tmp[1]))}');
			}
		}

		var pointer = cppType.endsWith(" *");
		var arrayarray = cppType.endsWith(" **");

		if (pointer)
		{
			cppType = cppType.substr(0, cppType.length-2);
		}

		if (arrayarray)
		{
			cppType = cppType.substr(0, cppType.length-3);
		}


		if (cppType.endsWith(" &"))
		{
			//TODO: do something? but they already are cpp.Ref so maybe not
			cppType = cppType.substr(0, cppType.length-2);
		}

		var firstIndex = cppType.indexOf("<");
		var lastIndex = cppType.indexOf(">");
		if (firstIndex != -1 && lastIndex != -1) 
		{
			var mainType =  toHaxeType(cppType.substring(0, firstIndex));
			var subTypes = cppType.substring(firstIndex+1,lastIndex).split(",").map(StringTools.trim).map(toHaxeType); 

			var t = subTypes[0];
			for (i in 1...subTypes.length)
			{
				t = fuseType(fuseType(t, Haxe(", ")), subTypes[i]);
			}

			return Haxe(getValue(mainType) + "<" + getValue(t) + ">");
		}

		var type = switch (cppType)
		{
			case "...":
				"haxe.extern.Rest<Dynamic>"; //TODO: better than dynamic?

			case "bool":
				"Bool";

			case "char", "signed char":
				"cpp.Char";

			case "int", "long int", "long":
				"Int";

			case "", "void":
				"Void";

			case "Uint8", "unsigned char":
				"cpp.UInt8";

			case "Uint16", "unsigned short int", "unsigned short":
				"cpp.UInt16";

			case "Uint32", "unsigned int":
				"cpp.UInt32";

			case "short int", "signed short":
				"cpp.Int16";

			case "unsigned", "unsigned long int", "size_t", "UInt", "unsigned long", "ssize_t":
				"UInt";

			case "float":
				"cpp.Float32";

			case "double":
				"cpp.Float64";

			case "std::string", "std::wstring":
				"String";

			default:
				toHaxeName(cppType);
		};

		if (pointer)
		{
			return Haxe('cpp.Pointer<$type>');
		}
		else if (arrayarray)
		{
			return Haxe('Array<cpp.Pointer<$type>>');
		}
		else
		{
			return Haxe(type);
		}
	}

	private function writeLine (file:FileOutput, line:String, lineEnd=true) : Void
	{
		if (line == "")
		{
			if (lineEnd)
			{
				file.writeString("\n");
			}
		}
		else
		{
			file.writeString('$_indent$line${if (lineEnd) "\n" else ""}');
		}
	}

	private function openBracket (file, lineEnd=true) : Void
	{
		writeLine(file, "{", lineEnd);
		indentLevel++;
	}

	private function closeBracket (file) : Void
	{
		indentLevel--;
		writeLine(file, "}");
	}

	private function safeName (name:String) : String
	{
		return switch (name)
		{
			case "function":
				"fn";

			case "operator()":
				"operator_fn";

			case "break":
				"break_";

			//TODO: make a case for each operator
			//TODO: add all haxe keywords

			default:
				name.replace("=", "_eq").replace("!", "_neq").replace("[]", "_arraccess").replace("+=", "_eqadd").replace("+", "_add").replace("<<", "_in");
		}
	}

	private function getDefaultValue (param:Xml) : String
	{
		var defval = "";
		var e = param.elementsNamed("defval").next();

		if (e != null)
		{
			var it = e.iterator();
			var n;
			while (it.hasNext())
			{
				n = it.next();

				if (n.nodeType == Xml.PCData)
				{
					defval += n.nodeValue;
				}
				else
				{
					defval += toHaxeType(n.firstChild().nodeValue);
				}

			}
		}
		return defval;
	}

	private function toHaxeTemplateParams (memberdef:Xml) : Array<String>
	{
		var templates:Array<String> = [];

		for (templatelist in memberdef.elementsNamed("templateparamlist"))
		{
			for (param in templatelist.elementsNamed("param"))
			{
				var typename = getXmlContent(param, "type");

				if (typename.startsWith("typename "))
				{
					templates.push(typename.substr(9));
				}
			}
		}

		return templates;
	}

	private function toHaxeArgs (memberdef:Xml) : Args
	{
		var sep = function (s:String) : TypeValue
		{
			if (s.indexOf("::") > -1 && !s.startsWith("std::"))
			{
				var tmp = s.split("::");
				return Haxe('${getValue(toHaxeType(tmp[0]))}.${getValue(toHaxeType(tmp[1]))}');
			}
			else
			{
				return toHaxeType(s);
			}
		};

		var argsName = [];
		var argsType = [];
		var argsDefault = -1;

		var it = memberdef.elementsNamed("param");
		var i = -1;
		while (it.hasNext())
		{
			i++;
			var e = it.next();
			var type = toHaxeType(getType(e));
			var array = getXmlContent(e,"array");
			var value = getDefaultValue(e);

			if (value != "" && argsDefault == -1)
			{
				argsDefault = i;
			}

			if (array != "")
			{
				var array_number = array.split("[").length - 1;
				if (array_number == 0)
				{
					if (array.split(" ").length == 1)
					{
						//TODO: Ignore array value?
					}
					else
					{
						//TODO: the arg is a call to a function
					}
				}
				else
				{
					while (array_number > 0)
					{
						type = Haxe("Array<" + getValue(type) + ">");
						array_number--;
					}
				}
			}

			argsType.push(type);
			if (getValue(type) == "haxe.extern.Rest<Dynamic>")
			{
				argsName.push("otherArgs");
			}
			else
			{
				argsName.push(getXmlContent(e,"declname"));
			}
			//TODO: default value in wxList value_type() = T*
		}

		return { argsName: argsName, argsType: argsType, argsDefault: argsDefault };
	}

	private function argstringToArgs (argstring:String) : Args
	{
		var sep = function (s:String) : TypeValue
		{
			if (s.indexOf("::") > -1 && !s.startsWith("std::"))
			{
				var tmp = s.split("::");
				return Haxe('${getValue(toHaxeType(tmp[0]))}.${getValue(toHaxeType(tmp[1]))}');
			}
			else
			{
				return toHaxeType(s);
			}
		};

		var argsName = [];
		var argsType = [];
		var argsDefault = -1;

		if (argstring.endsWith("=0"))
		{
			trace(argstring);
			argstring = argstring.substr(0, argstring.length-2);
		}

		if (argstring.endsWith(" const "))
		{
			trace(argstring);
			argstring = argstring.substr(0, argstring.length-7);
		}

		if (argstring == "()")
		{
			return { argsName: [], argsType: [], argsDefault: -1 };
		}

		var args = argstring.substr(1, argstring.length-2).split(','); //TODO: not reliable, redo function
		var haxeArgs = [];
		var i = -1;

		for (arg in args)
		{
			i++;
			var type = arg.trim().split(" ");

			var name = type.pop();
			var pointerArg = false;
			var defaultValue = "";

			if (name.charAt(0) == '*') //TODO: **name (double *)
			{
				name = name.substr(1);
				pointerArg = true;
			}
			if (name.charAt(0) == '&')
			{
				//TODO: probably needs something, but they already are cpp.Ref so maybe not
				name = name.substr(1);
			}
			if (name.indexOf("=") > -1)
			{
				var tmp = name.split("=");
				name = tmp[0];
				defaultValue = getValue(sep(tmp[1]));

				var f = defaultValue.charCodeAt(0);
				if (f >= "0".code && f <= "9".code) // number
				{
					f = defaultValue.charCodeAt(defaultValue.length - 1);
					if (f == "u".code)
					{
						defaultValue = defaultValue.substr(0, defaultValue.length - 1);
					}
				}
			}

			if (type[0] == "const")
			{
				type.shift();
			}

			if (type.length == 2 && type[0] == "unsigned")
			{
				type.pop();

				if (type[1] == "int" || type[1] == "char")
				{
					type[0] = "UInt";
				}
				//~ //else
				//~ //{
				//~ //	type[0] = "long";
				//~ //}
			}

			var t = if (type.length == 0)
			{
				name = "_";
				toHaxeType(arg);
			}
			else
			{
				sep(type[0]);
			}

			if (pointerArg)
			{
				t = Haxe("cpp.Pointer<" + getValue(t) + ">");
			}

			//TODO: templated arg type; see Array.sort
			//TODO: List.resize default value " = Value_type()"

			var raw = name.split("[");
			name = raw[0];
			var array_number = raw.length -1;
			while (array_number > 0)
			{
				t = Haxe("Array<"+getValue(t)+">");
				array_number--;
			}
			name = safeName(name);

			argsName.push(name);
			argsType.push(t);

			if (defaultValue != "" && argsDefault == -1)
			{
				argsDefault = i;
			}
		}

		return { argsName: argsName, argsType: argsType, argsDefault: argsDefault };
	}

	private function toArgString (args:Args, ?bake:TypeValue->String) : String
	{
		if (bake == null)
		{
			bake = getValue;
		}

		var a = [];

		for (i in 0...args.argsName.length)
		{
			a.push('${safeName(args.argsName[i])}:${getValue(args.argsType[i])}');
		}

		return '(${a.join(", ")})';
	}

	private function parseFunctionSign (sign:String, name:String, realName:String) : Fn
	{
		var i = sign.indexOf("(");
		var returnType = sign.substr(0, i);
		sign = sign.substr(i+1);
		var t = sign.split(")(");

		if (t.length != 2)
		{
			return null;
		}

		if (t[0].startsWith("* "))
		{
			t[0] = t[0].substr(2);
		}

		if (t[0] != name && t[0] != '$realName::$name')
		{
			return null;
		}

		return { returnType: toHaxeType(returnType), args: argstringToArgs('(${t[1]}') };
	}

	private function fnType (fn:Fn) : TypeValue
	{
		var args = if (fn.args.argsType.length > 0) fn.args.argsType.join("->") else "Void";

		return Haxe('$args->${fn.returnType}');
	}

	private function groupOverloadAndDefaultParams (arr:Array<FunctionData>) : Array<FunctionData>
	{
		//TODO: also remove duplicate (created because haxe has less type than c++, eg. short int and int)

		arr.sort(function (a, b) {
			return -1 * Reflect.compare(a.name, b.name);
		});

		var res = [];

		var lastName = "";
		for (fn in arr)
		{
			if (fn.name == lastName)
			{
				fn.overload = true;
			}
			else
			{
				lastName = fn.name;
			}

			res.push(fn);

			var f:Int;
			if ((f = fn.args.argsDefault) > -1)
			{
				var n = fn.args.argsName.length;
				for (i in 1...(n-f+1))
				{
					var a = { argsDefault: fn.args.argsDefault, argsType: fn.args.argsType.slice(0, n-i), argsName: fn.args.argsName.slice(0, n-i) };
					var c = { returnType: fn.returnType, overload: true, native: "", name: fn.name, templatedParams: fn.templatedParams, doc: null, args: a };
					// fn (a:Int, b:Int = 2, c:Int = 3) => @ov(a:Int) + @ov(a:Int, b:Int) + fn(a:Int, b:Int, c:Int)
					res.push(c);
				}
			}
		}

		res.reverse();
		return res;
	}

	private function buildGlobal (memberdef:Xml, realName:String) : Void
	{
		switch (memberdef.get("kind"))
		{
			case "function":
				var obj = buildFunction(memberdef, "Global");

				if (obj != null)
				{
					global.classes[0].functions_stat.push(obj);
				}

			case "typedef":
				var obj = buildTypedef(memberdef, "Global");

				if (obj != null)
				{
					// put global typedef in their own files
					var f = getFile(obj.name);
					f.typedefs.push(obj);
					typedefs_list.set(obj.name, getValue(obj.value));
				}

			case "variable":
				var obj = buildVariable(memberdef, "Global");

				if (obj != null)
				{
					global.classes[0].variables_stat.push(obj);
				}

			default:
				trace("ignored (for now) GLOBAL memberdef type: " + memberdef.get("kind") + " in " + realName);
		}
	}

	private function buildFile (compounddef:Xml, inGlobal:Bool) : Void
	{
		var realName = getXmlContent(compounddef, "compoundname");

		for (section in compounddef.elementsNamed("sectiondef"))
		{
			switch (section.get("kind"))
			{
				case "enum", "user-defined", "var", "func", "typedef":
					for (memberdef in section.elementsNamed("memberdef"))
					{
						if (memberdef.get("prot") != "public")
						{
							continue; // not in the API
						}

						switch (memberdef.get("kind"))
						{
							case "enum":
								buildEnum(memberdef, realName);

							case "function", "variable":
								buildGlobal(memberdef, realName);

							case "typedef":
								if (inGlobal)
								{
									buildGlobal(memberdef, realName);
								}
								else
								{
									var t = buildTypedef(memberdef, realName);

									if (t != null)
									{
										var f = getFile(toHaxeName(t.name));
										f.typedefs.push(t);
										typedefs_list.set(t.name, getValue(t.value));
									}
								}

							case "define":
								// ignore
								continue;

							default:
								trace("ignored (for now) memberdef type: " + memberdef.get("kind") + " in " + realName);
						}
					}

				case "define":
					// ignore
					continue;

				default:
					trace("ignored (for now) sectiondef type: " + section.get("kind"));
			}
		}
	}

	private function buildEnum (memberdef:Xml, realName:String) : Void
	{
		var stat = memberdef.get("static") == "yes";
		var name = getXmlContent(memberdef, "name");
		var nameu = '${name}_';
		var nv = new Map<String, String>();

		var values = [];
		var vname;
		var vinit;
		var vid = -1;
		for (enumvalue in memberdef.elementsNamed("enumvalue"))
		{
			vname = getXmlContent(enumvalue, "name");
			vinit = getXmlContent(enumvalue, "initializer").substr(2).trim();

			if (vinit == "")
			{
				vid++;
				vinit = '${vid}';
			}
			else if (vinit.startsWith("0x"))
			{
				// all good
			}
			else
			{
				var i = Std.parseInt(vinit);

				if (i != null)
				{
					vid = i;
					vinit = '${vid}';
				}
				else if (nv.exists(vinit))
				{
					vinit = '${nv.get(vinit)}';
				}
				else if (vinit.indexOf("|") > -1)
				{
					var ts = vinit.split("|");
					var r = [];

					for (t in ts)
					{
						if (t.startsWith("\n"))
						{
							t = t.substr(1);
						}

						t = t.trim();

						if (t.startsWith("("))
						{
							t = t.substr(1);
						}

						if (t.endsWith(")"))
						{
							t = t.substr(0, t.length-1);
						}

						t = t.trim();

						if (nv.exists(t))
						{
							r.push('${nv.get(t)}');
						}
						else
						{
							//TODO: cross enum value
							//Lib.println('\nEnum error in "$name" unknown enum value "$t"');
						}
					}

					vinit = r.join(" | ");
				}
			}

			if (vname.startsWith(nameu))
			{
				vname = vname.substr(nameu.length);
			}

			//TODO: homogenised enum name
			nv.set(vname, vinit);
			values.push({ name: toHaxeName(vname), value: TypeValue.Cpp(vinit) });
		}

		if (name.charCodeAt(0) == "@".code)
		{
			if (values.length == 1)
			{
				// Explode into Global
				global.classes[0].variables_stat.push({ name: toHaxeName(values[0].name), type: Haxe("Int"), native: "", initializer: getValue(values[0].value), doc: null });
				return;
			}

			// Find longuest prefix in all value
			var prefix = values[0].name;
			var i;
			var l;
			for (value in values)
			{
				if (value.name.startsWith(prefix))
				{
					continue;
				}

				l = (prefix.length < value.name.length) ? prefix.length : value.name.length;
				i = 0;

				for (j in 0...l+1)
				{
					if (value.name.charAt(i) != prefix.charAt(i))
					{
						break;
					}
				}

				if (i == 0) // no prefix
				{
					prefix = "";
					break;
				}

				prefix = prefix.substr(0, i);
			}

			if (prefix == "")
			{
				// Explode into Global
				for (v in values)
				{
					 global.classes[0].variables_stat.push({ name: toHaxeName(v.name), type: Haxe("Int"), native: "", initializer: getValue(v.value), doc: null });
				}
				return;
			}

			for (i in 0...values.length)
			{
				values[i].name = values[i].name.substr(prefix.length); //TODO: also remove 'wx' (basePack)
			}

			if (prefix.endsWith("_"))
			{
				prefix = prefix.substr(0, prefix.length-1);
			}

			//TODO: Clean name
			name = prefix;
		}

		//TODO: if no need to find prefix still remove enum name from values' string
		//TODO: need to update arg default values if enum values are modified
		//TODO: pushing enums into their own file requires the update of their types in the functions signatures

		var e:EnumData = { name: toHaxeName(name), values: values, doc: memberdef };
		var f = getFile(e.name);
		f.enums.push(e);
	}

	private function buildFunction (memberdef:Xml, realName:String) : FunctionData
	{
		var stat = memberdef.get("static") == "yes";
		var name = getXmlContent(memberdef, "name"); //TODO: if name is create will bug with the static create function of the constructor
		var isConstructor = name == realName;
		var isDestructor = name.startsWith("~");// && name.substr(1) == realName; //TODO: doesn't work on templated classes
		var templatedParams = toHaxeTemplateParams(memberdef);
		var args = toHaxeArgs(memberdef);
		var type = toHaxeType(getType(memberdef));
		var native = (if (stat) '$realName::' else "") + name;

		//TODO: generic function <T>

		if (name.startsWith("operator"))
		{
			//TODO: abstract, uses inline proxy function for operators, and @:forward + haxe's dev version @:forwardStatics
			return null;
		}

		name = name.replace(" ", "_");

		if (isConstructor)
		{
			stat = true;
			name = toHaxeName(realName);
			type = Haxe(name);
			native = 'new $realName';
		}
		else
		{
			name = toHaxeName(name, true);
		}

		if (isDestructor)
		{
			//TODO: test if presence necessary
			//TODO: Array has multiple destructors with a name different from the class
			return null;
		}

		return { native: native, name: name, args: args, returnType: type, templatedParams: templatedParams, doc: memberdef, overload: false };
	}

	private function buildTypedef (memberdef:Xml, realName:String) : TypedefData
	{
		// syntax: typedef [const] type realName::name;

		var def = getXmlContent(memberdef, "definition").substr(8); //.split(" ");
		var name = getXmlContent(memberdef, "name");
		var tv;

		var longName = '$realName::$name'; //TODO: templated realName

		if (!def.endsWith(name))
		{
			var sign = parseFunctionSign(def, name, realName);

			if (sign == null)
			{
				//TODO: what is it?
				Lib.println('Typedef error in "$realName": name "$name" not found in $def');
				return null;
			}

			tv = fnType(sign);
		}
		else
		{
			tv = toHaxeType(getType(memberdef));
			//~ def = def.substr(0, def.length - longName.length);
		}

		return { name: toHaxeName(name), value: tv, doc: memberdef };
	}

	private function buildVariable (memberdef:Xml, realName:String) : VariableData
	{
		var name = getXmlContent(memberdef, "name");
		var initializer = getXmlContent(memberdef, "initializer").substr(2).trim();
		var type = toHaxeType(getType(memberdef));

		return { name: toHaxeName(name, true), native: name, initializer: initializer, type: type, doc: memberdef };
	}

	private function buildClass (compounddef:Xml) : Void
	{
		//TODO: templated sub class, eg. List<T>::iterator
		//TODO: cannot return generic version of templated class in haxe, see Bitmap.getHandlers():List missing the <T>

		var realName = getXmlContent(compounddef, "compoundname"); //TODO check what to put in @:native for templated classes, also to find (de)(con)structor
		var haxeName = toHaxeName(realName);
		var fileName = haxeName;

		if (realName.indexOf("::") > -1)
		{
			var tmp = realName.split("::");
			fileName = toHaxeName(tmp[0]);
			realName = tmp[1];
			haxeName = toHaxeName(realName);
		}

		var sup = toHaxeName(getXmlContent(compounddef, "basecompoundref"));
		var includes = getXmlContent(compounddef, "includes").split("/");
		var include = includes.splice(includes.length-2, includes.length).join("/");

		var functions_stat = new Array<FunctionData>();
		var functions = new Array<FunctionData>();
		var variables_stat = new Array<VariableData>();
		var variables = new Array<VariableData>();
		var typedefs = new Array<TypedefData>();

		var nb = 0;
		for (section in compounddef.elementsNamed("sectiondef"))
		{
			nb++;

			switch (section.get("kind"))
			{
				case "public-func", "user-defined", "public-static-func", "public-type", "public-attrib", "public-static-attrib":
					for (memberdef in section.elementsNamed("memberdef"))
					{
						if (memberdef.get("prot") != "public")
						{
							continue; // not in the API
						}

						switch (memberdef.get("kind"))
						{
							case "function":
								var obj = buildFunction(memberdef, realName);

								if (obj == null)
								{
									continue;
								}
								else if (memberdef.get("static") == "yes" || obj.name == toHaxeName(realName)) // constructor
								{
									functions_stat.push(obj);
								}
								else
								{
									functions.push(obj);
								}

							case "typedef":
								var obj = buildTypedef(memberdef, realName);

								if (obj == null)
								{
									continue;
								}
								else
								{
									typedefs.push(obj);
								}

							case "enum":
								buildEnum(memberdef, realName);

							case "variable":
								var obj = buildVariable(memberdef, realName);

								if (obj == null)
								{
									continue;
								}
								else if (memberdef.get("static") == "yes")
								{
									variables_stat.push(obj);
								}
								else
								{
									variables.push(obj);
								}

							default:
								trace("ignored (for now) memberdef type: " + memberdef.get("kind") + " in " + realName);
						}
					}

				case "protected-func", "protected-static-func", "protected-attrib", "protected-static-attrib", "protected-type", "private-static-attrib", "private-func", "private-attrib":
					// ignore, protected and private are not part of the API
					continue;

				case "typedef", "friend":
					// ignore //TODO: igore typedef?!
					continue;

				default:
					trace("ignored (for now) sectiondef type: " + section.get("kind"));
			}
		}

		if (nb > 0) // ignore empty classes
		{
			var c : ClassData = { name: haxeName, doc: compounddef, typedefs: typedefs, variables: variables, functions: functions, variables_stat: variables_stat, functions_stat: functions_stat, include: include, native: realName, sup: sup };

			var f = getFile(fileName);
			f.classes.push(c);
		}
	}

	private function getEithers (compounddef:Xml) : String
	{
		var it = compounddef.elementsNamed("sectiondef").next().elementsNamed("memberdef");
		var types = new Array<TypeValue>();

		while (it.hasNext())
		{
			var memberdef = it.next();
			if (memberdef.get("kind") == "variable")
			{
				var type = toHaxeType(getType(memberdef));
				var argsstring = memberdef.elementsNamed("argsstring").next().firstChild().nodeValue;
				var array_number = argsstring.split("[").length - 1;

				while (array_number > 0)
				{
					type = Haxe("Array<"+getValue(type)+">");
					array_number--;
				}
				types.push(type);
			}
		}

		if (types.length > 1)
		{
			var t2 = types.pop();
			var eithers = "haxe.extern.Either<"+types.pop()+", "+t2+">";
			while (types.length > 0)
			{
				eithers = "haxe.extern.Either<"+types.pop()+", "+eithers+">";
			}
			return eithers;
		}
		else
		{
			throw "Not an either if not at least 2 types";
		}

		return null;
	}

	private function buildUnion (compounddef:Xml) : Void
	{
		// see unionwx_any_value_buffer.xml
		//TODO: got Either<Dynamic, Byte> instead of Either<Function, Byte>

		var name = toHaxeName(getXmlContent(compounddef, "compoundname"));
		var eithers = getEithers(compounddef);

		var u:UnionData = { name: name, values: eithers, doc: compounddef };
		var f = getFile(name);
		f.unions.push(u);
	}

	private function fixNameClashBetweenMemberAndStatic (c:ClassData)
	{
		var members = new Map<String, Bool>();

		for (fn in c.functions)
		{
			members.set(fn.name, true);
		}

		for (fn in c.functions_stat)
		{
			if (members.exists(fn.name))
			{
				fn.name = "static_" + fn.name;
			}
		}
	}

	private function genFile (fd:FileData)
	{
		var pack = [basePack].concat(fd.pack);
		var file = getOutputFileStream(pack, fd.name);

		// File header
		writeLine(file, 'package${genPackage(pack)};');
		writeLine(file, "");
		writeLine(file, '// This file was generated by $PROG_NAME version $PROG_VERSION, DO NOT EDIT');
		writeLine(file, '// See $PROG_README about patching the generation');

		// Typedefs
		fd.typedefs.sort(function (a, b) {
			return Reflect.compare(a.name, b.name);
		});
		var lastTD = null;
		for (td in fd.typedefs)
		{
			if (lastTD != null && lastTD.name == td.name) //TODO: find duplication source
			{
				// ignore duplicates
				continue;
			}

			counter.typedefs++;
			writeLine(file, "");
			writeLine(file, 'typedef ${td.name} = ${getValue(td.value)};');

			lastTD = td;
		}

		// Enums //TODO: needs its own file?
		fd.enums.sort(function (a, b) {
			return Reflect.compare(a.name, b.name);
		});
		for (en in fd.enums)
		{
			counter.enums++;
			writeLine(file, "");
			writeLine(file, '@:enum abstract ${en.name} (Int)');
			openBracket(file);

			for (value in en.values)
			{
				 writeLine(file, 'var ${value.name} = ${getValue(value.value)};');
			}

			closeBracket(file);
		}

		// Unions
		fd.unions.sort(function (a, b) {
			return Reflect.compare(a.name, b.name);
		});
		for (un in fd.unions)
		{
			counter.unions++;
			writeLine(file, "");
			writeLine(file, 'typedef ${un.name} = ${un.values};');
		}

		// Classes
		for (c in fd.classes)
		{
			// Add patched variables
			if (patches.vars.exists(c.name))
			{
				for (variable in patches.vars.get(c.name))
				{
					c.variables.push(variable);
				}
			}

			// Add patched static variables
			if (patches.vars_static.exists(c.name))
			{
				for (variable in patches.vars_static.get(c.name))
				{
					c.variables_stat.push(variable);
				}
			}

			counter.classes++;

			fixNameClashBetweenMemberAndStatic(c);

			var toBake = new Map<String, String>();
			for (t in c.typedefs)
			{
				toBake.set(t.name, getValue(t.value));
			}

			// Add NameList => List<Name> //TODO: check it's really like this (wxWindowList, wxVariantList)
			toBake.set(c.name + "List", "List<" + c.name + ">");

			var bake = function (type:TypeValue) : String
			{
				var value : String = getValue(type);

				if (toBake.exists(value))
				{
					return toBake.get(value);
				}
				else
				{
					return value;
				}
			};

			// Class header
			if (c.name != "Global")
			{
				writeLine(file, "");
				if (c.include != "")
				{
					writeLine(file, '@:include("${c.include}")');
				}

				if (c.native != "")
				{
					writeLine(file, '@:native("${c.native}")');
				}

				var ext = typedefs_list.exists(c.sup) ? typedefs_list.get(c.sup) : c.sup;
				writeLine(file, 'extern class _${c.name}${if (c.sup != "") " extends " + ext + "._" + ext else ""}');
				openBracket(file, false);

				c.variables.sort(function (a, b) {
					return Reflect.compare(a.name, b.name);
				});
				for (variable in c.variables)
				{
					if (patches.updated_vars.exists('${c.name}.${variable.name}'))
					{
						variable.initializer = patches.updated_vars.get('${c.name}.${variable.name}');
					}

					writeLine(file, "");
					genDoc(variable.doc, file);
					writeLine(file, '@:native("${variable.native}") public var ${variable.name} : ${bake(variable.type)}${if (variable.initializer != "") " = " + variable.initializer else ""};');
				}

				//TODO: check double functions with and without const modifier
				var inOverload = false;
				for (fn in groupOverloadAndDefaultParams(c.functions))
				{
					if (!inOverload)
					{
						writeLine(file, "");
						genDoc(fn.doc, file);
					}

					var templatedParams = (fn.templatedParams.length > 0) ? "<"+fn.templatedParams.join(", ")+"> " : "";
					if (fn.overload)
					{
						inOverload = true;

						writeLine(file, '@:overload(function${templatedParams} ${toArgString(fn.args, bake)} : ${bake(fn.returnType)} {})');
					}
					else
					{
						inOverload = false;

						writeLine(file, '@:native("${fn.native}") public function ${fn.name}${templatedParams} ${toArgString(fn.args, bake)} : ${bake(fn.returnType)};');
					}
				}

				// End of class
				closeBracket(file);
			}

			// Ref class
			writeLine(file, "");
			genDoc(c.doc, file);
			if (c.native != "")
			{
				writeLine(file, '@:native("cpp.Reference<${c.native}>")');
			}
			if (c.name == "Global")
			{
				writeLine(file, 'extern class ${c.name}');
			}
			else
			{
				writeLine(file, 'extern class ${c.name} extends _${c.name}');
			}
			openBracket(file, (c.variables_stat.length == 0 && c.functions_stat.length == 0));

			c.variables_stat.sort(function (a, b) {
				return Reflect.compare(a.name, b.name);
			});
			for (variable in c.variables_stat) // TODO : if c.native and/or variable.native are empty strings
			{
				if (patches.updated_vars.exists('${c.name}.${variable.name}'))
				{
					variable.initializer = patches.updated_vars.get('${c.name}.${variable.name}');
				}

				writeLine(file, "");
				genDoc(variable.doc, file);
				writeLine(file, '@:native("${c.native}::${variable.native}") public static var ${variable.name} : ${bake(variable.type)}${if (variable.initializer != "") " = " + variable.initializer else ""};');
			}

			var inOverload = false;
			for (fn in groupOverloadAndDefaultParams(c.functions_stat))
			{
				if (!inOverload)
				{
					writeLine(file, "");
					genDoc(fn.doc, file);
				}

				var templatedParams = (fn.templatedParams.length > 0) ? "<"+fn.templatedParams.join(", ")+"> " : "";
				if (fn.overload)
				{
					inOverload = true;

					writeLine(file, '@:overload(function${templatedParams} ${toArgString(fn.args, bake)} : ${bake(fn.returnType)} {})');
				}
				else
				{
					inOverload = false;

					writeLine(file, '@:native("${fn.native}") public static function ${fn.name}${templatedParams} ${toArgString(fn.args, bake)} : ${bake(fn.returnType)};');
				}
			}

			// End of ref class
			closeBracket(file);
		}

		// End of file
		file.flush();
		file.close();
	}
}
