extends RefCounted
class_name RegionGenerator

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")

func initialize_ground(map_data: MapData, composition: Dictionary) -> void:
	map_data.clear_runtime_collections()
	map_data.composition_template_id = String(composition.get("template_id", "unknown"))
	map_data.register_region(1, MapTypes.RegionType.OPEN_GROUND, "open_ground", {})
	for tile in map_data.tiles:
		tile.terrain_type = MapTypes.TerrainType.GROUND
		tile.base_terrain_type = MapTypes.TerrainType.GROUND
		tile.height_class = _choose_height_class(tile.x, tile.y, map_data.width, map_data.height)
		tile.region_id = 1
		tile.region_type = MapTypes.RegionType.OPEN_GROUND
		tile.blocker_type = MapTypes.BlockerType.NONE
		tile.road_width_class = MapTypes.RoadWidthClass.NONE
		tile.transition_type = MapTypes.TransitionType.NONE
		tile.walk_cost = 1.0
		tile.is_walkable = true
		tile.is_buildable = false
		tile.is_road = false
		tile.is_water = false
		tile.is_blocked = false
		tile.is_future_wallable = false
		tile.resource_tag = MapTypes.ResourceTag.NONE
		tile.poi_tag = MapTypes.PoiTag.NONE
		tile.threat_value = 0.0
		tile.transition_flags = {}
		tile.debug_tags.clear()
		tile.debug_tags.append("open_ground")

