extends RefCounted
class_name MapGenerationConfig

const GameConfigData = preload("res://autoload/game_config.gd")

var width: int = GameConfigData.DEFAULT_MAP_WIDTH
var height: int = GameConfigData.DEFAULT_MAP_HEIGHT
var profile_id: String = "default"
var entry_count: int = GameConfigData.DEFAULT_ENTRY_COUNT
var min_center_area: int = GameConfigData.DEFAULT_MIN_CENTER_AREA
var max_center_area: int = GameConfigData.DEFAULT_MAX_CENTER_AREA
var water_chance: float = GameConfigData.DEFAULT_WATER_CHANCE
var min_water_area: int = GameConfigData.DEFAULT_MIN_WATER_AREA
var max_water_area: int = GameConfigData.DEFAULT_MAX_WATER_AREA
var blocker_count: int = GameConfigData.DEFAULT_BLOCKER_COUNT
var min_blocker_area: int = GameConfigData.DEFAULT_MIN_BLOCKER_AREA
var max_blocker_area: int = GameConfigData.DEFAULT_MAX_BLOCKER_AREA
var road_curvature: float = GameConfigData.DEFAULT_ROAD_CURVATURE
var min_blocker_distance_from_center: int = GameConfigData.DEFAULT_MIN_BLOCKER_DISTANCE_FROM_CENTER
var approach_padding: int = GameConfigData.DEFAULT_APPROACH_PADDING
var minimum_path_width: int = GameConfigData.DEFAULT_MIN_PATH_WIDTH

func to_dict() -> Dictionary:
	return {
		"width": width,
		"height": height,
		"profile_id": profile_id,
		"entry_count": entry_count,
		"min_center_area": min_center_area,
		"max_center_area": max_center_area,
		"water_chance": water_chance,
		"min_water_area": min_water_area,
		"max_water_area": max_water_area,
		"blocker_count": blocker_count,
		"min_blocker_area": min_blocker_area,
		"max_blocker_area": max_blocker_area,
		"road_curvature": road_curvature,
		"min_blocker_distance_from_center": min_blocker_distance_from_center,
		"approach_padding": approach_padding,
		"minimum_path_width": minimum_path_width,
	}

func apply_from_dict(source: Dictionary) -> void:
	var requested_center_area: int = int(source.get("village_tile_count", GameConfigData.DEFAULT_VILLAGE_TILE_COUNT))
	width = int(source.get("width", width))
	height = int(source.get("height", height))
	profile_id = String(source.get("profile_id", profile_id))
	entry_count = clampi(int(source.get("entry_count", entry_count)), GameConfigData.MIN_ENTRY_COUNT, GameConfigData.MAX_ENTRY_COUNT)
	min_center_area = int(source.get("min_center_area", max(160, requested_center_area - 60)))
	max_center_area = int(source.get("max_center_area", requested_center_area + 60))
	min_center_area = max(64, min_center_area)
	max_center_area = max(min_center_area, max_center_area)
	water_chance = clampf(float(source.get("water_chance", water_chance)), 0.0, 1.0)
	min_water_area = int(source.get("min_water_area", min_water_area))
	max_water_area = int(source.get("max_water_area", max_water_area))
	blocker_count = int(source.get("blocker_count", blocker_count))
	min_blocker_area = int(source.get("min_blocker_area", min_blocker_area))
	max_blocker_area = int(source.get("max_blocker_area", max_blocker_area))
	min_water_area = max(24, min_water_area)
	max_water_area = max(min_water_area, max_water_area)
	min_blocker_area = max(36, min_blocker_area)
	max_blocker_area = max(min_blocker_area, max_blocker_area)
	road_curvature = float(source.get("road_curvature", road_curvature))
	min_blocker_distance_from_center = int(source.get("min_blocker_distance_from_center", min_blocker_distance_from_center))
	approach_padding = int(source.get("approach_padding", approach_padding))
	minimum_path_width = int(source.get("minimum_path_width", minimum_path_width))
