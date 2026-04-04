extends RefCounted
class_name RoadGenerator

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")
const INF_COST: float = 1_000_000.0
const BRIDGE_MAX_WATER_SPAN: int = 6
const BRIDGE_BASE_PENALTY: float = 8.0
const BRIDGE_DETOUR_TRIGGER: float = 1.28
const MAX_SCENIC_OVERSHOOT_RATIO: float = 1.34
const BRIDGE_EVAL_DETOUR_RATIO: float = 1.18

func generate(map_data: MapData, _rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	var center_points: Array[Vector2i] = map_data.central_zone_tiles
	if center_points.is_empty():
		return

	var pending_entries: Array = composition.get("entries", []).duplicate(true)
	var road_index: int = 0
	var max_passes: int = maxi(2, pending_entries.size())
	var pass_index: int = 0
	while not pending_entries.is_empty() and pass_index < max_passes:
		var progress_made: bool = false
		var next_pending: Array = []
		for entry_spec in pending_entries:
			var entry_point: Vector2i = entry_spec.get("point", Vector2i.ZERO)
			_ensure_entry_tile(map_data, entry_point)
			if not map_data.entry_points.has(entry_point):
				map_data.entry_points.append(entry_point)
			var attach_point: Vector2i = _select_attach_point(center_points, entry_point, map_data, composition)
			var spine_tiles: Array[Vector2i] = _plan_entry_route(map_data, entry_point, attach_point, _rng, config)
			if spine_tiles.is_empty():
				next_pending.append(entry_spec)
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
			progress_made = true
		if not progress_made:
			break
		pending_entries = next_pending
		pass_index += 1

func _find_path_with_fallback(
	map_data: MapData,
	from_point: Vector2i,
	to_point: Vector2i,
	allow_bridge_eval: bool = true
) -> Array[Vector2i]:
	var dry_path: Array[Vector2i] = _a_star_path(map_data, from_point, to_point, false)
	if not allow_bridge_eval:
		if not dry_path.is_empty():
			return dry_path
		var soft_path: Array[Vector2i] = _a_star_path(map_data, from_point, to_point, true)
		if not soft_path.is_empty():
			return soft_path
		return _emergency_straight_path(map_data, from_point, to_point)

	if not dry_path.is_empty():
		var manhattan: float = _heuristic(from_point, to_point)
		var dry_detour_ratio: float = float(dry_path.size()) / maxf(1.0, manhattan)
		if dry_detour_ratio <= BRIDGE_EVAL_DETOUR_RATIO:
			return dry_path

	var bridge_path: Array[Vector2i] = _path_via_bridge(map_data, from_point, to_point)
	if not dry_path.is_empty() and not bridge_path.is_empty():
		var dry_score: float = _route_physical_score(map_data, dry_path)
		var bridge_score: float = _route_physical_score(map_data, bridge_path)
		var dry_length: float = float(dry_path.size())
		var bridge_length: float = float(bridge_path.size())
		var detour_ratio: float = dry_length / maxf(1.0, bridge_length)
		if bridge_score <= dry_score or detour_ratio >= BRIDGE_DETOUR_TRIGGER:
			return bridge_path
		return dry_path
	if not bridge_path.is_empty():
		return bridge_path
	if not dry_path.is_empty():
		return dry_path
	var path: Array[Vector2i] = _a_star_path(map_data, from_point, to_point, true)
	if not path.is_empty():
		return path
	return _emergency_straight_path(map_data, from_point, to_point)

func _plan_entry_route(
	map_data: MapData,
	entry_point: Vector2i,
	attach_point: Vector2i,
	rng: RandomNumberGenerator,
	config
) -> Array[Vector2i]:
	var candidates: Array = []
	var direct_path: Array[Vector2i] = _find_path_with_fallback(map_data, entry_point, attach_point)
	if not direct_path.is_empty():
		candidates.append(direct_path)
	var curvature_strength: float = clampf(float(config.road_curvature), 0.0, 0.45)
	if curvature_strength <= 0.01:
		return direct_path
	for waypoint in _route_waypoint_candidates(map_data, entry_point, attach_point, curvature_strength, rng):
		var scenic_path: Array[Vector2i] = _find_path_via_waypoint(map_data, entry_point, attach_point, waypoint)
		if scenic_path.is_empty():
			continue
		candidates.append(scenic_path)
	if candidates.is_empty():
		return []
	var best_path: Array[Vector2i] = _best_route_candidate(candidates, entry_point, attach_point, curvature_strength)
	if not direct_path.is_empty() and not best_path.is_empty():
		var scenic_ratio: float = float(best_path.size()) / maxf(1.0, float(direct_path.size()))
		if scenic_ratio > MAX_SCENIC_OVERSHOOT_RATIO:
			return direct_path
	return best_path

func _route_physical_score(map_data: MapData, path: Array[Vector2i]) -> float:
	if path.is_empty():
		return INF_COST
	var bridge_span: int = 0
	for point in path:
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		if tile.is_water or tile.base_terrain_type == MapTypes.TerrainType.WATER:
			bridge_span += 1
	return float(path.size()) + (float(bridge_span) * BRIDGE_BASE_PENALTY)

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

func _find_path_via_waypoint(
	map_data: MapData,
	from_point: Vector2i,
	to_point: Vector2i,
	waypoint: Vector2i
) -> Array[Vector2i]:
	var first_leg: Array[Vector2i] = _find_path_with_fallback(map_data, from_point, waypoint, false)
	if first_leg.is_empty():
		return []
	var second_leg: Array[Vector2i] = _find_path_with_fallback(map_data, waypoint, to_point, false)
	if second_leg.is_empty():
		return []
	var combined: Array[Vector2i] = first_leg.duplicate()
	for i in range(1, second_leg.size()):
		if combined[combined.size() - 1] != second_leg[i]:
			combined.append(second_leg[i])
	return combined

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
	if tile.rock_role == MapTypes.RockRole.FOOT or tile.rock_role == MapTypes.RockRole.TALUS or tile.debug_tags.has("rock_edge"):
		return maxf(tile.walk_cost, 4.2)
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

func _path_via_bridge(map_data: MapData, from_point: Vector2i, to_point: Vector2i) -> Array[Vector2i]:
	var candidates: Array[Dictionary] = _bridge_candidates(map_data, from_point, to_point)
	if candidates.is_empty():
		return []
	var best_path: Array[Vector2i] = []
	var best_score: float = INF_COST
	for candidate in candidates:
		var variants: Array[Dictionary] = [
			{
				"near": Vector2i(candidate.get("bank_a", Vector2i.ZERO)),
				"far": Vector2i(candidate.get("bank_b", Vector2i.ZERO)),
				"bridge": Array(candidate.get("bridge_tiles", [])),
			},
			{
				"near": Vector2i(candidate.get("bank_b", Vector2i.ZERO)),
				"far": Vector2i(candidate.get("bank_a", Vector2i.ZERO)),
				"bridge": _reversed_points(Array(candidate.get("bridge_tiles", []))),
			},
		]
		for variant in variants:
			var bank_path_a: Array[Vector2i] = _a_star_path(map_data, from_point, Vector2i(variant.get("near", Vector2i.ZERO)), false)
			if bank_path_a.is_empty():
				continue
			var bank_path_b: Array[Vector2i] = _a_star_path(map_data, Vector2i(variant.get("far", Vector2i.ZERO)), to_point, false)
			if bank_path_b.is_empty():
				continue
			var combined: Array[Vector2i] = bank_path_a.duplicate()
			for water_point in Array(variant.get("bridge", [])):
				if combined.is_empty() or combined[combined.size() - 1] != water_point:
					combined.append(water_point)
			for i in range(1, bank_path_b.size()):
				if combined.is_empty() or combined[combined.size() - 1] != bank_path_b[i]:
					combined.append(bank_path_b[i])
			var span: int = int(candidate.get("water_span", 0))
			var score: float = float(combined.size()) + (float(span) * BRIDGE_BASE_PENALTY)
			if score < best_score:
				best_score = score
				best_path = combined
	return best_path

func _bridge_candidates(map_data: MapData, from_point: Vector2i, to_point: Vector2i) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for tile in map_data.tiles:
		var start := Vector2i(tile.x, tile.y)
		if not _is_bridge_bank_tile(tile):
			continue
		for direction in [Vector2i.RIGHT, Vector2i.DOWN]:
			var first_water: Vector2i = start + direction
			if not map_data.is_in_bounds(first_water.x, first_water.y):
				continue
			var first_tile = map_data.get_tile(first_water.x, first_water.y)
			if first_tile == null or not _is_bridge_water_tile(first_tile):
				continue
			var water_tiles: Array[Vector2i] = []
			var probe: Vector2i = first_water
			while map_data.is_in_bounds(probe.x, probe.y) and water_tiles.size() <= BRIDGE_MAX_WATER_SPAN:
				var probe_tile = map_data.get_tile(probe.x, probe.y)
				if probe_tile == null:
					break
				if _is_bridge_water_tile(probe_tile):
					water_tiles.append(probe)
					probe += direction
					continue
				if water_tiles.is_empty():
					break
				if water_tiles.size() <= BRIDGE_MAX_WATER_SPAN and _is_bridge_bank_tile(probe_tile):
					var bank_b: Vector2i = probe
					var line_penalty: float = _distance_to_segment(Vector2(bank_b), Vector2(from_point), Vector2(to_point))
					candidates.append({
						"bank_a": start,
						"bank_b": bank_b,
						"bridge_tiles": water_tiles.duplicate(),
						"water_span": water_tiles.size(),
						"sort_score": float(water_tiles.size()) + line_penalty,
					})
				break
	if candidates.size() <= 1:
		return candidates
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a.get("sort_score", INF_COST)) < float(b.get("sort_score", INF_COST))
	)
	if candidates.size() > 12:
		candidates.resize(12)
	return candidates