func generate_clearing(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	var target_area: int = rng.randi_range(config.min_center_area, config.max_center_area)
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var region_id: int = 10
	map_data.register_region(region_id, MapTypes.RegionType.CENTER_CLEARING, "center_clearing", {"target_area": target_area})

	var points: Array[Vector2i] = _grow_clearing_points(map_data, center, target_area, rng, composition)
	points = _smooth_clearing_points(map_data, points)
	if points.size() < int(float(target_area) * 0.60):
		var fallback_radius: float = sqrt(float(target_area)) * rng.randf_range(0.52, 0.74)
		var fallback_raw: Array[Vector2i] = GenerationUtilsClass.fill_blob(
			map_data,
			center,
			fallback_radius,
			fallback_radius * rng.randf_range(0.78, 1.22),
			rng
		)
		points = GenerationUtilsClass.smooth_points(map_data, fallback_raw, 2, 3)

	map_data.central_zone_tiles = points.duplicate()

	for point in points:
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		tile.terrain_type = MapTypes.TerrainType.CLEARING
		tile.base_terrain_type = MapTypes.TerrainType.CLEARING
		tile.region_id = region_id
		tile.region_type = MapTypes.RegionType.CENTER_CLEARING
		tile.is_walkable = true
		tile.is_buildable = true
		tile.walk_cost = 1.0
		tile.debug_tags.clear()
		tile.debug_tags.append("center_clearing")
		tile.debug_tags.append("build_zone")
		if not tile.debug_tags.has("clearing_core"):
			tile.debug_tags.append("clearing_core")

func stamp_approach_regions(map_data: MapData, composition: Dictionary) -> void:
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	for entry_spec in composition.get("entries", []):
		var entry_point: Vector2i = entry_spec.get("point", Vector2i.ZERO)
		var region_id: int = int(entry_spec.get("region_id", 100))
		map_data.register_region(region_id, MapTypes.RegionType.APPROACH_CORRIDOR, "approach_%s" % String(entry_spec.get("side", "entry")), {})
		var samples := GenerationUtilsClass.rasterize_polyline([Vector2(entry_point), center])
		for point in samples:
			if not map_data.is_in_bounds(point.x, point.y):
				continue
			var tile = map_data.get_tile(point.x, point.y)
			if tile == null:
				continue
			if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
				continue
			if tile.region_type == MapTypes.RegionType.OPEN_GROUND:
				tile.region_id = region_id
				tile.region_type = MapTypes.RegionType.APPROACH_CORRIDOR
				if not tile.debug_tags.has("approach_corridor"):
					tile.debug_tags.append("approach_corridor")

func _choose_height_class(x: int, y: int, width: int, height: int) -> int:
	var nx: float = (float(x) / max(1.0, float(width - 1))) - 0.5
	var ny: float = (float(y) / max(1.0, float(height - 1))) - 0.5
	var slope_bias: float = (ny * 0.7) - (nx * 0.18)
	if slope_bias < -0.16:
		return MapTypes.HeightClass.LOW
	if slope_bias > 0.18:
		return MapTypes.HeightClass.HIGH
	return MapTypes.HeightClass.MID

func _grow_clearing_points(
	map_data: MapData,
	center: Vector2,
	target_area: int,
	rng: RandomNumberGenerator,
	composition: Dictionary
) -> Array[Vector2i]:
	var seed_point := Vector2i(
		clampi(roundi(center.x), 1, map_data.width - 2),
		clampi(roundi(center.y), 1, map_data.height - 2)
	)
	var selected := {seed_point: true}
	var frontier: Array[Vector2i] = []
	_push_frontier_neighbors(seed_point, map_data, selected, frontier)
	var scenario_hash: int = absi(String(composition.get("scenario_family_id", "default")).hash())
	var axis_angle: float = rng.randf_range(0.0, TAU) + float(scenario_hash % 17) * 0.09
	var axis: Vector2 = Vector2.RIGHT.rotated(axis_angle)
	var radius_hint: float = maxf(6.0, sqrt(float(target_area)) * 1.24)
	var safety: int = target_area * 20

	while selected.size() < target_area and not frontier.is_empty() and safety > 0:
		safety -= 1
		var index: int = rng.randi_range(0, frontier.size() - 1)
		var candidate: Vector2i = frontier[index]
		frontier.remove_at(index)
		if selected.has(candidate):
			continue
		if not map_data.is_in_bounds(candidate.x, candidate.y):
			continue

		var delta: Vector2 = Vector2(candidate) - center
		var distance_norm: float = delta.length() / radius_hint
		var alignment: float = 0.0 if delta == Vector2.ZERO else absf(delta.normalized().dot(axis))
		var wobble: float = sin((float(candidate.x) * 0.23) + (float(candidate.y) * 0.19) + float(scenario_hash % 97)) * 0.08
		var chance: float = 0.84 - (distance_norm * 0.48) + (alignment * 0.16) + wobble + rng.randf_range(-0.10, 0.10)
		if rng.randf() > chance:
			continue

		selected[candidate] = true
		_push_frontier_neighbors(candidate, map_data, selected, frontier)

	if selected.size() < target_area:
		_expand_clearing_fallback(map_data, selected, target_area, center, radius_hint, rng)

	var points: Array[Vector2i] = []
	points.assign(selected.keys())
	return points

func _expand_clearing_fallback(
	map_data: MapData,
	selected: Dictionary,
	target_area: int,
	center: Vector2,
	radius_hint: float,
	rng: RandomNumberGenerator
) -> void:
	var directions: Array[Vector2i] = [
		Vector2i.UP,
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
	]
	var safety: int = target_area * 24
	while selected.size() < target_area and safety > 0:
		safety -= 1
		var keys: Array = selected.keys()
		var source: Vector2i = keys[rng.randi_range(0, keys.size() - 1)]
		var delta: Vector2i = directions[rng.randi_range(0, directions.size() - 1)]
		var candidate: Vector2i = source + delta
		if selected.has(candidate):
			continue
		if not map_data.is_in_bounds(candidate.x, candidate.y):
			continue
		if Vector2(candidate).distance_to(center) > radius_hint * 1.36:
			continue
		selected[candidate] = true

func _smooth_clearing_points(map_data: MapData, points: Array[Vector2i]) -> Array[Vector2i]:
	var pass_a: Array[Vector2i] = GenerationUtilsClass.smooth_points(map_data, points, 2, 3)
	var pass_b: Array[Vector2i] = GenerationUtilsClass.smooth_points(map_data, pass_a, 2, 2)
	var selected := {}
	for point in pass_b:
		selected[point] = true
	for point in pass_b:
		var neighbors: int = 0
		for neighbor in GenerationUtilsClass.cardinal_neighbors(point):
			if selected.has(neighbor):
				neighbors += 1
		if neighbors >= 3:
			for neighbor in GenerationUtilsClass.cardinal_neighbors(point):
				if map_data.is_in_bounds(neighbor.x, neighbor.y):
					selected[neighbor] = true
	var result: Array[Vector2i] = []
	result.assign(selected.keys())
	return result

func _push_frontier_neighbors(
	point: Vector2i,
	map_data: MapData,
	selected: Dictionary,
	frontier: Array[Vector2i]
) -> void:
	for neighbor in GenerationUtilsClass.cardinal_neighbors(point):
		if selected.has(neighbor):
			continue
		if not map_data.is_in_bounds(neighbor.x, neighbor.y):
			continue
		if frontier.has(neighbor):
			continue
		frontier.append(neighbor)
