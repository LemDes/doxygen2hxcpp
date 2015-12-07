package data;

typedef FileData = {
	pack:Array<String>,
	name:String,
	typedefs:Array<TypedefData>,
	classes:Array<ClassData>,
	enums:Array<EnumData>,
	unions:Array<UnionData>
};
