extends RefCounted
class_name MapData

const TileDataClass = preload("res://scripts/core/map/tile_data.gd")

var width: int = 0
var height: int = 0
var seed: int = 0
var generator_version: int = 0
var profile_id: String = "default"
var composition_template_id: String = "unknown"
var terrain_layer: Array[int] = []
var height_layer: Array[int] = []
var region_layer: Array[int] = []
var road_mask: Array[bool] = []
var water_mask: Array[bool] = []
var blocker_mask: Array[bool] = []
var buildable_mask: Array[bool] = []
var village_center_mask: Array[bool] = []
var transition_layer: Array[Dictionary] = []

var tiles: Array = []
var entry_points: Array[Vector2i] = []
var central_zone_tiles: Array[Vector2i] = []
var roads: Array[Dictionary] = []
var regions: Array[Dictionary] = []
var generation_summary: Dictionary = {}
var validation_report: Dictionary = {}

func _init(new_width: int = 0, new_height: int = 0) -> void:
	width = new_width
	height = new_height
	_resize_layers()

	if width > 0 and height > 0:
		tiles.resize(width * height)
		for y in range(height):
			for x in range(width):
				set_tile(x, y, TileDataClass.new(x, y))

func index_of(x: int, y: int) -> int:
	return y * width + x

func is_in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < width and y < height

func get_tile(x: int, y: int):
	if not is_in_bounds(x, y):
		return null

	return tiles[index_of(x, y)]

func set_tile(x: int, y: int, tile) -> void:
	if not is_in_bounds(x, y):
		return

	tiles[index_of(x, y)] = tile
	_write_tile_to_layers(tile)

func set_tile_flags(point: Vector2i, values: Dictionary) -> void:
	if not is_in_bounds(point.x, point.y):
		return
	var tile = get_tile(point.x, point.y)
	if tile == null:
		return
	for key in values.keys():
		tile.set(key, values[key])
	_write_tile_to_layers(tile)

func for_each_tile(callback: Callable) -> void:
	for tile in tiles:
		callback.call(tile)

func clear_runtime_collections() -> void:
	entry_points.clear()
	central_zone_tiles.clear()
	roads.clear()
	regions.clear()
	generation_summary = {}
	validation_report = {}
	composition_template_id = "unknown"

func register_region(region_id: int, region_type: int, label: String, metadata: Dictionary = {}) -> void:
	for index in range(regions.size()):
		if int(regions[index].get("id", -1)) != region_id:
			continue
		regions[index] = {
			"id": region_id,
			"type": region_type,
			"type_name": MapTypes.region_name(region_type),
			"label": label,
			"metadata": metadata.duplicate(true),
		}
		return
	regions.append({
		"id": region_id,
		"type": region_type,
		"type_name": MapTypes.region_name(region_type),
		"label": label,
		"metadata": metadata.duplicate(true),
	})

func rebuild_layers_from_tiles() -> void:
	_resize_layers()
	for tile in tiles:
		_write_tile_to_layers(tile)
	for point in central_zone_tiles:
		if is_in_bounds(point.x, point.y):
			village_center_mask[index_of(point.x, point.y)] = true

func point_mask_from_array(points: Array[Vector2i]) -> Array[bool]:
	var mask: Array[bool] = []
	mask.resize(width * height)
	mask.fill(false)
	for point in points:
		if is_in_bounds(point.x, point.y):
			mask[index_of(point.x, point.y)] = true
	return mask

func get_mask_value(mask: Array[bool], x: int, y: int) -> bool:
	if not is_in_bounds(x, y):
		return false
	return bool(mask[index_of(x, y)])

func to_dict() -> Dictionary:
	var tiles_payload: Array[Dictionary] = []
	tiles_payload.resize(tiles.size())

	for i in range(tiles.size()):
		tiles_payload[i] = tiles[i].to_dict()

	var entry_payload: Array[Dictionary] = []
	for point in entry_points:
		entry_payload.append({
			"x": point.x,
			"y": point.y,
		})

	var central_payload: Array[Dictionary] = []
	for point in central_zone_tiles:
		central_payload.append({
			"x": point.x,
			"y": point.y,
		})

	var road_payload: Array[Dictionary] = []
	for road in roads:
		road_payload.append(road.duplicate(true))

	var layer_payload := {
		"terrain_layer": terrain_layer.duplicate(),
		"height_layer": height_layer.duplicate(),
		"region_layer": region_layer.duplicate(),
		"road_mask": road_mask.duplicate(),
		"water_mask": water_mask.duplicate(),
		"blocker_mask": blocker_mask.duplicate(),
		"buildable_mask": buildable_mask.duplicate(),
		"village_center_mask": village_center_mask.duplicate(),
		"transition_layer": transition_layer.duplicate(true),
	}

	return {
		"width": width,
		"height": height,
		"seed": seed,
		"generator_version": generator_version,
		"profile_id": profile_id,
		"composition_template_id": composition_template_id,
		"entry_points": entry_payload,
		"central_zone_tiles": central_payload,
		"roads": road_payload,
		"regions": regions.duplicate(true),
		"generation_summary": generation_summary.duplicate(true),
		"layers": layer_payload,
		"validation_report": validation_report,
		"tiles": tiles_payload,
	}

