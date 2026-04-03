extends RefCounted
class_name WaterGenerator

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")

func generate(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> bool:
	var water_spec: Variant = composition.get("water")
	if water_spec == null:
		return false
	if rng.randf() > config.water_chance:
		return false

	var keep_corridor_mask: Dictionary = _build_keep_corridor_mask(map_data, composition, config)
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
	if points.size() < max(24, int(config.min_water_area / 3)):
		return false

	var region_id: int = 300
	map_data.register_region(
		region_id,
		MapTypes.RegionType.WATER_REGION,
		"water_body",
		{
			"target_area": target_area,
			"style": String(water_spec.get("style", "soft_basin")),
			"basin_count": basin_count,
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
		tile.debug_tags.append("water_core")
	return true

func _build_keep_corridor_mask(map_data: MapData, composition: Dictionary, config) -> Dictionary:
	var mask := {}
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var corridor_width: int = int(composition.get("corridor_width", maxi(config.minimum_path_width + 1, 3)))
	var radius: int = maxi(1, int(floor(float(corridor_width) * 0.5)) + 1)
	for entry_spec in composition.get("entries", []):
		var entry_point: Vector2i = entry_spec.get("point", Vector2i.ZERO)
		var samples: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([Vector2(entry_point), center])
		for sample in samples:
			_stamp_mask(mask, sample, radius, map_data)
		_stamp_mask(mask, entry_point, radius + 1, map_data)
	_stamp_mask(mask, Vector2i(roundi(center.x), roundi(center.y)), radius + 2, map_data)
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
