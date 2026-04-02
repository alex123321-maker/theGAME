extends Node

const GENERATOR_VERSION: int = 1
const DEFAULT_MAP_WIDTH: int = 96
const DEFAULT_MAP_HEIGHT: int = 96
const DEFAULT_ENTRY_COUNT: int = 3
const DEFAULT_CENTRAL_ZONE_RADIUS: int = 12
const DEFAULT_VILLAGE_TILE_COUNT: int = 420
const MIN_ENTRY_COUNT: int = 1
const MAX_ENTRY_COUNT: int = 4
const MIN_VILLAGE_TILE_COUNT: int = 24
const MAX_VILLAGE_TILE_COUNT: int = 1800
const TILE_SIZE: int = 16

const OVERLAY_MODES: Array[String] = [
	"none",
	"height",
	"buildable",
	"threat",
	"resources"
]

const BLOCKED_TERRAINS: Array[int] = [4, 5] # WATER, RAVINE

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
		"central_zone_radius": DEFAULT_CENTRAL_ZONE_RADIUS,
		"village_tile_count": DEFAULT_VILLAGE_TILE_COUNT,
		"forest_cluster_count": 7,
		"rock_cluster_count": 4,
		"water_cluster_count": 2,
	}
