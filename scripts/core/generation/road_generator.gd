extends RefCounted
class_name RoadGenerator

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")
const INF_COST: float = 1_000_000.0

func generate(map_data: MapData, _rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	var center_points: Array[Vector2i] = map_data.central_zone_tiles
	if center_points.is_empty():
		return

	var road_index: int = 0
	for entry_spec in composition.get("entries", []):
		var entry_point: Vector2i = entry_spec.get("point", Vector2i.ZERO)
		_ensure_entry_tile(map_data, entry_point)
		map_data.entry_points.append(entry_point)
		var attach_point: Vector2i = _closest_center_point(center_points, entry_point)
		var spine_tiles: Array[Vector2i] = _find_path_with_fallback(map_data, entry_point, attach_point)
		if spine_tiles.is_empty():
			continue
		var road_report: Dictionary = _paint_road(map_data, spine_tiles, map_data.seed, road_index, config)
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
			"control_points": _serialize_vec2_array(_sample_control_points(spine_tiles)),
			"spine_tiles": _serialize_vec2i_array(spine_tiles),
			"tiles": _serialize_vec2i_array(painted_tiles),
		})
		road_index += 1

func _find_path_with_fallback(map_data: MapData, from_point: Vector2i, to_point: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = _a_star_path(map_data, from_point, to_point, false)
	if not path.is_empty():
		return path
	path = _a_star_path(map_data, from_point, to_point, true)
	if not path.is_empty():
		return path
	return _emergency_straight_path(map_data, from_point, to_point)

func _a_star_path(map_data: MapData, from_point: Vector2i, to_point: Vector2i, allow_soft_break: bool) -> Array[Vector2i]:
	var start: Vector2i = _nearest_traversable_point(map_data, from_point, allow_soft_break)
	var goal: Vector2i = _nearest_traversable_point(map_data, to_point, allow_soft_break)
	if start == Vector2i(-1, -1) or goal == Vector2i(-1, -1):
		return []

	var open: Array[Vector2i] = [start]
	var open_lookup := {start: true}
	var closed := {}
	var came_from := {}
	var g_score := {start: 0.0}
	var f_score := {start: _heuristic(start, goal)}
	while not open.is_empty():
		var current: Vector2i = _pop_lowest_f(open, f_score)
		open_lookup.erase(current)
		if current == goal:
			return _reconstruct_path(came_from, current)
		closed[current] = true
		for direction in GenerationUtilsClass.cardinal_neighbors(Vector2i.ZERO):
			var next: Vector2i = current + direction
			if not map_data.is_in_bounds(next.x, next.y):
				continue
			if closed.has(next):
				continue
			var tile = map_data.get_tile(next.x, next.y)
			var step_cost: float = _road_step_cost(tile, allow_soft_break)
			if step_cost >= INF_COST:
				continue
			var tentative: float = float(g_score[current]) + step_cost
			if (not g_score.has(next)) or tentative < float(g_score[next]):
				came_from[next] = current
				g_score[next] = tentative
				f_score[next] = tentative + _heuristic(next, goal)
				if not open_lookup.has(next):
					open.append(next)
					open_lookup[next] = true
	return []

func _road_step_cost(tile, allow_soft_break: bool) -> float:
	if tile == null:
		return INF_COST
	if tile.is_water or tile.base_terrain_type == MapTypes.TerrainType.WATER:
		return INF_COST
	if tile.is_blocked:
		if allow_soft_break and tile.blocker_type == MapTypes.BlockerType.FOREST:
			return 16.0
		return INF_COST
	if not tile.is_walkable:
		if allow_soft_break and tile.blocker_type == MapTypes.BlockerType.FOREST:
			return 12.0
		return INF_COST
	if tile.is_road:
		return 0.52
	if tile.base_terrain_type == MapTypes.TerrainType.CLEARING:
		return 0.85
	if tile.base_terrain_type == MapTypes.TerrainType.FOREST:
		return 2.6
	if tile.base_terrain_type == MapTypes.TerrainType.ROCK:
		return 5.8
	if tile.region_type == MapTypes.RegionType.APPROACH_CORRIDOR:
		return 0.96
	return 1.22

func _nearest_traversable_point(map_data: MapData, origin: Vector2i, allow_soft_break: bool) -> Vector2i:
	if _road_step_cost(map_data.get_tile(origin.x, origin.y), allow_soft_break) < INF_COST:
		return origin
	var frontier: Array[Vector2i] = [origin]
	var visited := {origin: true}
	var depth: int = 0
	while not frontier.is_empty() and depth < 10:
		var iteration: int = frontier.size()
		for _i in range(iteration):
			var current: Vector2i = frontier.pop_front()
			if _road_step_cost(map_data.get_tile(current.x, current.y), allow_soft_break) < INF_COST:
				return current
			for neighbor in GenerationUtilsClass.cardinal_neighbors(current):
				if visited.has(neighbor):
					continue
				if not map_data.is_in_bounds(neighbor.x, neighbor.y):
					continue
				visited[neighbor] = true
				frontier.append(neighbor)
		depth += 1
	return Vector2i(-1, -1)

func _pop_lowest_f(open: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var best_index: int = 0
	var best_point: Vector2i = open[0]
	var best_score: float = float(f_score.get(best_point, INF_COST))
	for i in range(1, open.size()):
		var candidate: Vector2i = open[i]
		var candidate_score: float = float(f_score.get(candidate, INF_COST))
		if candidate_score < best_score:
			best_score = candidate_score
			best_point = candidate
			best_index = i
	open.remove_at(best_index)
	return best_point

func _heuristic(from_point: Vector2i, to_point: Vector2i) -> float:
	return float(absi(from_point.x - to_point.x) + absi(from_point.y - to_point.y))

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	var cursor: Vector2i = current
	while came_from.has(cursor):
		cursor = came_from[cursor]
		path.push_front(cursor)
	return path

func _emergency_straight_path(map_data: MapData, from_point: Vector2i, to_point: Vector2i) -> Array[Vector2i]:
	var points: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([Vector2(from_point), Vector2(to_point)])
	var path: Array[Vector2i] = []
	for point in points:
		if not map_data.is_in_bounds(point.x, point.y):
			continue
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		if tile.is_water:
			continue
		if tile.is_blocked and tile.blocker_type != MapTypes.BlockerType.FOREST:
			continue
		if tile.is_blocked and tile.blocker_type == MapTypes.BlockerType.FOREST:
			tile.is_blocked = false
			tile.is_walkable = true
			tile.walk_cost = 6.0
			if not tile.debug_tags.has("emergency_corridor_clear"):
				tile.debug_tags.append("emergency_corridor_clear")
		path.append(point)
	return path

func _closest_center_point(points: Array[Vector2i], origin: Vector2i) -> Vector2i:
	var best_point: Vector2i = points[0]
	var best_distance: float = best_point.distance_to(origin)
	for point in points:
		var candidate_distance: float = point.distance_to(origin)
		if candidate_distance < best_distance:
			best_distance = candidate_distance
			best_point = point
	return best_point

func _paint_road(map_data: MapData, road_tiles: Array[Vector2i], seed: int, road_index: int, config) -> Dictionary:
	var painted := {}
	var width_profile: Array[int] = _build_width_profile(road_tiles, seed, road_index, config)
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
			if _mark_road_tile(
				map_data,
				target,
				width_cells,
				point_index == 0 and offsets[offset_index] == Vector2i.ZERO
			):
				painted[target] = true
	_fill_enclosed_road_gaps(map_data, painted)
	return {
		"painted_tiles": _dictionary_points(painted),
		"min_width_cells": min_width_cells if not road_tiles.is_empty() else 0,
		"max_width_cells": max_width_cells if not road_tiles.is_empty() else 0,
	}

func _build_width_profile(road_tiles: Array[Vector2i], seed: int, road_index: int, config) -> Array[int]:
	var widths: Array[int] = []
	widths.resize(road_tiles.size())
	if road_tiles.is_empty():
		return widths
	var min_width: int = clampi(config.minimum_path_width, 1, 3)
	var max_width: int = mini(3, min_width + 1)
	var current_width: int = min_width
	for i in range(road_tiles.size()):
		if i > 0 and (i % 5) == 0 and max_width > min_width:
			var target_width: int = min_width + (_road_hash(seed, road_index, int(i / 5)) % (max_width - min_width + 1))
			if target_width > current_width:
				current_width += 1
			elif target_width < current_width:
				current_width -= 1
		widths[i] = clampi(current_width, min_width, max_width)
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

func _mark_road_tile(map_data: MapData, point: Vector2i, width_cells: int, is_entry_tile: bool) -> bool:
	var tile = map_data.get_tile(point.x, point.y)
	if tile == null:
		return false
	if not _can_paint_road_tile(tile, is_entry_tile):
		return false
	var underlying_terrain: int = tile.base_terrain_type
	tile.terrain_type = MapTypes.TerrainType.ROAD
	tile.road_width_cells = maxi(tile.road_width_cells, width_cells)
	tile.road_width_class = maxi(tile.road_width_class, _road_width_class_from_cells(tile.road_width_cells))
	tile.is_road = true
	tile.is_walkable = true
	tile.is_buildable = false
	tile.is_water = false
	tile.is_blocked = false
	tile.walk_cost = _road_walk_cost(tile.road_width_cells)
	if is_entry_tile:
		tile.poi_tag = MapTypes.PoiTag.ENTRY
	if not tile.debug_tags.has("road"):
		tile.debug_tags.append("road")
	if underlying_terrain == MapTypes.TerrainType.FOREST and not tile.debug_tags.has("road_through_forest_fringe"):
		tile.debug_tags.append("road_through_forest_fringe")
	if underlying_terrain == MapTypes.TerrainType.ROCK and not tile.debug_tags.has("road_through_rock_edge"):
		tile.debug_tags.append("road_through_rock_edge")
	return true

func _can_paint_road_tile(tile, is_entry_tile: bool) -> bool:
	if tile == null:
		return false
	if tile.is_water or tile.base_terrain_type == MapTypes.TerrainType.WATER:
		return false
	if tile.is_blocked and not is_entry_tile:
		return false
	if not tile.is_walkable and not is_entry_tile:
		return false
	return true

func _fill_enclosed_road_gaps(map_data: MapData, painted: Dictionary) -> void:
	if painted.is_empty():
		return
	var min_x: int = map_data.width
	var min_y: int = map_data.height
	var max_x: int = 0
	var max_y: int = 0
	for point in painted.keys():
		var point_i: Vector2i = point
		min_x = mini(min_x, point_i.x)
		min_y = mini(min_y, point_i.y)
		max_x = maxi(max_x, point_i.x)
		max_y = maxi(max_y, point_i.y)
	for y in range(maxi(min_y - 1, 0), mini(max_y + 2, map_data.height)):
		for x in range(maxi(min_x - 1, 0), mini(max_x + 2, map_data.width)):
			var point := Vector2i(x, y)
			var tile = map_data.get_tile(x, y)
			if tile == null or tile.is_road:
				continue
			var road_neighbors: Array = _road_neighbor_tiles(map_data, point)
			if road_neighbors.size() < 4:
				continue
			if not _can_paint_road_tile(tile, false):
				continue
			var inferred_width: int = 1
			for neighbor in road_neighbors:
				inferred_width = maxi(inferred_width, int(neighbor.road_width_cells))
			if _mark_road_tile(map_data, point, inferred_width, false):
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

func _ensure_entry_tile(map_data: MapData, entry_point: Vector2i) -> void:
	if not map_data.is_in_bounds(entry_point.x, entry_point.y):
		return
	var tile = map_data.get_tile(entry_point.x, entry_point.y)
	if tile == null:
		return
	if tile.is_water or tile.base_terrain_type == MapTypes.TerrainType.WATER:
		tile.base_terrain_type = MapTypes.TerrainType.GROUND
		tile.terrain_type = MapTypes.TerrainType.GROUND
		tile.is_water = false
	if tile.is_blocked:
		tile.is_blocked = false
		tile.is_walkable = true
		tile.walk_cost = 1.4
		if not tile.debug_tags.has("entry_clearance"):
			tile.debug_tags.append("entry_clearance")
	if not tile.is_walkable:
		tile.is_walkable = true
		tile.walk_cost = 1.2
	tile.poi_tag = MapTypes.PoiTag.ENTRY
	if not tile.debug_tags.has("entry_anchor"):
		tile.debug_tags.append("entry_anchor")

func _sample_control_points(spine_tiles: Array[Vector2i]) -> Array[Vector2]:
	var controls: Array[Vector2] = []
	if spine_tiles.size() < 4:
		return controls
	var first_index: int = int(floor(float(spine_tiles.size() - 1) * 0.33))
	var second_index: int = int(floor(float(spine_tiles.size() - 1) * 0.66))
	controls.append(Vector2(spine_tiles[first_index]))
	controls.append(Vector2(spine_tiles[second_index]))
	return controls

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
	for key in points.keys():
		var point: Vector2i = key
		payload.append(point)
	return payload
