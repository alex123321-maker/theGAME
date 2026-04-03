extends RefCounted
class_name RoadGenerator

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")

func generate(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	var center_points: Array[Vector2i] = map_data.central_zone_tiles
	if center_points.is_empty():
		return
	var center: Vector2 = Vector2.ZERO
	for point in center_points:
		center += Vector2(point)
	center /= float(center_points.size())

	var road_index: int = 0
	for entry_spec in composition.get("entries", []):
		var entry_point: Vector2i = entry_spec.get("point", Vector2i.ZERO)
		map_data.entry_points.append(entry_point)
		var attach_point: Vector2i = _closest_center_point(center_points, entry_point)
		var control_points: Array[Vector2] = _build_control_points(entry_point, attach_point, center, rng, config, road_index)
		var polyline: Array[Vector2] = [Vector2(entry_point)]
		for control in control_points:
			polyline.append(control)
		polyline.append(Vector2(attach_point))
		var spine_tiles: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline(polyline)
		var road_report: Dictionary = _paint_road(map_data, spine_tiles, map_data.seed, road_index)
		var max_width_cells: int = int(road_report.get("max_width_cells", 1))
		var painted_tiles: Array[Vector2i] = road_report.get("painted_tiles", [])
		var width_class: int = _road_width_class_from_cells(max_width_cells)
		map_data.roads.append({
			"entry_point": {"x": entry_point.x, "y": entry_point.y},
			"attach_point": {"x": attach_point.x, "y": attach_point.y},
			"width_class": width_class,
			"width_name": MapTypes.road_width_name(width_class),
			"min_width_cells": int(road_report.get("min_width_cells", 1)),
			"max_width_cells": max_width_cells,
			"control_points": _serialize_vec2_array(control_points),
			"spine_tiles": _serialize_vec2i_array(spine_tiles),
			"tiles": _serialize_vec2i_array(painted_tiles),
		})
		road_index += 1

func _build_control_points(entry_point: Vector2i, attach_point: Vector2i, center: Vector2, rng: RandomNumberGenerator, config, road_index: int) -> Array[Vector2]:
	var delta: Vector2 = Vector2(attach_point - entry_point)
	var normal: Vector2 = Vector2(-delta.y, delta.x).normalized()
	var path_length: float = maxf(delta.length(), 1.0)
	var bend_strength: float = path_length * clampf(config.road_curvature, 0.04, 0.22)
	var control_a: Vector2 = Vector2(entry_point).lerp(center, 0.34)
	var control_b: Vector2 = Vector2(entry_point).lerp(center, 0.68)
	var sign_a: float = -1.0 if (road_index % 2) == 0 else 1.0
	var sign_b: float = 1.0 if rng.randf() < 0.5 else -1.0
	control_a += normal * bend_strength * sign_a * rng.randf_range(0.45, 0.95)
	control_b += normal * bend_strength * sign_b * rng.randf_range(0.20, 0.70)
	return [control_a, control_b]

func _closest_center_point(points: Array[Vector2i], origin: Vector2i) -> Vector2i:
	var best_point: Vector2i = points[0]
	var best_distance: float = best_point.distance_to(origin)
	for point in points:
		var candidate_distance: float = point.distance_to(origin)
		if candidate_distance < best_distance:
			best_distance = candidate_distance
			best_point = point
	return best_point

func _paint_road(map_data: MapData, road_tiles: Array[Vector2i], seed: int, road_index: int) -> Dictionary:
	var painted := {}
	var width_profile: Array[int] = _build_width_profile(road_tiles, seed, road_index)
	var min_width_cells: int = 3
	var max_width_cells: int = 1
	for point_index in range(road_tiles.size()):
		var point: Vector2i = road_tiles[point_index]
		var width_cells: int = width_profile[point_index]
		min_width_cells = mini(min_width_cells, width_cells)
		max_width_cells = maxi(max_width_cells, width_cells)
		var offsets: Array[Vector2i] = _road_offsets(road_tiles, point_index, width_cells, seed, road_index)
		for offset_index in range(offsets.size()):
			var target: Vector2i = point + offsets[offset_index]
			if not map_data.is_in_bounds(target.x, target.y):
				continue
			_mark_road_tile(
				map_data,
				target,
				width_cells,
				point_index == 0 and offsets[offset_index] == Vector2i.ZERO
			)
			painted[target] = true
	_fill_enclosed_road_gaps(map_data, painted)
	return {
		"painted_tiles": _dictionary_points(painted),
		"min_width_cells": min_width_cells if not road_tiles.is_empty() else 0,
		"max_width_cells": max_width_cells if not road_tiles.is_empty() else 0,
	}

func _build_width_profile(road_tiles: Array[Vector2i], seed: int, road_index: int) -> Array[int]:
	var widths: Array[int] = []
	widths.resize(road_tiles.size())
	if road_tiles.is_empty():
		return widths
	var current_width: int = 1 + (_road_hash(seed, road_index, 0) % 3)
	for i in range(road_tiles.size()):
		if i > 0 and (i % 4) == 0:
			var target_width: int = 1 + (_road_hash(seed, road_index, int(i / 4)) % 3)
			if target_width > current_width:
				current_width += 1
			elif target_width < current_width:
				current_width -= 1
		widths[i] = clampi(current_width, 1, 3)
	return widths

func _road_offsets(road_tiles: Array[Vector2i], point_index: int, width_cells: int, seed: int, road_index: int) -> Array[Vector2i]:
	var tangent: Vector2i = _road_tangent(road_tiles, point_index)
	var normal: Vector2i = _road_normal(tangent)
	var bias: int = -1 if (_road_hash(seed, road_index, point_index) % 2) == 0 else 1
	var scalars: Array[int] = [0]
	match width_cells:
		2:
			scalars.append(bias)
		3:
			scalars = [-1, 0, 1]
	var offsets: Array[Vector2i] = []
	for scalar in scalars:
		offsets.append(normal * scalar)
	return offsets

func _road_tangent(road_tiles: Array[Vector2i], point_index: int) -> Vector2i:
	if road_tiles.is_empty():
		return Vector2i.RIGHT
	var current: Vector2i = road_tiles[point_index]
	var previous: Vector2i = road_tiles[maxi(point_index - 1, 0)]
	var next: Vector2i = road_tiles[mini(point_index + 1, road_tiles.size() - 1)]
	var tangent: Vector2i = next - previous
	if tangent == Vector2i.ZERO:
		tangent = current - previous
	if tangent == Vector2i.ZERO:
		tangent = next - current
	return tangent

func _road_normal(tangent: Vector2i) -> Vector2i:
	if absi(tangent.x) > absi(tangent.y):
		return Vector2i.UP
	if absi(tangent.y) > absi(tangent.x):
		return Vector2i.RIGHT
	var dx: int = _sign_int(tangent.x)
	var dy: int = _sign_int(tangent.y)
	if dx == 0 and dy == 0:
		return Vector2i.UP
	return Vector2i(-dy, dx)

func _mark_road_tile(map_data: MapData, point: Vector2i, width_cells: int, is_entry_tile: bool) -> void:
	var tile = map_data.get_tile(point.x, point.y)
	if tile == null:
		return
	var underlying_terrain: int = tile.base_terrain_type
	var crosses_water: bool = tile.is_water or underlying_terrain == MapTypes.TerrainType.WATER
	var crosses_blocker: bool = tile.is_blocked \
		or underlying_terrain == MapTypes.TerrainType.BLOCKER \
		or tile.blocker_type != MapTypes.BlockerType.NONE
	tile.terrain_type = MapTypes.TerrainType.ROAD
	tile.road_width_cells = maxi(tile.road_width_cells, width_cells)
	tile.road_width_class = maxi(tile.road_width_class, _road_width_class_from_cells(tile.road_width_cells))
	tile.is_road = true
	tile.is_walkable = true
	tile.is_buildable = false
	tile.is_water = crosses_water
	tile.is_blocked = false
	tile.walk_cost = _road_walk_cost(tile.road_width_cells)
	if is_entry_tile:
		tile.poi_tag = MapTypes.PoiTag.ENTRY
	if not tile.debug_tags.has("road"):
		tile.debug_tags.append("road")
	if crosses_water and not tile.debug_tags.has("road_over_water"):
		tile.debug_tags.append("road_over_water")
	if crosses_blocker and not tile.debug_tags.has("road_over_blocker"):
		tile.debug_tags.append("road_over_blocker")

func _fill_enclosed_road_gaps(map_data: MapData, painted: Dictionary) -> void:
	if painted.is_empty():
		return
	var min_x: int = map_data.width
	var min_y: int = map_data.height
	var max_x: int = 0
	var max_y: int = 0
	for point in painted.keys():
		min_x = mini(min_x, point.x)
		min_y = mini(min_y, point.y)
		max_x = maxi(max_x, point.x)
		max_y = maxi(max_y, point.y)
	for y in range(maxi(min_y - 1, 0), mini(max_y + 2, map_data.height)):
		for x in range(maxi(min_x - 1, 0), mini(max_x + 2, map_data.width)):
			var point := Vector2i(x, y)
			var tile = map_data.get_tile(x, y)
			if tile == null or tile.is_road:
				continue
			var road_neighbors: Array = _road_neighbor_tiles(map_data, point)
			if road_neighbors.size() < 4:
				continue
			var inferred_width: int = 1
			for neighbor in road_neighbors:
				inferred_width = maxi(inferred_width, int(neighbor.road_width_cells))
			_mark_road_tile(map_data, point, inferred_width, false)
			if not tile.debug_tags.has("road_gap_fill"):
				tile.debug_tags.append("road_gap_fill")
			painted[point] = true

func _road_neighbor_tiles(map_data: MapData, point: Vector2i) -> Array:
	var neighbors: Array = []
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var target: Vector2i = point + direction
		if not map_data.is_in_bounds(target.x, target.y):
			return []
		var tile = map_data.get_tile(target.x, target.y)
		if tile == null or not tile.is_road:
			return []
		neighbors.append(tile)
	return neighbors

func _road_width_class_from_cells(width_cells: int) -> int:
	return MapTypes.RoadWidthClass.MEDIUM if width_cells >= 2 else MapTypes.RoadWidthClass.NARROW

func _road_walk_cost(width_cells: int) -> float:
	match width_cells:
		3:
			return 0.68
		2:
			return 0.75
		_:
			return 0.84

func _road_hash(seed: int, road_index: int, sample_index: int) -> int:
	return absi(int((seed * 92821) ^ (road_index * 68917) ^ (sample_index * 28387) ^ 177))

func _sign_int(value: int) -> int:
	if value < 0:
		return -1
	if value > 0:
		return 1
	return 0

func _serialize_vec2_array(points: Array[Vector2]) -> Array[Dictionary]:
	var payload: Array[Dictionary] = []
	for point in points:
		payload.append({"x": point.x, "y": point.y})
	return payload

func _serialize_vec2i_array(points: Array[Vector2i]) -> Array[Dictionary]:
	var payload: Array[Dictionary] = []
	for point in points:
		payload.append({"x": point.x, "y": point.y})
	return payload

func _dictionary_points(points: Dictionary) -> Array[Vector2i]:
	var payload: Array[Vector2i] = []
	for point in points.keys():
		payload.append(point)
	return payload