static func from_dict(source: Dictionary) -> MapData:
	var map_data := MapData.new(
		int(source.get("width", 0)),
		int(source.get("height", 0))
	)

	map_data.seed = int(source.get("seed", 0))
	map_data.generator_version = int(source.get("generator_version", 0))
	map_data.profile_id = String(source.get("profile_id", "default"))
	map_data.composition_template_id = String(source.get("composition_template_id", "unknown"))
	map_data.generation_summary = source.get("generation_summary", {}).duplicate(true)
	map_data.validation_report = source.get("validation_report", {})

	map_data.entry_points.clear()
	for point in source.get("entry_points", []):
		map_data.entry_points.append(Vector2i(int(point.get("x", 0)), int(point.get("y", 0))))

	map_data.central_zone_tiles.clear()
	for point in source.get("central_zone_tiles", []):
		map_data.central_zone_tiles.append(Vector2i(int(point.get("x", 0)), int(point.get("y", 0))))

	map_data.roads.clear()
	for road in source.get("roads", []):
		map_data.roads.append(road.duplicate(true))

	map_data.regions.clear()
	for region in source.get("regions", []):
		map_data.regions.append(region.duplicate(true))

	var source_tiles: Array = source.get("tiles", [])
	for i in range(min(source_tiles.size(), map_data.tiles.size())):
		map_data.tiles[i] = TileDataClass.from_dict(source_tiles[i])

	var layers: Dictionary = source.get("layers", {})
	map_data.terrain_layer = layers.get("terrain_layer", map_data.terrain_layer)
	map_data.height_layer = layers.get("height_layer", map_data.height_layer)
	map_data.region_layer = layers.get("region_layer", map_data.region_layer)
	map_data.road_mask = layers.get("road_mask", map_data.road_mask)
	map_data.water_mask = layers.get("water_mask", map_data.water_mask)
	map_data.blocker_mask = layers.get("blocker_mask", map_data.blocker_mask)
	map_data.buildable_mask = layers.get("buildable_mask", map_data.buildable_mask)
	map_data.village_center_mask = layers.get("village_center_mask", map_data.village_center_mask)
	map_data.transition_layer = layers.get("transition_layer", map_data.transition_layer)
	map_data.rebuild_layers_from_tiles()

	return map_data

func _resize_layers() -> void:
	var tile_count: int = max(0, width * height)
	terrain_layer.resize(tile_count)
	height_layer.resize(tile_count)
	region_layer.resize(tile_count)
	road_mask.resize(tile_count)
	water_mask.resize(tile_count)
	blocker_mask.resize(tile_count)
	buildable_mask.resize(tile_count)
	village_center_mask.resize(tile_count)
	transition_layer.resize(tile_count)
	for i in range(tile_count):
		terrain_layer[i] = MapTypes.TerrainType.GROUND
		height_layer[i] = MapTypes.HeightClass.MID
		region_layer[i] = 0
		road_mask[i] = false
		water_mask[i] = false
		blocker_mask[i] = false
		buildable_mask[i] = false
		village_center_mask[i] = false
		transition_layer[i] = {}

func _write_tile_to_layers(tile) -> void:
	if tile == null or not is_in_bounds(tile.x, tile.y):
		return
	var index: int = index_of(tile.x, tile.y)
	terrain_layer[index] = int(tile.base_terrain_type)
	height_layer[index] = int(tile.height_class)
	region_layer[index] = int(tile.region_id)
	road_mask[index] = bool(tile.is_road)
	water_mask[index] = bool(tile.is_water)
	blocker_mask[index] = bool(tile.is_blocked)
	buildable_mask[index] = bool(tile.is_buildable)
	transition_layer[index] = {
		"type": int(tile.transition_type),
		"type_name": MapTypes.transition_name(tile.transition_type),
		"flags": tile.transition_flags.duplicate(true),
	}
