extends RefCounted
class_name RoutesPass

const GameConfigData = preload("res://autoload/game_config.gd")

## Creates outer entries and carves orthogonal roads toward the village center.
func apply(map_data: MapData, rng: RandomNumberGenerator, config: Dictionary) -> void:
	var entry_count: int = clampi(
		int(config.get("entry_count", GameConfigData.DEFAULT_ENTRY_COUNT)),
		GameConfigData.MIN_ENTRY_COUNT,
		GameConfigData.MAX_ENTRY_COUNT
	)

	var center := _choose_village_target(map_data)
	var candidate_entries := _build_entry_candidates(map_data)

	for i in range(entry_count):
		var entry_index: int = i % candidate_entries.size()
		var entry_point: Vector2i = candidate_entries[entry_index]
		map_data.entry_points.append(entry_point)
		_mark_entry_tile(map_data, entry_point)
		var prefer_vertical_first: bool = _prefer_vertical_first(entry_index, rng)
		_carve_road_path(map_data, entry_point, center, prefer_vertical_first)

func _choose_village_target(map_data: MapData) -> Vector2i:
	if map_data.central_zone_tiles.is_empty():
		return Vector2i(map_data.width / 2, map_data.height / 2)

	var average := Vector2.ZERO
	for point in map_data.central_zone_tiles:
		average += Vector2(point.x, point.y)
	average /= float(map_data.central_zone_tiles.size())
	return Vector2i(roundi(average.x), roundi(average.y))

func _build_entry_candidates(map_data: MapData) -> Array[Vector2i]:
	var x_mid: int = map_data.width / 2
	var y_mid: int = map_data.height / 2

	return [
		Vector2i(x_mid, 0),
		Vector2i(map_data.width - 1, y_mid),
		Vector2i(x_mid, map_data.height - 1),
		Vector2i(0, y_mid),
	]

func _mark_entry_tile(map_data: MapData, entry_point: Vector2i) -> void:
	var tile = map_data.get_tile(entry_point.x, entry_point.y)
	if tile == null:
		return

	tile.terrain_type = MapTypes.TerrainType.ROAD
	tile.walk_cost = 1.0
	tile.poi_tag = MapTypes.PoiTag.ENTRY
	tile.threat_value = 1.0

func _carve_road_path(
	map_data: MapData,
	from_point: Vector2i,
	to_point: Vector2i,
	prefer_vertical_first: bool
) -> void:
	var bend_point := Vector2i(from_point.x, to_point.y) if prefer_vertical_first else Vector2i(to_point.x, from_point.y)
	_carve_axis_segment(map_data, from_point, bend_point)
	_carve_axis_segment(map_data, bend_point, to_point)

func _carve_axis_segment(map_data: MapData, from_point: Vector2i, to_point: Vector2i) -> void:
	var current := from_point
	_paint_road(map_data, current)

	while current.x != to_point.x:
		current.x += signi(to_point.x - current.x)
		_paint_road(map_data, current)

	while current.y != to_point.y:
		current.y += signi(to_point.y - current.y)
		_paint_road(map_data, current)

func _prefer_vertical_first(entry_index: int, rng: RandomNumberGenerator) -> bool:
	match entry_index:
		0, 2:
			return true
		1, 3:
			return false
		_:
			return rng.randf() < 0.5

func _paint_road(map_data: MapData, point: Vector2i) -> void:
	if not map_data.is_in_bounds(point.x, point.y):
		return

	var tile = map_data.get_tile(point.x, point.y)
	tile.terrain_type = MapTypes.TerrainType.ROAD
	tile.walk_cost = 0.8
	tile.threat_value = maxf(tile.threat_value, 0.75)

	if tile.poi_tag == MapTypes.PoiTag.NONE:
		tile.poi_tag = MapTypes.PoiTag.BOTTLENECK
