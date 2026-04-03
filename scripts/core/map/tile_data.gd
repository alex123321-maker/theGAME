extends RefCounted

var x: int = 0
var y: int = 0
var terrain_type: int = MapTypes.TerrainType.GROUND
var base_terrain_type: int = MapTypes.TerrainType.GROUND
var height_class: int = MapTypes.HeightClass.MID
var region_id: int = 0
var region_type: int = MapTypes.RegionType.NONE
var blocker_type: int = MapTypes.BlockerType.NONE
var road_width_class: int = MapTypes.RoadWidthClass.NONE
var road_width_cells: int = 0
var transition_type: int = MapTypes.TransitionType.NONE
var walk_cost: float = 1.0
var is_walkable: bool = true
var is_buildable: bool = false
var is_road: bool = false
var is_water: bool = false
var is_blocked: bool = false
var is_future_wallable: bool = false
var resource_tag: int = MapTypes.ResourceTag.NONE
var threat_value: float = 0.0
var poi_tag: int = MapTypes.PoiTag.NONE
var transition_flags: Dictionary = {}
var debug_tags: Array = []

func _init(tile_x: int = 0, tile_y: int = 0) -> void:
	x = tile_x
	y = tile_y

func to_dict() -> Dictionary:
	return {
		"x": x,
		"y": y,
		"terrain_type": terrain_type,
		"base_terrain_type": base_terrain_type,
		"height_class": height_class,
		"region_id": region_id,
		"region_type": region_type,
		"blocker_type": blocker_type,
		"road_width_class": road_width_class,
		"road_width_cells": road_width_cells,
		"transition_type": transition_type,
		"walk_cost": walk_cost,
		"is_walkable": is_walkable,
		"is_buildable": is_buildable,
		"is_road": is_road,
		"is_water": is_water,
		"is_blocked": is_blocked,
		"is_future_wallable": is_future_wallable,
		"resource_tag": resource_tag,
		"threat_value": threat_value,
		"poi_tag": poi_tag,
		"transition_flags": transition_flags.duplicate(true),
		"debug_tags": debug_tags.duplicate(),
	}

static func from_dict(source: Dictionary):
	var tile = preload("res://scripts/core/map/tile_data.gd").new(
		int(source.get("x", 0)),
		int(source.get("y", 0))
	)

	tile.terrain_type = int(source.get("terrain_type", MapTypes.TerrainType.GROUND))
	tile.base_terrain_type = int(source.get("base_terrain_type", tile.terrain_type))
	tile.height_class = int(source.get("height_class", MapTypes.HeightClass.MID))
	tile.region_id = int(source.get("region_id", 0))
	tile.region_type = int(source.get("region_type", MapTypes.RegionType.NONE))
	tile.blocker_type = int(source.get("blocker_type", MapTypes.BlockerType.NONE))
	tile.road_width_class = int(source.get("road_width_class", MapTypes.RoadWidthClass.NONE))
	tile.road_width_cells = int(source.get("road_width_cells", 0))
	tile.transition_type = int(source.get("transition_type", MapTypes.TransitionType.NONE))
	tile.walk_cost = float(source.get("walk_cost", 1.0))
	tile.is_walkable = bool(source.get("is_walkable", true))
	tile.is_buildable = bool(source.get("is_buildable", false))
	tile.is_road = bool(source.get("is_road", false))
	tile.is_water = bool(source.get("is_water", false))
	tile.is_blocked = bool(source.get("is_blocked", false))
	tile.is_future_wallable = bool(source.get("is_future_wallable", false))
	tile.resource_tag = int(source.get("resource_tag", MapTypes.ResourceTag.NONE))
	tile.threat_value = float(source.get("threat_value", 0.0))
	tile.poi_tag = int(source.get("poi_tag", MapTypes.PoiTag.NONE))
	tile.transition_flags = source.get("transition_flags", {}).duplicate(true)
	for tag in source.get("debug_tags", []):
		tile.debug_tags.append(String(tag))
	return tile
