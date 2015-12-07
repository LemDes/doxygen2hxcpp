import data.*;

class PatchFile
{
	var ignored = new Map<String, Bool>();
	public var typedefs = new Array<TypedefData>();
	public var vars = new Map<String, Array<VariableData>>();
	public var vars_static = new Map<String, Array<VariableData>>();
	
	public var updated_vars = new Map<String, String>();

	public function new (?xml:Xml)
	{
		if (xml == null)
		{
			// no patch
		}
		else
		{
			// read patches
			var root = xml.elementsNamed("root").next();
			for (operation in root.elements())
			{
				switch (operation.nodeName)
				{
					case "ignore":
						for (e in operation.elementsNamed("item"))
						{
							ignored.set(e.get("name"), true);
						}

					case "add":
						for (e in operation.elements())
						{
							switch (e.nodeName)
							{
								case "typedef":
									typedefs.push({ name: e.get("name"), value: Haxe(e.get("is")), doc: null });
									
								case "var":
									var file = e.get("file");
									var obj = { name: e.get("name"), native: "", initializer: e.get("value"), type: TypeValue.Haxe(e.get("type")), doc: null };

									if (e.get("static") == "true")
									{
										if (!vars_static.exists(file))
										{
											vars_static.set(file,new Array<VariableData>());
										}

										vars_static.get(file).push(obj);
									}
									else
									{
										if (!vars.exists(file))
										{
											vars.set(file, new Array<VariableData>());
										}

										vars.get(file).push(obj);
									}
							}
						}

					case "set" :
						for (e in operation.elements())
						{
							switch (e.nodeName)
							{
								case "var":
									var name = e.get("name");
									var key = e.get("file") + "." + name;
									updated_vars.set(key, e.get("value"));
							}
						}
				}
			}
		}
	}

	public inline function ignores (name:String) : Bool
	{
		return ignored.exists(name);
	}
}
