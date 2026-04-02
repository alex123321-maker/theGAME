extends RefCounted
class_name MapData

const TileDataClass = preload("res://scripts/core/map/tile_data.gd")

var width: int = 0
var height: int = 0
var seed: int = 0
var generator_version: int = 0
var profile_id: String = "default"

var tiles: Array = []
var entry_points: Array[Vector2i] = []
var central_zone_tiles: Array[Vector2i] = []
var validation_report: Dictionary = {}

func _init(new_width: int = 0, new_height: int = 0) -> void:
	width = new_width
	height = new_height

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

func for_each_tile(callback: Callable) -> void:
	for tile in tiles:
		callback.call(tile)

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

	return {
		"width": width,
		"height": height,
		"seed": seed,
		"generator_version": generator_version,
		"profile_id": profile_id,
		"entry_points": entry_payload,
		"central_zone_tiles": central_payload,
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
	map_data.validation_report = source.get("validation_report", {})

	map_data.entry_points.clear()
	for point in source.get("entry_points", []):
		map_data.entry_points.append(Vector2i(int(point.get("x", 0)), int(point.get("y", 0))))

	map_data.central_zone_tiles.clear()
	for point in source.get("central_zone_tiles", []):
		map_data.central_zone_tiles.append(Vector2i(int(point.get("x", 0)), int(point.get("y", 0))))

	var source_tiles: Array = source.get("tiles", [])
	for i in range(min(source_tiles.size(), map_data.tiles.size())):
		map_data.tiles[i] = TileDataClass.from_dict(source_tiles[i])

	return map_data
