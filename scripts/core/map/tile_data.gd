extends RefCounted

var x: int = 0
var y: int = 0
var terrain_type: int = MapTypes.TerrainType.GROUND
var height_class: int = MapTypes.HeightClass.MID
var walk_cost: float = 1.0
var is_buildable: bool = false
var is_future_wallable: bool = false
var resource_tag: int = MapTypes.ResourceTag.NONE
var threat_value: float = 0.0
var poi_tag: int = MapTypes.PoiTag.NONE

func _init(tile_x: int = 0, tile_y: int = 0) -> void:
	x = tile_x
	y = tile_y

func to_dict() -> Dictionary:
	return {
		"x": x,
		"y": y,
		"terrain_type": terrain_type,
		"height_class": height_class,
		"walk_cost": walk_cost,
		"is_buildable": is_buildable,
		"is_future_wallable": is_future_wallable,
		"resource_tag": resource_tag,
		"threat_value": threat_value,
		"poi_tag": poi_tag,
	}

static func from_dict(source: Dictionary):
	var tile = preload("res://scripts/core/map/tile_data.gd").new(
		int(source.get("x", 0)),
		int(source.get("y", 0))
	)

	tile.terrain_type = int(source.get("terrain_type", MapTypes.TerrainType.GROUND))
	tile.height_class = int(source.get("height_class", MapTypes.HeightClass.MID))
	tile.walk_cost = float(source.get("walk_cost", 1.0))
	tile.is_buildable = bool(source.get("is_buildable", false))
	tile.is_future_wallable = bool(source.get("is_future_wallable", false))
	tile.resource_tag = int(source.get("resource_tag", MapTypes.ResourceTag.NONE))
	tile.threat_value = float(source.get("threat_value", 0.0))
	tile.poi_tag = int(source.get("poi_tag", MapTypes.PoiTag.NONE))
	return tile