func _is_bridge_bank_tile(tile) -> bool:
	if tile == null:
		return false
	if tile.is_water or tile.base_terrain_type == MapTypes.TerrainType.WATER:
		return false
	if tile.is_blocked:
		return false
	return tile.is_walkable

func _is_bridge_water_tile(tile) -> bool:
	if tile == null:
		return false
	return tile.is_water or tile.base_terrain_type == MapTypes.TerrainType.WATER

func _distance_to_segment(point: Vector2, start: Vector2, finish: Vector2) -> float:
	var segment: Vector2 = finish - start
	var length_sq: float = segment.length_squared()
	if length_sq <= 0.0001:
		return point.distance_to(start)
	var t: float = clampf((point - start).dot(segment) / length_sq, 0.0, 1.0)
	var projection: Vector2 = start + (segment * t)
	return point.distance_to(projection)

func _closest_center_point(points: Array[Vector2i], origin: Vector2i) -> Vector2i:
	var best_point: Vector2i = points[0]
	var best_distance: float = best_point.distance_to(origin)
	for point in points:
		var candidate_distance: float = point.distance_to(origin)
		if candidate_distance < best_distance:
			best_distance = candidate_distance
			best_point = point
	return best_point

func _select_attach_point(points: Array[Vector2i], origin: Vector2i, map_data: MapData, _composition: Dictionary) -> Vector2i:
	if points.size() <= 1:
		return points[0]
	var candidates: Array[Vector2i] = _nearest_attach_candidates(points, origin, 6)
	var best_point: Vector2i = candidates[0]
	var best_score: float = INF_COST
	for point in candidates:
		var path: Array[Vector2i] = _find_path_with_fallback(map_data, origin, point, false)
		if path.is_empty():
			continue
		var score: float = _route_physical_score(map_data, path)
		if score < best_score:
			best_score = score
			best_point = point
	if best_score < INF_COST:
		return best_point
	return _closest_center_point(points, origin)

