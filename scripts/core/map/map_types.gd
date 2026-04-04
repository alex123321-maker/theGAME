extends RefCounted
class_name MapTypes

enum TerrainType {
	GROUND,
	CLEARING,
	ROAD,
	WATER,
	BLOCKER,
	RAVINE_EDGE,
	FOREST,
	ROCK,
	RAVINE,
}

enum HeightClass {
	LOW,
	MID,
	HIGH,
	DROP_EDGE,
}

enum RegionType {
	NONE,
	CENTER_CLEARING,
	APPROACH_CORRIDOR,
	BLOCKER_MASS,
	WATER_REGION,
	OPEN_GROUND,
}

enum BlockerType {
	NONE,
	FOREST,
	ROCK,
	RAVINE,
}

enum RockRole {
	NONE,
	FOOT,
	TALUS,
	SHELF,
	WALL,
	SUMMIT,
}

enum RockSummitProfile {
	NONE,
	PEAK,
	PLATEAU,
	BROKEN_TOP,
}

enum RoadWidthClass {
	NONE,
	NARROW,
	MEDIUM,
}

enum TransitionType {
	NONE,
	WET_EDGE,
	ROAD_EDGE,
	CLEARING_EDGE,
	BLOCKER_EDGE,
	RAVINE_EDGE,
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
		TerrainType.CLEARING:
			return "clearing"
		TerrainType.ROAD:
			return "road"
		TerrainType.WATER:
			return "water"
		TerrainType.BLOCKER:
			return "blocker"
		TerrainType.RAVINE_EDGE:
			return "ravine_edge"
		TerrainType.FOREST:
			return "forest"
		TerrainType.ROCK:
			return "rock"
		TerrainType.RAVINE:
			return "ravine"
		_:
			return "unknown"

static func height_name(value: int) -> String:
	match value:
		HeightClass.LOW:
			return "low"
		HeightClass.MID:
			return "normal"
		HeightClass.HIGH:
			return "high"
		HeightClass.DROP_EDGE:
			return "drop_edge"
		_:
			return "unknown"

static func region_name(value: int) -> String:
	match value:
		RegionType.CENTER_CLEARING:
			return "center_clearing"
		RegionType.APPROACH_CORRIDOR:
			return "approach_corridor"
		RegionType.BLOCKER_MASS:
			return "blocker_mass"
		RegionType.WATER_REGION:
			return "water_region"
		RegionType.OPEN_GROUND:
			return "open_ground"
		_:
			return "none"

static func blocker_name(value: int) -> String:
	match value:
		BlockerType.FOREST:
			return "forest"
		BlockerType.ROCK:
			return "rock"
		BlockerType.RAVINE:
			return "ravine"
		_:
			return "none"

static func rock_role_name(value: int) -> String:
	match value:
		RockRole.FOOT:
			return "foot"
		RockRole.TALUS:
			return "talus"
		RockRole.SHELF:
			return "shelf"
		RockRole.WALL:
			return "wall"
		RockRole.SUMMIT:
			return "summit"
		_:
			return "none"

static func rock_summit_profile_name(value: int) -> String:
	match value:
		RockSummitProfile.PEAK:
			return "peak"
		RockSummitProfile.PLATEAU:
			return "plateau"
		RockSummitProfile.BROKEN_TOP:
			return "broken_top"
		_:
			return "none"

static func road_width_name(value: int) -> String:
	match value:
		RoadWidthClass.NARROW:
			return "narrow"
		RoadWidthClass.MEDIUM:
			return "medium"
		_:
			return "none"

static func transition_name(value: int) -> String:
	match value:
		TransitionType.WET_EDGE:
			return "wet_edge"
		TransitionType.ROAD_EDGE:
			return "road_edge"
		TransitionType.CLEARING_EDGE:
			return "clearing_edge"
		TransitionType.BLOCKER_EDGE:
			return "blocker_edge"
		TransitionType.RAVINE_EDGE:
			return "ravine_edge"
		_:
			return "none"

static func surface_priority(terrain_type: int) -> int:
	match terrain_type:
		TerrainType.RAVINE_EDGE:
			return 500
		TerrainType.WATER:
			return 400
		TerrainType.BLOCKER, TerrainType.FOREST, TerrainType.ROCK, TerrainType.RAVINE:
			return 350
		TerrainType.ROAD:
			return 300
		TerrainType.CLEARING:
			return 200
		TerrainType.GROUND:
			return 100
		_:
			return 0
