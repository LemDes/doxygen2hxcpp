package data;

typedef FunctionData = {
	native:String,
	args:Args,
	name:String,
	returnType:TypeValue,
	templatedParams:Array<String>,
	doc:Xml,
	overload:Bool
};
