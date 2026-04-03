extends RefCounted
class_name WaterGenerator

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")
const INF_COST: float = 1_000_000.0

func generate(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> bool:
	var water_spec: Variant = composition.get("water")
	if water_spec == null:
		return false
	if rng.randf() > config.water_chance:
		return false

	var keep_corridor_mask: Dictionary = _build_keep_corridor_mask(map_data, composition, config)
	var style: String = String(water_spec.get("style", "meandering_river"))
	var points: Array[Vector2i] = []
	match style:
		"soft_basin":
			points = _generate_basin_points(map_data, rng, config, composition, water_spec, keep_corridor_mask)
		"river_with_basin":
			points = _generate_river_points(map_data, rng, composition, water_spec, keep_corridor_mask)
			if not points.is_empty():
				points = _attach_river_basin(points, map_data, rng, water_spec, keep_corridor_mask)
		"forked_river":
			points = _generate_river_points(map_data, rng, composition, water_spec, keep_corridor_mask)
			if not points.is_empty():
				points = _attach_river_branch(points, map_data, rng, composition, water_spec, keep_corridor_mask)
		_:
			points = _generate_river_points(map_data, rng, composition, water_spec, keep_corridor_mask)
			var branch_chance: float = clampf(float(water_spec.get("branch_chance", 0.0)), 0.0, 1.0)
			if not points.is_empty() and branch_chance > 0.0 and rng.randf() < branch_chance:
				points = _attach_river_branch(points, map_data, rng, composition, water_spec, keep_corridor_mask)
	if points.is_empty() and style != "soft_basin":
		var fallback_spec: Dictionary = water_spec.duplicate(true)
		fallback_spec["style"] = "soft_basin"
		fallback_spec["basins_min"] = maxi(1, int(fallback_spec.get("basins_min", 1)))
		fallback_spec["basins_max"] = maxi(int(fallback_spec.get("basins_min", 1)), int(fallback_spec.get("basins_max", 2)))
		points = _generate_basin_points(map_data, rng, config, composition, fallback_spec, keep_corridor_mask)

	if points.size() < max(24, int(config.min_water_area / 3)):
		return false

	var region_id: int = 300
	map_data.register_region(
		region_id,
		MapTypes.RegionType.WATER_REGION,
		"water_body",
		{
			"target_area": points.size(),
			"style": style,
			"basin_count": int(water_spec.get("basins_max", 0)),
		}
	)
	for point in points:
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
			continue
		tile.base_terrain_type = MapTypes.TerrainType.WATER
		tile.terrain_type = MapTypes.TerrainType.WATER
		tile.blocker_type = MapTypes.BlockerType.NONE
		tile.region_id = region_id
		tile.region_type = MapTypes.RegionType.WATER_REGION
		tile.is_walkable = false
		tile.is_water = true
		tile.is_blocked = false
		tile.is_road = false
		tile.is_buildable = false
		tile.is_future_wallable = false
		tile.walk_cost = 999.0
		tile.resource_tag = MapTypes.ResourceTag.NONE
		tile.debug_tags.clear()
		tile.debug_tags.append("water_region")
		if style == "soft_basin":
			tile.debug_tags.append("water_basin")
		else:
			tile.debug_tags.append("water_channel")
	return true

func _generate_basin_points(
	map_data: MapData,
	rng: RandomNumberGenerator,
	config,
	_composition: Dictionary,
	water_spec: Dictionary,
	keep_corridor_mask: Dictionary
) -> Array[Vector2i]:
	var anchor: Vector2 = water_spec.get("anchor", Vector2(0.78, 0.24))
	var center := Vector2(
		anchor.x * float(map_data.width - 1),
		anchor.y * float(map_data.height - 1)
	)
	var target_area: int = rng.randi_range(config.min_water_area, config.max_water_area)
	var size_bias: float = float(water_spec.get("size_bias", 1.0))
	var basin_min: int = int(water_spec.get("basins_min", 1))
	var basin_max: int = max(basin_min, int(water_spec.get("basins_max", 2)))
	var basin_count: int = rng.randi_range(basin_min, basin_max)
	var jitter: float = float(water_spec.get("jitter", 0.14))
	var selected := {}
	var basins: Array[Dictionary] = []

	for _i in range(maxi(1, basin_count)):
		var direction: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		var spread: float = sqrt(float(target_area)) * rng.randf_range(0.25, 0.65)
		var basin_center: Vector2 = _clamp_world(center + direction * spread, map_data)
		var basin_radius: float = sqrt(float(target_area) / float(maxi(1, basin_count))) * rng.randf_range(0.46, 0.76) * size_bias
		basins.append({
			"center": basin_center,
			"radius": basin_radius,
		})
		_stamp_disc(selected, Vector2i(roundi(basin_center.x), roundi(basin_center.y)), basin_radius, map_data)

	for i in range(1, basins.size()):
		var prev_center: Vector2 = Vector2(basins[i - 1]["center"])
		var current_center: Vector2 = Vector2(basins[i]["center"])
		var link_radius: float = minf(float(basins[i - 1]["radius"]), float(basins[i]["radius"])) * rng.randf_range(0.24, 0.42)
		var seam_line: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([prev_center, current_center])
		for point in seam_line:
			_stamp_disc(selected, point, link_radius, map_data)

	selected = _roughen(selected, jitter, map_data, int(center.x * 13.0 + center.y * 19.0))
	var points: Array[Vector2i] = []
	points.assign(selected.keys())
	points = _sanitize_points(map_data, points, keep_corridor_mask)
	points = _extract_largest_component(points)
	points = _trim_to_target(points, center, int(float(target_area) * 1.25))
	return points

func _generate_river_points(
	map_data: MapData,
	rng: RandomNumberGenerator,
	composition: Dictionary,
	water_spec: Dictionary,
	keep_corridor_mask: Dictionary
) -> Array[Vector2i]:
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var sides: Dictionary = _pick_flow_sides(water_spec, rng)
	var start_side: String = String(sides.get("start", "west"))
	var end_side: String = String(sides.get("end", "east"))
	var anchor: Vector2 = water_spec.get("anchor", Vector2(0.76, 0.24))
	var start_point: Vector2i = _edge_point_for_side(start_side, anchor, map_data, rng)
	var end_point: Vector2i = _edge_point_for_side(end_side, anchor, map_data, rng)
	start_point = _nearest_river_entry(map_data, start_point, keep_corridor_mask)
	end_point = _nearest_river_entry(map_data, end_point, keep_corridor_mask)
	if start_point == Vector2i(-1, -1) or end_point == Vector2i(-1, -1):
		return []

	var controls: Array[Vector2i] = _build_river_controls(
		map_data,
		start_point,
		end_point,
		center,
		anchor,
		start_side,
		end_side,
		water_spec,
		keep_corridor_mask,
		rng
	)
	if controls.size() < 2:
		return []

	var axis: Array[Vector2i] = []
	for index in range(controls.size() - 1):
		var segment: Array[Vector2i] = _water_pathfind(
			map_data,
			controls[index],
			controls[index + 1],
			keep_corridor_mask,
			center,
			water_spec
		)
		if segment.is_empty():
			return []
		for point in segment:
			if axis.is_empty() or axis[axis.size() - 1] != point:
				axis.append(point)
	if axis.size() < 12:
		return []

	var selected := {}
	var width_min: float = float(water_spec.get("channel_width_min", 2.6))
	var width_max: float = maxf(width_min, float(water_spec.get("channel_width_max", 4.8)))
	for index in range(axis.size()):
		var point: Vector2i = axis[index]
		var t: float = float(index) / maxf(1.0, float(axis.size() - 1))
		var sway: float = 0.5 + (sin((t * PI * 2.0) + rng.randf_range(-0.4, 0.4)) * 0.22)
		var width: float = lerpf(width_min, width_max, clampf(sway, 0.0, 1.0))
		width += rng.randf_range(-0.22, 0.22)
		_stamp_disc(selected, point, maxf(1.6, width), map_data)

	selected = _roughen(selected, float(water_spec.get("jitter", 0.12)), map_data, int(center.x * 31.0 + center.y * 17.0))
	var points: Array[Vector2i] = []
	points.assign(selected.keys())
	points = _sanitize_points(map_data, points, keep_corridor_mask)
	return points

func _attach_river_basin(
	points: Array[Vector2i],
	map_data: MapData,
	rng: RandomNumberGenerator,
	water_spec: Dictionary,
	keep_corridor_mask: Dictionary
) -> Array[Vector2i]:
	if points.size() < 10:
		return points
	var selected := {}
	for point in points:
		selected[point] = true
	var pivot_index: int = clampi(int(round(float(points.size() - 1) * rng.randf_range(0.30, 0.72))), 1, points.size() - 2)
	var pivot: Vector2i = points[pivot_index]
	var axis_normal: Vector2 = _axis_normal(points, pivot_index)
	var basin_center: Vector2 = Vector2(pivot) + axis_normal * rng.randf_range(2.0, 5.0)
	var basin_radius: float = rng.randf_range(4.5, 7.8) * float(water_spec.get("size_bias", 1.0))
	_stamp_disc(selected, Vector2i(roundi(basin_center.x), roundi(basin_center.y)), basin_radius, map_data)
	var connector: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([Vector2(pivot), basin_center])
	for point in connector:
		_stamp_disc(selected, point, basin_radius * 0.34, map_data)
	var output: Array[Vector2i] = []
	output.assign(selected.keys())
	return _sanitize_points(map_data, output, keep_corridor_mask)

func _attach_river_branch(
	points: Array[Vector2i],
	map_data: MapData,
	rng: RandomNumberGenerator,
	composition: Dictionary,
	water_spec: Dictionary,
	keep_corridor_mask: Dictionary
) -> Array[Vector2i]:
	if points.size() < 18:
		return points
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var selected := {}
	for point in points:
		selected[point] = true
	var branch_index: int = clampi(int(round(float(points.size() - 1) * rng.randf_range(0.18, 0.48))), 1, points.size() - 3)
	var branch_start: Vector2i = points[branch_index]
	var preferred_sides: Array[String] = ["north", "south", "east", "west"]
	_shuffle(preferred_sides, rng)
	var branch_end := Vector2i(-1, -1)
	for side in preferred_sides:
		var candidate: Vector2i = _edge_point_for_side(side, water_spec.get("anchor", Vector2(0.5, 0.5)), map_data, rng)
		candidate = _nearest_river_entry(map_data, candidate, keep_corridor_mask)
		if candidate == Vector2i(-1, -1):
			continue
		if candidate.distance_to(branch_start) < 18.0:
			continue
		branch_end = candidate
		break
	if branch_end == Vector2i(-1, -1):
		return points

	var branch_path: Array[Vector2i] = _water_pathfind(map_data, branch_start, branch_end, keep_corridor_mask, center, water_spec)
	if branch_path.is_empty():
		return points
	var width_scale: float = rng.randf_range(0.68, 0.86)
	var width_min: float = float(water_spec.get("channel_width_min", 2.6)) * width_scale
	var width_max: float = float(water_spec.get("channel_width_max", 4.8)) * width_scale
	for index in range(branch_path.size()):
		var t: float = float(index) / maxf(1.0, float(branch_path.size() - 1))
		var width: float = lerpf(width_min, width_max, 0.5 + (sin(t * PI) * 0.18))
		_stamp_disc(selected, branch_path[index], maxf(1.4, width), map_data)
	var output: Array[Vector2i] = []
	output.assign(selected.keys())
	return _sanitize_points(map_data, output, keep_corridor_mask)

func _build_river_controls(
	map_data: MapData,
	start_point: Vector2i,
	end_point: Vector2i,
	center: Vector2,
	anchor: Vector2,
	start_side: String,
	end_side: String,
	water_spec: Dictionary,
	keep_corridor_mask: Dictionary,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var controls: Array[Vector2i] = [start_point]
	var desired_distance: float = rng.randf_range(
		float(water_spec.get("near_center_distance_min", 10.0)),
		float(water_spec.get("near_center_distance_max", 18.0))
	)
	var flow_dir: Vector2 = (Vector2(end_point) - Vector2(start_point)).normalized()
	if flow_dir == Vector2.ZERO:
		flow_dir = Vector2.RIGHT
	var normal: Vector2 = Vector2(-flow_dir.y, flow_dir.x)
	var anchor_world := Vector2(anchor.x * float(map_data.width - 1), anchor.y * float(map_data.height - 1))
	if (anchor_world - center).dot(normal) < 0.0:
		normal = -normal
	var near_center: Vector2i = _find_near_center_waypoint(map_data, center, normal, desired_distance, keep_corridor_mask)
	var bend_a: Vector2i = _offset_control_between(map_data, start_point, near_center, normal, rng.randf_range(4.0, 10.0))
	var bend_b: Vector2i = _offset_control_between(map_data, near_center, end_point, -normal, rng.randf_range(4.0, 10.0))
	for control in [bend_a, near_center, bend_b]:
		if control == Vector2i(-1, -1):
			continue
		if controls[controls.size() - 1] != control:
			controls.append(control)
	if controls[controls.size() - 1] != end_point:
		controls.append(end_point)
	return controls

func _find_near_center_waypoint(
	map_data: MapData,
	center: Vector2,
	normal: Vector2,
	desired_distance: float,
	keep_corridor_mask: Dictionary
) -> Vector2i:
	var directions: Array[Vector2] = [
		normal.normalized(),
		-normal.normalized(),
		normal.normalized().rotated(0.35),
		normal.normalized().rotated(-0.35),
	]
	for direction in directions:
		for distance_bias in [0.0, -2.0, 2.0, -4.0, 4.0]:
			var sample: Vector2 = center + direction * maxf(6.0, desired_distance + distance_bias)
			var point := Vector2i(roundi(sample.x), roundi(sample.y))
			if _is_viable_river_point(map_data, point, keep_corridor_mask):
				return point
	return Vector2i(roundi(center.x), clampi(int(round(center.y + desired_distance)), 1, map_data.height - 2))

func _offset_control_between(
	map_data: MapData,
	from_point: Vector2i,
	to_point: Vector2i,
	normal: Vector2,
	offset: float
) -> Vector2i:
	var midpoint: Vector2 = Vector2(from_point).lerp(Vector2(to_point), 0.5) + normal.normalized() * offset
	midpoint = _clamp_world(midpoint, map_data)
	return Vector2i(roundi(midpoint.x), roundi(midpoint.y))

func _pick_flow_sides(water_spec: Dictionary, rng: RandomNumberGenerator) -> Dictionary:
	var explicit_start: String = String(water_spec.get("flow_side_start", ""))
	var explicit_end: String = String(water_spec.get("flow_side_end", ""))
	if not explicit_start.is_empty() and not explicit_end.is_empty():
		return {"start": explicit_start, "end": explicit_end}
	var sector: int = int(water_spec.get("sector", 0))
	match sector:
		0:
			return {"start": "west" if rng.randf() < 0.5 else "north", "end": "east" if rng.randf() < 0.6 else "south"}
		1:
			return {"start": "north" if rng.randf() < 0.5 else "east", "end": "south" if rng.randf() < 0.6 else "west"}
		2:
			return {"start": "west" if rng.randf() < 0.5 else "south", "end": "east" if rng.randf() < 0.6 else "north"}
		_:
			return {"start": "south" if rng.randf() < 0.5 else "east", "end": "north" if rng.randf() < 0.6 else "west"}

func _edge_point_for_side(side: String, anchor: Vector2, map_data: MapData, rng: RandomNumberGenerator) -> Vector2i:
	var offset: float = anchor.x if side == "north" or side == "south" else anchor.y
	offset = clampf(offset + rng.randf_range(-0.14, 0.14), 0.14, 0.86)
	return GenerationUtilsClass.point_on_side(side, map_data.width, map_data.height, offset, 1)

func _nearest_river_entry(map_data: MapData, origin: Vector2i, keep_corridor_mask: Dictionary) -> Vector2i:
	if _is_viable_river_point(map_data, origin, keep_corridor_mask):
		return origin
	var frontier: Array[Vector2i] = [origin]
	var visited := {origin: true}
	var depth: int = 0
	while not frontier.is_empty() and depth < 14:
		var iteration_count: int = frontier.size()
		for _i in range(iteration_count):
			var current: Vector2i = frontier.pop_front()
			if _is_viable_river_point(map_data, current, keep_corridor_mask):
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

func _water_pathfind(
	map_data: MapData,
	from_point: Vector2i,
	to_point: Vector2i,
	keep_corridor_mask: Dictionary,
	center: Vector2,
	water_spec: Dictionary
) -> Array[Vector2i]:
	var open: Array[Vector2i] = [from_point]
	var open_lookup := {from_point: true}
	var closed := {}
	var came_from := {}
	var g_score := {from_point: 0.0}
	var f_score := {from_point: _water_heuristic(from_point, to_point)}

	while not open.is_empty():
		var current: Vector2i = _pop_lowest_f(open, f_score)
		open_lookup.erase(current)
		if current == to_point:
			return _reconstruct_path(came_from, current)
		closed[current] = true
		for direction in GenerationUtilsClass.cardinal_neighbors(Vector2i.ZERO):
			var next: Vector2i = current + direction
			if not map_data.is_in_bounds(next.x, next.y):
				continue
			if closed.has(next):
				continue
			var step_cost: float = _water_step_cost(map_data, next, keep_corridor_mask, center, water_spec)
			if step_cost >= INF_COST:
				continue
			var turn_penalty: float = 0.0
			if came_from.has(current):
				var prev: Vector2i = came_from[current]
				var first_dir: Vector2i = current - prev
				var second_dir: Vector2i = next - current
				if first_dir != second_dir:
					turn_penalty = 0.28
			var tentative: float = float(g_score[current]) + step_cost + turn_penalty
			if (not g_score.has(next)) or tentative < float(g_score[next]):
				came_from[next] = current
				g_score[next] = tentative
				f_score[next] = tentative + _water_heuristic(next, to_point)
				if not open_lookup.has(next):
					open.append(next)
					open_lookup[next] = true
	return []

func _water_step_cost(
	map_data: MapData,
	point: Vector2i,
	keep_corridor_mask: Dictionary,
	center: Vector2,
	water_spec: Dictionary
) -> float:
	if keep_corridor_mask.has(point):
		return INF_COST
	var tile = map_data.get_tile(point.x, point.y)
	if tile == null:
		return INF_COST
	if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
		return INF_COST
	if tile.is_blocked:
		return INF_COST
	if tile.is_water:
		return 0.75
	var terrain_cost: float = 1.0
	match tile.base_terrain_type:
		MapTypes.TerrainType.FOREST:
			terrain_cost = 2.2
		MapTypes.TerrainType.ROCK:
			terrain_cost = 4.8
		_:
			terrain_cost = 1.0
	var desired_distance: float = 0.5 * (
		float(water_spec.get("near_center_distance_min", 10.0)) +
		float(water_spec.get("near_center_distance_max", 18.0))
	)
	var center_distance: float = Vector2(point).distance_to(center)
	var distance_penalty: float = absf(center_distance - desired_distance) * 0.10
	if center_distance < desired_distance - 3.0:
		distance_penalty += 8.0
	var edge_penalty: float = 0.0
	if point.x <= 1 or point.y <= 1 or point.x >= map_data.width - 2 or point.y >= map_data.height - 2:
		edge_penalty = 0.24
	var noise: float = float(GenerationUtilsClass.hash2d(point.x, point.y, 97) % 1000) / 1000.0
	return terrain_cost + distance_penalty + edge_penalty + ((noise - 0.5) * 0.16)

func _water_heuristic(from_point: Vector2i, to_point: Vector2i) -> float:
	return float(absi(from_point.x - to_point.x) + absi(from_point.y - to_point.y)) * 0.92

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

func _reconstruct_path(came_from: Dictionary, current: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [current]
	var cursor: Vector2i = current
	while came_from.has(cursor):
		cursor = came_from[cursor]
		path.push_front(cursor)
	return path

func _axis_normal(points: Array[Vector2i], index: int) -> Vector2:
	var previous: Vector2i = points[maxi(index - 1, 0)]
	var next: Vector2i = points[mini(index + 1, points.size() - 1)]
	var tangent: Vector2 = (Vector2(next) - Vector2(previous)).normalized()
	if tangent == Vector2.ZERO:
		return Vector2.UP
	return Vector2(-tangent.y, tangent.x).normalized()

func _is_viable_river_point(map_data: MapData, point: Vector2i, keep_corridor_mask: Dictionary) -> bool:
	if not map_data.is_in_bounds(point.x, point.y):
		return false
	if keep_corridor_mask.has(point):
		return false
	var tile = map_data.get_tile(point.x, point.y)
	if tile == null:
		return false
	if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
		return false
	return not tile.is_blocked

func _build_keep_corridor_mask(map_data: MapData, composition: Dictionary, config) -> Dictionary:
	var mask := {}
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var corridor_width: int = int(composition.get("corridor_width", maxi(config.minimum_path_width + 1, 3)))
	var radius: int = maxi(1, int(floor(float(corridor_width) * 0.5)) + 2)
	for entry_spec in composition.get("entries", []):
		var entry_point: Vector2i = entry_spec.get("point", Vector2i.ZERO)
		_stamp_mask(mask, entry_point, radius + 2, map_data)
	_stamp_mask(mask, Vector2i(roundi(center.x), roundi(center.y)), radius + 3, map_data)
	return mask

func _sanitize_points(map_data: MapData, points: Array[Vector2i], keep_corridor_mask: Dictionary) -> Array[Vector2i]:
	var selected := {}
	for point in points:
		if not map_data.is_in_bounds(point.x, point.y):
			continue
		if keep_corridor_mask.has(point):
			continue
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
			continue
		if tile.is_blocked:
			continue
		selected[point] = true
	var result: Array[Vector2i] = []
	result.assign(selected.keys())
	return result

func _trim_to_target(points: Array[Vector2i], center: Vector2, max_count: int) -> Array[Vector2i]:
	if points.size() <= max_count:
		return points
	var sorted: Array[Vector2i] = points.duplicate()
	sorted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return Vector2(a).distance_squared_to(center) < Vector2(b).distance_squared_to(center)
	)
	var trimmed: Array[Vector2i] = []
	for i in range(mini(max_count, sorted.size())):
		trimmed.append(sorted[i])
	return trimmed

func _stamp_disc(selected: Dictionary, center: Vector2i, radius: float, map_data: MapData) -> void:
	var r: int = ceili(maxf(1.0, radius))
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			if not map_data.is_in_bounds(x, y):
				continue
			var point := Vector2i(x, y)
			if Vector2(point).distance_to(Vector2(center)) <= radius:
				selected[point] = true

func _stamp_mask(mask: Dictionary, center: Vector2i, radius: int, map_data: MapData) -> void:
	var r: int = maxi(radius, 0)
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			if not map_data.is_in_bounds(x, y):
				continue
			var point := Vector2i(x, y)
			if Vector2(point).distance_to(Vector2(center)) <= float(r) + 0.2:
				mask[point] = true

func _roughen(selected: Dictionary, jitter: float, map_data: MapData, salt: int) -> Dictionary:
	if selected.is_empty():
		return selected
	var result: Dictionary = selected.duplicate(true)
	for key in selected.keys():
		var point: Vector2i = key
		var boundary_neighbors: int = 0
		for neighbor in GenerationUtilsClass.cardinal_neighbors(point):
			if not result.has(neighbor):
				boundary_neighbors += 1
		if boundary_neighbors <= 0:
			continue
		var noise: float = float(GenerationUtilsClass.hash2d(point.x, point.y, salt) % 1000) / 1000.0
		if noise < jitter * 0.56:
			result.erase(point)
	var points: Array[Vector2i] = []
	points.assign(result.keys())
	var smoothed: Array[Vector2i] = GenerationUtilsClass.smooth_points(map_data, points, 2, 3)
	var output := {}
	for point in smoothed:
		output[point] = true
	return output

func _extract_largest_component(points: Array[Vector2i]) -> Array[Vector2i]:
	var selected := {}
	for point in points:
		selected[point] = true
	var visited := {}
	var best_component: Array[Vector2i] = []
	for key in selected.keys():
		var point: Vector2i = key
		if visited.has(point):
			continue
		var component: Array[Vector2i] = []
		var frontier: Array[Vector2i] = [point]
		visited[point] = true
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_front()
			component.append(current)
			for neighbor in GenerationUtilsClass.cardinal_neighbors(current):
				if visited.has(neighbor):
					continue
				if not selected.has(neighbor):
					continue
				visited[neighbor] = true
				frontier.append(neighbor)
		if component.size() > best_component.size():
			best_component = component
	return best_component

func _clamp_world(point: Vector2, map_data: MapData) -> Vector2:
	return Vector2(
		clampf(point.x, 1.0, float(map_data.width - 2)),
		clampf(point.y, 1.0, float(map_data.height - 2))
	)

func _shuffle(array: Array, rng: RandomNumberGenerator) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = array[i]
		array[i] = array[j]
		array[j] = tmp
