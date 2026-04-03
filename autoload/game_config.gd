extends Node

const GENERATOR_VERSION: int = 2
const DEFAULT_MAP_WIDTH: int = 96
const DEFAULT_MAP_HEIGHT: int = 96
const DEFAULT_ENTRY_COUNT: int = 3
const DEFAULT_MIN_CENTER_AREA: int = 300
const DEFAULT_MAX_CENTER_AREA: int = 520
const DEFAULT_VILLAGE_TILE_COUNT: int = 420
const DEFAULT_WATER_CHANCE: float = 0.55
const DEFAULT_MIN_WATER_AREA: int = 120
const DEFAULT_MAX_WATER_AREA: int = 240
const DEFAULT_BLOCKER_COUNT: int = 2
const DEFAULT_MIN_BLOCKER_AREA: int = 160
const DEFAULT_MAX_BLOCKER_AREA: int = 320
const DEFAULT_ROAD_CURVATURE: float = 0.12
const DEFAULT_MIN_BLOCKER_DISTANCE_FROM_CENTER: int = 18
const DEFAULT_APPROACH_PADDING: int = 6
const DEFAULT_MIN_PATH_WIDTH: int = 2
const MIN_ENTRY_COUNT: int = 2
const MAX_ENTRY_COUNT: int = 4
const MIN_VILLAGE_TILE_COUNT: int = DEFAULT_MIN_CENTER_AREA
const MAX_VILLAGE_TILE_COUNT: int = DEFAULT_MAX_CENTER_AREA
const TILE_SIZE: int = 16

const OVERLAY_MODES: Array[String] = [
	"none",
	"base_terrain",
	"regions",
	"roads",
	"water",
	"blockers",
	"buildable",
	"validation",
]

const BLOCKED_TERRAINS: Array[int] = [
	MapTypes.TerrainType.WATER,
	MapTypes.TerrainType.BLOCKER,
	MapTypes.TerrainType.RAVINE_EDGE,
]

const REFERENCE_SEEDS: Array[int] = [
	101,
	777,
	20260401,
	17,
	33,
	55,
	89,
	144,
	233,
	377,
	610,
]

static func build_default_generator_config() -> Dictionary:
	return {
		"width": DEFAULT_MAP_WIDTH,
		"height": DEFAULT_MAP_HEIGHT,
		"entry_count": DEFAULT_ENTRY_COUNT,
		"village_tile_count": DEFAULT_VILLAGE_TILE_COUNT,
		"min_center_area": DEFAULT_MIN_CENTER_AREA,
		"max_center_area": DEFAULT_MAX_CENTER_AREA,
		"water_chance": DEFAULT_WATER_CHANCE,
		"min_water_area": DEFAULT_MIN_WATER_AREA,
		"max_water_area": DEFAULT_MAX_WATER_AREA,
		"blocker_count": DEFAULT_BLOCKER_COUNT,
		"min_blocker_area": DEFAULT_MIN_BLOCKER_AREA,
		"max_blocker_area": DEFAULT_MAX_BLOCKER_AREA,
		"road_curvature": DEFAULT_ROAD_CURVATURE,
		"min_blocker_distance_from_center": DEFAULT_MIN_BLOCKER_DISTANCE_FROM_CENTER,
		"approach_padding": DEFAULT_APPROACH_PADDING,
		"minimum_path_width": DEFAULT_MIN_PATH_WIDTH,
	}
