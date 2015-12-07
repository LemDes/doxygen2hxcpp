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

package data;

typedef ClassData = {
	name:String,
	variables:Array<VariableData>,
	variables_stat:Array<VariableData>,
	functions:Array<FunctionData>,
	functions_stat:Array<FunctionData>,
	doc:Xml,
	sup:String,
	native:String,
	include:String,
	typedefs:Array<TypedefData>
};
