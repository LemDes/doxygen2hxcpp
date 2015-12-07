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
