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
