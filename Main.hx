import haxe.io.Path;
import sys.io.File;
import sys.io.FileOutput;
import sys.FileSystem;

#if cpp
import cpp.Lib;
#else
import neko.Lib;
#end

using StringTools;

typedef Args = { argsName:Array<String>, argsType:Array<String>, argsValue:Array<String> };
typedef Fn = { returnType:String, args:Args };
typedef FunctionData = { native:String, args:Args, name:String, returnType:String, doc:Xml };
typedef VariableData = { name:String, initializer:String, type:String, doc:Xml };

class PatchFile
{
	public function new (?xml:Xml)
	{
		if (xml == null)
		{
			// no patch
		}
		else
		{
			// read patches
		}
	}
}

class Main
{
	public static function main ()
	{
		new Main();
	}
	
	private var patches : PatchFile;
	private var used = new Map<String, Bool>();
	private var nb = 0;
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
		
		var index = Xml.parse(File.getContent(Path.join([ inputPath, "index.xml" ]))).firstElement();
		
		if (!index.get("version").startsWith("1.8."))
		{
			Lib.println("The xml isn't version 1.8.*, may not work");
		}
		
		var file;
		for (compound in index.elements())
		{
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
					//TODO: there is at least some enums in there
					//TODO: check if they aren't also elsewhere
					continue;
				
				case "dir", "page", "group":
					// ignore
					//TODO: check the xmls to be sure
					continue;
				
				default:
					// no "interface" wxWidgets, ignore for now
					trace("ignored (for now) compound type: " + compound.get("kind"));
					continue;
			}
		}
		
		Lib.println('\nDone! $nb files generated.');
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
	
	private function toHaxeType (cppType:String) : String
	{
		if (cppType == "void *")
		{
			// any pointer
			return "Dynamic";
		}
		
		if (cppType.indexOf("(") > -1)
		{
			
			// returnType(*|T::*)(Type a, Type b)
			var tmp = cppType.split("(");
			var returnType = toHaxeType(tmp[0]);
			
			var paramString = tmp[tmp.length-1];
			var parameters = paramString.substr(0,paramString.length-1).split(",");
			
			var type = "";
			for (param in parameters)
			{
				type += toHaxeType(param.ltrim().split(" ")[0]) + " -> ";
			}
			type += returnType;
			return type;
		}
		
		if (cppType.indexOf("::") > -1)
		{
			var tmp = cppType.split("::");
			return '${toHaxeType(tmp[0])}.${toHaxeType(tmp[1])}';
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
		
		var type = switch (cppType)
		{
			case "...":
				"haxe.extern.Rest<Dynamic>"; //TODO: better than dynamic?
			
			case "bool":
				"Bool";
				
			case "char", "int":
				"Int";
				
			case "", "void":
				"Void";
				
			case "unsigned char", "unsigned", "size_t", "UInt":
				"UInt";
				
			case "float", "double", "long":
				"Float";
				
			case "std::string", "std::wstring":
				"String";
				
			default:
				toHaxeName(cppType);
		};
		
		if (pointer)
		{
			return 'cpp.Pointer<$type>';
		}
		else if (arrayarray)
		{
			return 'Array<cpp.Pointer<$type>>';
		}
		else
		{
			return type;
		}
	}
	
	private function writeLine (file:FileOutput, line:String, lineEnd=true) : Void
	{
		file.writeString('$_indent$line${if (lineEnd) "\n" else ""}');
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
	
	private function toHaxeArgs (memberdef:Xml) : Args
	{
		var sep = function (s:String) : String
		{
			if (s.indexOf("::") > -1 && !s.startsWith("std::"))
			{
				var tmp = s.split("::");
				return '${toHaxeType(tmp[0])}.${toHaxeType(tmp[1])}';
			}
			else
			{
				return toHaxeType(s);
			}
		};
		
		var argsName = [];
		var argsValue = [];
		var argsType = [];
		
		var it = memberdef.elementsNamed("param");
		while (it.hasNext())
		{
			var e = it.next();
			var type = toHaxeType(getType(e));
			var array = getXmlContent(e,"array");
			var value = getDefaultValue(e);
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
						type = "Array<"+type+">";
						array_number--;
					}
				}
			}
			
			argsType.push(type);			
			if (type == "haxe.extern.Rest<Dynamic>")
			{
				argsName.push("otherArgs");
			}
			else
			{
				argsName.push(getXmlContent(e,"declname"));
			}
			argsValue.push(value);
			//TODO: default value in wxList value_type() = T*
		}
		
		return { argsName: argsName, argsType: argsType, argsValue: argsValue };
	}
	
	private function argstringToArgs (argstring:String) : Args
	{	
		var sep = function (s:String) : String
		{
			if (s.indexOf("::") > -1 && !s.startsWith("std::"))
			{
				var tmp = s.split("::");
				return '${toHaxeType(tmp[0])}.${toHaxeType(tmp[1])}';
			}
			else
			{
				return toHaxeType(s);
			}
		};
		
		var argsName = [];
		var argsValue = [];
		var argsType = [];
		
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
			return { argsName: [], argsType: [], argsValue: [] };
		}
		
		var args = argstring.substr(1, argstring.length-2).split(','); //TODO: not reliable, redo function
		var haxeArgs = [];
		
		for (arg in args)
		{			
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
				defaultValue = sep(tmp[1]);
				
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
				t = 'cpp.Pointer<$t>';
			}
			
			//TODO: templated arg type; see Array.sort
			//TODO: List.resize default value " = Value_type()"
			
			var raw = name.split("[");
			name = raw[0];
			var array_number = raw.length -1;
			while (array_number > 0)
			{
				t = "Array<"+t+">";
				array_number--;
			}
			name = safeName(name);
			
			argsName.push(name);
			argsType.push(t);
			argsValue.push(defaultValue);
		}
		
		return { argsName: argsName, argsType: argsType, argsValue: argsValue };
	}
	
	private function toArgString (args:Args) : String
	{
		var a = [];
		
		for (i in 0...args.argsName.length)
		{
			a.push('${args.argsName[i]}:${args.argsType[i]}${if (args.argsValue[i] != "") " = " + args.argsValue[i] else ""}');
		}
		
		return '(${a.join(", ")})';
	}
	
	private function parseFunctionSign (sign:String, name:String) : Fn
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
		
		if (t[0] != name)
		{
			return null;
		}
		
		return { returnType: toHaxeType(returnType), args: argstringToArgs('(${t[1]}') };
	}
	
	private function fnType (fn:Fn) : String
	{
		var args = if (fn.args.argsType.length > 0) fn.args.argsType.join("->") else "Void";
		
		return '$args->${fn.returnType}';
	}
	
	private function buildClass (compounddef:Xml) : Void
	{
		//TODO: templated sub class, eg. List<T>::iterator
		//TODO: cannot return generic version of templated class in haxe, see Bitmap.getHandlers():List missing the <T>
		
		var realName = getXmlContent(compounddef, "compoundname"); //TODO check what to put in @:native for templated classes, also to find (de)(con)structor
		var haxeName = toHaxeName(realName);
		
		if (realName.indexOf(":") > -1)
		{
			//TODO: A::B, add class B to class A's file
			//~ return;
		}
		
		var pack = [basePack];
		var sup = toHaxeName(getXmlContent(compounddef, "basecompoundref"));
		var includes = getXmlContent(compounddef, "includes").split("/");
		var include = includes.splice(includes.length-2, includes.length).join("/");
		
		var file = getOutputFileStream(pack, haxeName);
		
		var functions_stat = new Array<FunctionData>();
		var functions = new Array<FunctionData>();
		var variables_stat = new Array<VariableData>();
		var variables = new Array<VariableData>();
		var typedefs = new Array<{ name:String, value:String }>();
		var enums = new Array<{ name:String, values: Array<String> }>();

		for (section in compounddef.elementsNamed("sectiondef"))
		{
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
								var stat = memberdef.get("static") == "yes";
								var name = getXmlContent(memberdef, "name"); //TODO: if name is create will bug with the static create function of the constructor
								var isConstructor = name == realName;
								var isDestructor = name.startsWith("~") && name.substr(1) == realName; //TODO: doesn't work on templated classes
								var args = toHaxeArgs(memberdef);
								var type = toHaxeType(getType(memberdef));
								var native = (if (stat) '$realName::' else "") + name;
								
								//TODO: generic function <T>
								
								if (name.startsWith("operator"))
								{
									//TODO: abstract?
									continue;
								}
																
								name = name.replace(" ", "_");								
								
								if (isConstructor)
								{
									stat = true;
									name = "create";									
									type = haxeName;
									native = 'new $realName';									
								}
								
								if (isDestructor)
								{
									//TODO: test if presence necessary
									//TODO: Array has multiple destructors with a name different from the class
									continue;
								}
								
								var obj = { native: native, name: name, args: args, returnType: type, doc: memberdef };

								if (stat)
								{
									functions_stat.push(obj);
								}
								else
								{
									functions.push(obj);
								}
							
							case "typedef":
								// syntax: typedef [const] type realName::name;
								
								var def = getXmlContent(memberdef, "definition").substr(8); //.split(" ");
								var name = getXmlContent(memberdef, "name");
								var longName = '$realName::$name'; //TODO: templated realName
								
								if (!def.endsWith(longName))
								{
									var sign = parseFunctionSign(def, longName);
									
									if (sign == null)
									{
										//TODO: what is it?									
										Lib.println('Typedef error in "$realName": name "$name" not found in $def');
										continue;
									}
									
									def = fnType(sign);
								}
								else
								{
									def = def.substr(0, def.length - longName.length);
								}
								
								typedefs.push({ name: name, value: def });
								
							case "enum":							
								var stat = memberdef.get("static") == "yes";
								var name = getXmlContent(memberdef, "name");
								var nameu = '${name}_';
								
								var values = [];
								var vname;
								var vinit;
								var nbInit = 0;
								for (enumvalue in memberdef.elementsNamed("enumvalue"))
								{
									vname = getXmlContent(enumvalue, "name");
									vinit = getXmlContent(enumvalue, "initializer");
									
									if (vinit != "")
									{
										nbInit++;
									}
									
									if (vname.startsWith(nameu))
									{
										vname = vname.substr(nameu.length);
									}
									
									values.push('$vname${if (vinit != "") " " + vinit else ""};');
								}
								
								if (nbInit > 0 && nbInit != values.length)
								{
									//TODO: what to do?							
									Lib.println('Enum error in "$realName": named "$name" has mix of initializer presence/absence');
									continue;
								}
								
								if (name.charCodeAt(0) == "@".code)
								{
									if (values.length == 1)
									{
										//TODO: ask for patch
										Lib.println('Enum error in "$realName": nameless ($name) with only one value but no patch');
										continue;
									}
									
									// Find longuest prefix in all value
									var prefix = values[0];
									var i;
									var l;
									for (value in values)
									{										
										if (value.startsWith(prefix))
										{
											continue;
										}
										
										l = (prefix.length < value.length) ? prefix.length : value.length;
										i = 0;
										
										for (j in 0...l+1)
										{											
											if (value.charAt(i) != prefix.charAt(i))
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
										//TODO: ask for patch
										Lib.println('Enum error in "$realName": nameless ($name) with no common prefix and no patch');
										continue;
									}
									
									for (i in 0...values.length)
									{
										values[i] = values[i].substr(prefix.length); //TODO: also remove 'wx' (basePack)
									}
									
									if (prefix.endsWith("_"))
									{
										prefix = prefix.substr(0, prefix.length-1);
									}
									
									//TODO: Clean name
									name = prefix;
								}
								
								//TODO: if no need to find prefix still remove enum name from values' string

								enums.push({ name: name, values: values });
								
							case "variable":
								var name = getXmlContent(memberdef, "name");
								var initializer = getXmlContent(memberdef, "initializer");
								var type = toHaxeType(getType(memberdef));
								
								var obj = { name: name, initializer: initializer, type: type, doc: memberdef };

								if (memberdef.get("static") == "yes")
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
					continue;
			}
		}
		
		// File header
		writeLine(file, 'package${genPackage(pack)};');

		// Typedefs
		for (tp in typedefs)
		{
			writeLine(file, "");
			writeLine(file, 'typedef ${tp.name} = ${toHaxeType(tp.value)};');
		}

		// Enums //TODO: needs its own file?
		for (en in enums)
		{
			writeLine(file, "");
			writeLine(file, 'enum ${toHaxeName(en.name)}');
			openBracket(file);

			for (value in en.values)
			{
				writeLine(file, value);
			}

			closeBracket(file);
		}

		// Class header
		writeLine(file, "");
		writeLine(file, '@:include("$include")');
		writeLine(file, '@:native("$realName")');
		writeLine(file, 'extern class _$haxeName${if (sup != "") " extends " + sup + "._" + sup else ""}');
		openBracket(file, false);

		for (variable in variables)
		{
			writeLine(file, "");
			genDoc(variable.doc, file);
			writeLine(file, '@:native("${variable.name}") public var ${toHaxeName(variable.name, true)} : ${variable.type}${if (variable.initializer != "") " " + variable.initializer else ""};');
		}

		//TODO: group together to do function overloading, also check double functions with and without const modifier
		for (fn in functions)
		{
			writeLine(file, "");
			genDoc(fn.doc, file);
			writeLine(file, '@:native("${fn.native}") public function ${toHaxeName(fn.name, true)} ${toArgString(fn.args)} : ${fn.returnType};');
		}

		// End of class
		closeBracket(file);
		writeLine(file, "");

		// Ref class
		genDoc(compounddef, file);
		writeLine(file, '@:native("cpp.Reference<$realName>")');
		writeLine(file, 'extern class $haxeName extends _$haxeName');
		openBracket(file, (variables_stat.length == 0 && functions_stat.length == 0));

		for (variable in variables_stat)
		{
			writeLine(file, "");
			genDoc(variable.doc, file);
			writeLine(file, '@:native("$realName::${variable.name}") public var ${toHaxeName(variable.name, true)} : ${variable.type}${if (variable.initializer != "") " " + variable.initializer else ""};');
		}
		
		for (fn in functions_stat)
		{
			writeLine(file, "");
			genDoc(fn.doc, file);
			writeLine(file, '@:native("${fn.native}") public static function ${toHaxeName(fn.name, true)} ${toArgString(fn.args)} : ${fn.returnType};');
		}
		
		// End of ref class
		closeBracket(file);
		
		// End of file
		file.flush();
		file.close();
	}
	
	private function getEithers (compounddef:Xml) : String
	{
		var it = compounddef.elementsNamed("sectiondef").next().elementsNamed("memberdef");
		var types = new Array<String>();
		
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
					type = "Array<"+type+">";
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
		var realName = getXmlContent(compounddef, "compoundname");		
		var haxeName = toHaxeName(realName);
		
		var pack = [basePack];
		var sup = toHaxeName(getXmlContent(compounddef, "basecompoundref"));
		var eithers = getEithers(compounddef);
				
		var file = getOutputFileStream(pack, haxeName);
		
		writeLine(file, 'package${genPackage(pack)};');
		writeLine(file, "");
		writeLine(file, 'typedef $haxeName = $eithers;');
		
		file.flush();
		file.close();

		// see unionwx_any_value_buffer.xml
		//TODO: got Either<Dynamic, Byte> instead of Either<Function, Byte>
	}
}
