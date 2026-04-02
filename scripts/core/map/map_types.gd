extends RefCounted
class_name MapTypes

enum TerrainType {
	GROUND,
	ROAD,
	FOREST,
	ROCK,
	WATER,
	RAVINE,
	CLEARING,
}

enum HeightClass {
	LOW,
	MID,
	HIGH,
}

enum ResourceTag {
	NONE,
	WOOD,
	STONE,
	MIXED,
}

enum PoiTag {
	NONE,
	ENTRY,
	OVERLOOK,
	BOTTLENECK,
	RESOURCE_CLUSTER,
}

static func terrain_name(value: int) -> String:
	match value:
		TerrainType.GROUND:
			return "ground"
		TerrainType.ROAD:
			return "road"
		TerrainType.FOREST:
			return "forest"
		TerrainType.ROCK:
			return "rock"
		TerrainType.WATER:
			return "water"
		TerrainType.RAVINE:
			return "ravine"
		TerrainType.CLEARING:
			return "clearing"
		_:
			return "unknown"