func _nearest_attach_candidates(points: Array[Vector2i], origin: Vector2i, limit: int) -> Array[Vector2i]:
	var ordered: Array[Vector2i] = points.duplicate()
	ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return a.distance_to(origin) < b.distance_to(origin)
	)
	if ordered.size() > limit:
		ordered.resize(limit)
	return ordered

func _route_waypoint_candidates(
	map_data: MapData,
	entry_point: Vector2i,
	attach_point: Vector2i,
	curvature_strength: float,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var candidates: Array[Vector2i] = []
	var segment: Vector2 = Vector2(attach_point - entry_point)
	if segment == Vector2.ZERO:
		return candidates
	var normal: Vector2 = Vector2(-segment.y, segment.x).normalized()
	var base_offset: float = lerpf(4.0, 10.0, curvature_strength / 0.45)
	for t in [0.35, 0.55]:
		var pivot: Vector2 = Vector2(entry_point).lerp(Vector2(attach_point), t)
		for sign in [-1.0, 1.0]:
			var offset: float = base_offset * rng.randf_range(0.82, 1.18)
			var candidate_vec: Vector2 = pivot + (normal * sign * offset)
			var candidate_point := Vector2i(
				clampi(roundi(candidate_vec.x), 1, map_data.width - 2),
				clampi(roundi(candidate_vec.y), 1, map_data.height - 2)
			)
			candidate_point = _nearest_traversable_point(map_data, candidate_point, false)
			if candidate_point == Vector2i(-1, -1):
				continue
			if candidate_point.distance_to(entry_point) < 8.0 or candidate_point.distance_to(attach_point) < 8.0:
				continue
			if not candidates.has(candidate_point):
				candidates.append(candidate_point)
	return candidates

func _best_route_candidate(
	candidates: Array,
	entry_point: Vector2i,
	attach_point: Vector2i,
	curvature_strength: float
) -> Array[Vector2i]:
	var best_path: Array[Vector2i] = candidates[0]
	var best_score: float = _route_candidate_score(best_path, entry_point, attach_point, curvature_strength)
	for i in range(1, candidates.size()):
		var candidate: Array[Vector2i] = candidates[i]
		var score: float = _route_candidate_score(candidate, entry_point, attach_point, curvature_strength)
		if score > best_score:
			best_score = score
			best_path = candidate
	return best_path

func _route_candidate_score(path: Array[Vector2i], entry_point: Vector2i, attach_point: Vector2i, curvature_strength: float) -> float:
	if path.is_empty():
		return -INF_COST
	var direct_distance: float = maxf(1.0, float(absi(entry_point.x - attach_point.x) + absi(entry_point.y - attach_point.y)))
	var curviness: float = float(path.size()) / direct_distance
	var target_curviness: float = 1.03 + (curvature_strength * 0.65)
	var curvature_fit: float = 1.0 - absf(curviness - target_curviness)
	var max_allowed: float = 1.18 + (curvature_strength * 0.85)
	var overshoot_penalty: float = maxf(0.0, curviness - max_allowed) * 18.0
	return (curvature_fit * 20.0) - (float(path.size()) * 0.18) - overshoot_penalty

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
		var source_tile = map_data.get_tile(point.x, point.y)
		var allow_bridge_tile: bool = source_tile != null and (source_tile.is_water or source_tile.base_terrain_type == MapTypes.TerrainType.WATER)
		for offset_index in range(offsets.size()):
			var target: Vector2i = point + offsets[offset_index]
			if not map_data.is_in_bounds(target.x, target.y):
				continue
			if _mark_road_tile(
				map_data,
				target,
				width_cells,
				point_index == 0 and offsets[offset_index] == Vector2i.ZERO,
				allow_bridge_tile
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

func _mark_road_tile(map_data: MapData, point: Vector2i, width_cells: int, is_entry_tile: bool, allow_bridge_tile: bool = false) -> bool:
	var tile = map_data.get_tile(point.x, point.y)
	if tile == null:
		return false
	if not _can_paint_road_tile(tile, is_entry_tile, allow_bridge_tile):
		return false
	var underlying_terrain: int = tile.base_terrain_type
	var is_bridge_tile: bool = allow_bridge_tile and (tile.is_water or underlying_terrain == MapTypes.TerrainType.WATER)
	tile.terrain_type = MapTypes.TerrainType.ROAD
	tile.road_width_cells = maxi(tile.road_width_cells, width_cells)
	tile.road_width_class = maxi(tile.road_width_class, _road_width_class_from_cells(tile.road_width_cells))
	tile.is_road = true
	tile.is_bridge = is_bridge_tile
	tile.is_walkable = true
	tile.is_buildable = false
	tile.is_water = false
	tile.is_blocked = false
	tile.walk_cost = _road_walk_cost(tile.road_width_cells)
	if is_entry_tile:
		tile.poi_tag = MapTypes.PoiTag.ENTRY
	if not tile.debug_tags.has("road"):
		tile.debug_tags.append("road")
	if is_bridge_tile and not tile.debug_tags.has("bridge"):
		tile.debug_tags.append("bridge")
	if underlying_terrain == MapTypes.TerrainType.FOREST and not tile.debug_tags.has("road_through_forest_fringe"):
		tile.debug_tags.append("road_through_forest_fringe")
	if underlying_terrain == MapTypes.TerrainType.ROCK and not tile.debug_tags.has("road_through_rock_edge"):
		tile.debug_tags.append("road_through_rock_edge")
	return true

func _can_paint_road_tile(tile, is_entry_tile: bool, allow_bridge_tile: bool = false) -> bool:
	if tile == null:
		return false
	var is_water_tile: bool = tile.is_water or tile.base_terrain_type == MapTypes.TerrainType.WATER
	if is_water_tile and allow_bridge_tile:
		return not tile.is_blocked
	if is_water_tile and not allow_bridge_tile:
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
			var allow_bridge_tile: bool = tile.is_water or tile.base_terrain_type == MapTypes.TerrainType.WATER
			if _mark_road_tile(map_data, point, inferred_width, false, allow_bridge_tile):
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
		tile.is_bridge = false
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

func _reversed_points(points: Array) -> Array[Vector2i]:
	var reversed: Array[Vector2i] = []
	for i in range(points.size() - 1, -1, -1):
		reversed.append(points[i])
	return reversed
