extends RefCounted
class_name BlockerGenerator

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")

func generate(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var keep_corridor_mask: Dictionary = _build_keep_corridor_mask(map_data, composition, config)
	for blocker_spec in composition.get("blockers", []):
		var anchor: Vector2 = blocker_spec.get("anchor", Vector2(0.25, 0.25))
		var world_anchor := Vector2(anchor.x * float(map_data.width - 1), anchor.y * float(map_data.height - 1))
		if world_anchor.distance_to(center) < float(config.min_blocker_distance_from_center):
			continue

		var blocker_type: int = int(blocker_spec.get("kind", MapTypes.BlockerType.FOREST))
		var shape: String = String(blocker_spec.get("shape", "metaball"))
		var core_points: Array[Vector2i] = []
		match shape:
			"spine":
				core_points = _generate_spine_mass(map_data, world_anchor, center, blocker_spec, rng, blocker_type)
			"metaball":
				core_points = _generate_metaball_mass(map_data, world_anchor, center, blocker_spec, rng, blocker_type)
			_:
				core_points = _generate_metaball_mass(map_data, world_anchor, center, blocker_spec, rng, blocker_type)

		core_points = _sanitize_points(map_data, core_points, keep_corridor_mask)
		var preserve_disconnected_clusters: bool = blocker_type == MapTypes.BlockerType.FOREST and bool(blocker_spec.get("allow_disconnected_clusters", false))
		if preserve_disconnected_clusters:
			var min_component_tiles: int = max(6, int(blocker_spec.get("min_component_tiles", 10)))
			core_points = _extract_components_above_size(core_points, min_component_tiles)
		else:
			core_points = _extract_largest_component(core_points)
		if core_points.size() < max(24, int(config.min_blocker_area / 6)):
			continue

		var edge_band: int = maxi(0, int(blocker_spec.get("edge_band", 1)))
		var fringe_points: Array[Vector2i] = _build_fringe_points(map_data, core_points, edge_band, keep_corridor_mask)
		var region_id: int = int(blocker_spec.get("region_id", 200))
		map_data.register_region(
			region_id,
			MapTypes.RegionType.BLOCKER_MASS,
			"blocker_%d" % region_id,
			{
				"blocker_type": blocker_type,
				"shape": shape,
				"core_tiles": core_points.size(),
				"fringe_tiles": fringe_points.size(),
			}
		)
		_stamp_core_tiles(map_data, core_points, region_id, blocker_type)
		_stamp_fringe_tiles(map_data, fringe_points, region_id, blocker_type)

func _generate_spine_mass(
	map_data: MapData,
	anchor: Vector2,
	center: Vector2,
	spec: Dictionary,
	rng: RandomNumberGenerator,
	blocker_type: int
) -> Array[Vector2i]:
	var segments_min: int = int(spec.get("segments_min", 2))
	var segments_max: int = max(segments_min, int(spec.get("segments_max", 5)))
	var segments: int = rng.randi_range(segments_min, segments_max)
	var length: float = rng.randf_range(
		float(spec.get("length_min", 18.0)),
		float(spec.get("length_max", 36.0))
	) * float(spec.get("size_bias", 1.0))
	var base_width: float = rng.randf_range(
		float(spec.get("thickness_min", 2.6)),
		float(spec.get("thickness_max", 5.4))
	) * float(spec.get("size_bias", 1.0))
	var bend: float = rng.randf_range(
		float(spec.get("bend_min", 0.18)),
		float(spec.get("bend_max", 0.42))
	)
	var center_dir: Vector2 = (center - anchor).normalized()
	if center_dir == Vector2.ZERO:
		center_dir = Vector2.RIGHT
	var heading: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
	heading = heading.slerp(center_dir, clampf(float(spec.get("aggression", 0.55)) * 0.45, 0.0, 0.75))

	var controls: Array[Vector2] = [anchor]
	var current: Vector2 = anchor
	for _step in range(segments):
		heading = heading.rotated(rng.randf_range(-bend, bend))
		var stride: float = (length / float(maxi(segments, 1))) * rng.randf_range(0.72, 1.20)
		current += heading.normalized() * stride
		current = _clamp_world(current, map_data)
		controls.append(current)

	var spine_tiles: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline(controls)
	var selected := {}
	for index in range(spine_tiles.size()):
		var point: Vector2i = spine_tiles[index]
		var t: float = float(index) / maxf(1.0, float(spine_tiles.size() - 1))
		var width: float = base_width * (0.78 + (sin(t * PI) * 0.34) + rng.randf_range(-0.12, 0.12))
		_stamp_disc(selected, point, width, map_data)

	selected = _roughen_mass(
		selected,
		float(spec.get("jitter", 0.16)),
		map_data,
		int(anchor.x * 17.0 + anchor.y * 23.0),
		blocker_type
	)
	var points: Array[Vector2i] = []
	points.assign(selected.keys())
	return points

func _generate_metaball_mass(
	map_data: MapData,
	anchor: Vector2,
	center: Vector2,
	spec: Dictionary,
	rng: RandomNumberGenerator,
	blocker_type: int
) -> Array[Vector2i]:
	var blobs_min: int = int(spec.get("blob_count_min", 2))
	var blobs_max: int = max(blobs_min, int(spec.get("blob_count_max", 5)))
	var nuclei_count: int = rng.randi_range(blobs_min, blobs_max)
	var radius_min: float = float(spec.get("radius_min", 4.0)) * float(spec.get("size_bias", 1.0))
	var radius_max: float = float(spec.get("radius_max", 9.0)) * float(spec.get("size_bias", 1.0))
	var center_bias: float = clampf(float(spec.get("aggression", 0.5)), 0.0, 1.0)
	var cluster_radius: float = lerpf(radius_max * 1.65, radius_max * 1.05, center_bias)

	var nuclei: Array[Dictionary] = []
	for _i in range(nuclei_count):
		var random_dir: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		var to_center: Vector2 = (center - anchor).normalized()
		if to_center == Vector2.ZERO:
			to_center = random_dir
		var dir: Vector2 = random_dir.slerp(to_center, center_bias * rng.randf_range(0.2, 0.6))
		var distance: float = rng.randf_range(0.0, cluster_radius)
		var nucleus_center: Vector2 = _clamp_world(anchor + dir * distance, map_data)
		var radius: float = rng.randf_range(radius_min, radius_max)
		nuclei.append({
			"center": nucleus_center,
			"radius": radius,
		})

	var selected := {}
	for nucleus in nuclei:
		var nucleus_center: Vector2 = Vector2(nucleus["center"])
		var nucleus_radius: float = float(nucleus["radius"])
		_stamp_disc(selected, Vector2i(roundi(nucleus_center.x), roundi(nucleus_center.y)), nucleus_radius, map_data)

	var allow_disconnected_clusters: bool = bool(spec.get("allow_disconnected_clusters", false))
	var connect_nuclei_chance: float = clampf(float(spec.get("connect_nuclei_chance", 1.0)), 0.0, 1.0)
	var max_links: int = int(spec.get("max_links", nuclei.size() - 1))
	if max_links < 0:
		max_links = 0
	var links_used: int = 0
	if connect_nuclei_chance > 0.0 and max_links > 0:
		var link_candidates: Array[Dictionary] = []
		for i in range(nuclei.size()):
			for j in range(i + 1, nuclei.size()):
				var first_center: Vector2 = Vector2(nuclei[i]["center"])
				var second_center: Vector2 = Vector2(nuclei[j]["center"])
				link_candidates.append({
					"from": i,
					"to": j,
					"distance": first_center.distance_to(second_center),
				})
		link_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("distance", 999999.0)) < float(b.get("distance", 999999.0))
		)
		for link in link_candidates:
			if links_used >= max_links:
				break
			if rng.randf() > connect_nuclei_chance:
				continue
			var from_index: int = int(link.get("from", 0))
			var to_index: int = int(link.get("to", 0))
			var from_center: Vector2 = Vector2(nuclei[from_index]["center"])
			var to_center: Vector2 = Vector2(nuclei[to_index]["center"])
			var link_radius: float = minf(float(nuclei[from_index]["radius"]), float(nuclei[to_index]["radius"])) * rng.randf_range(0.38, 0.62)
			var link_line: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([from_center, to_center])
			for point in link_line:
				_stamp_disc(selected, point, link_radius, map_data)
			links_used += 1
	if not allow_disconnected_clusters and nuclei.size() > 1 and links_used == 0:
		var fallback_from: Vector2 = Vector2(nuclei[0]["center"])
		var fallback_to: Vector2 = Vector2(nuclei[1]["center"])
		var fallback_radius: float = minf(float(nuclei[0]["radius"]), float(nuclei[1]["radius"])) * 0.5
		var fallback_line: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([fallback_from, fallback_to])
		for point in fallback_line:
			_stamp_disc(selected, point, fallback_radius, map_data)

	selected = _roughen_mass(
		selected,
		float(spec.get("jitter", 0.24)),
		map_data,
		int(anchor.x * 29.0 + anchor.y * 31.0),
		blocker_type
	)
	var points: Array[Vector2i] = []
	points.assign(selected.keys())
	return points

func _build_keep_corridor_mask(map_data: MapData, composition: Dictionary, config) -> Dictionary:
	var mask := {}
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var center_point := Vector2i(roundi(center.x), roundi(center.y))
	var corridor_width: int = int(composition.get("corridor_width", maxi(config.minimum_path_width + 1, 3)))
	var corridor_buffer: int = int(composition.get("corridor_buffer", 1))
	var corridor_radius: int = maxi(1, int(floor(float(corridor_width) * 0.5)) + corridor_buffer)

	for entry_spec in composition.get("entries", []):
		var entry_point: Vector2i = entry_spec.get("point", Vector2i.ZERO)
		var axis_line: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([Vector2(entry_point), center])
		for point in axis_line:
			_stamp_mask(mask, point, corridor_radius, map_data)

	_stamp_mask(mask, center_point, corridor_radius + 2, map_data)
	for entry_spec in composition.get("entries", []):
		var entry_point: Vector2i = entry_spec.get("point", Vector2i.ZERO)
		_stamp_mask(mask, entry_point, corridor_radius + 1, map_data)
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
		if tile.is_water:
			continue
		selected[point] = true
	var result: Array[Vector2i] = []
	result.assign(selected.keys())
	return result

func _build_fringe_points(
	map_data: MapData,
	core_points: Array[Vector2i],
	edge_band: int,
	keep_corridor_mask: Dictionary
) -> Array[Vector2i]:
	var core := {}
	for point in core_points:
		core[point] = true
	var fringe := {}
	var frontier: Array[Vector2i] = core_points.duplicate()
	for _layer in range(edge_band):
		var next_frontier: Array[Vector2i] = []
		for point in frontier:
			for neighbor in GenerationUtilsClass.cardinal_neighbors(point):
				if core.has(neighbor) or fringe.has(neighbor):
					continue
				if keep_corridor_mask.has(neighbor):
					continue
				if not map_data.is_in_bounds(neighbor.x, neighbor.y):
					continue
				var tile = map_data.get_tile(neighbor.x, neighbor.y)
				if tile == null:
					continue
				if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
					continue
				if tile.is_water or tile.is_road:
					continue
				fringe[neighbor] = true
				next_frontier.append(neighbor)
		frontier = next_frontier
		if frontier.is_empty():
			break
	var result: Array[Vector2i] = []
	result.assign(fringe.keys())
	return result

func _stamp_core_tiles(map_data: MapData, points: Array[Vector2i], region_id: int, blocker_type: int) -> void:
	for point in points:
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
			continue
		tile.base_terrain_type = _terrain_for_blocker(blocker_type)
		tile.terrain_type = _terrain_for_blocker(blocker_type)
		tile.blocker_type = blocker_type
		tile.region_id = region_id
		tile.region_type = MapTypes.RegionType.BLOCKER_MASS
		tile.is_walkable = false
		tile.is_blocked = true
		tile.is_buildable = false
		tile.is_future_wallable = false
		tile.is_water = false
		tile.walk_cost = 999.0
		tile.resource_tag = _resource_for_blocker(blocker_type)
		tile.debug_tags.clear()
		tile.debug_tags.append("major_blocker")
		tile.debug_tags.append("blocker_core")
		tile.debug_tags.append(MapTypes.blocker_name(blocker_type))
		if blocker_type == MapTypes.BlockerType.FOREST:
			tile.debug_tags.append("forest_core")
		elif blocker_type == MapTypes.BlockerType.ROCK:
			tile.debug_tags.append("rock_core")

func _stamp_fringe_tiles(map_data: MapData, points: Array[Vector2i], region_id: int, blocker_type: int) -> void:
	for point in points:
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
			continue
		if tile.is_blocked:
			continue
		tile.region_id = region_id
		tile.region_type = MapTypes.RegionType.BLOCKER_MASS
		tile.is_buildable = false
		tile.is_future_wallable = false
		tile.is_water = false
		match blocker_type:
			MapTypes.BlockerType.FOREST:
				tile.base_terrain_type = MapTypes.TerrainType.FOREST
				tile.terrain_type = MapTypes.TerrainType.FOREST
				tile.blocker_type = MapTypes.BlockerType.FOREST
				tile.resource_tag = MapTypes.ResourceTag.WOOD
				tile.is_walkable = true
				tile.is_blocked = false
				tile.walk_cost = 2.35
				if not tile.debug_tags.has("forest_fringe"):
					tile.debug_tags.append("forest_fringe")
			MapTypes.BlockerType.ROCK:
				tile.base_terrain_type = MapTypes.TerrainType.GROUND
				tile.terrain_type = MapTypes.TerrainType.GROUND
				tile.blocker_type = MapTypes.BlockerType.NONE
				tile.resource_tag = MapTypes.ResourceTag.STONE
				tile.transition_type = MapTypes.TransitionType.BLOCKER_EDGE
				tile.is_walkable = true
				tile.is_blocked = false
				tile.walk_cost = 4.40
				if not tile.debug_tags.has("rock_edge"):
					tile.debug_tags.append("rock_edge")
			_:
				tile.base_terrain_type = _terrain_for_blocker(blocker_type)
				tile.terrain_type = _terrain_for_blocker(blocker_type)
				tile.blocker_type = blocker_type
				tile.resource_tag = _resource_for_blocker(blocker_type)
				tile.is_walkable = false
				tile.is_blocked = false
				tile.walk_cost = 6.0
		if not tile.debug_tags.has("obstacle_fringe"):
			tile.debug_tags.append("obstacle_fringe")

func _terrain_for_blocker(blocker_type: int) -> int:
	match blocker_type:
		MapTypes.BlockerType.FOREST:
			return MapTypes.TerrainType.FOREST
		MapTypes.BlockerType.ROCK:
			return MapTypes.TerrainType.ROCK
		MapTypes.BlockerType.RAVINE:
			return MapTypes.TerrainType.RAVINE
		_:
			return MapTypes.TerrainType.BLOCKER

func _resource_for_blocker(blocker_type: int) -> int:
	match blocker_type:
		MapTypes.BlockerType.FOREST:
			return MapTypes.ResourceTag.WOOD
		MapTypes.BlockerType.ROCK, MapTypes.BlockerType.RAVINE:
			return MapTypes.ResourceTag.STONE
		_:
			return MapTypes.ResourceTag.NONE

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
			if Vector2(point).distance_to(Vector2(center)) <= float(r) + 0.35:
				mask[point] = true

func _roughen_mass(selected: Dictionary, jitter: float, map_data: MapData, salt: int, blocker_type: int) -> Dictionary:
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
		if noise < jitter * 0.52:
			result.erase(point)
	var points: Array[Vector2i] = []
	points.assign(result.keys())
	var smooth_iterations: int = 2
	var smooth_neighbors: int = 2
	match blocker_type:
		MapTypes.BlockerType.ROCK:
			smooth_iterations = 1
			smooth_neighbors = 3
		MapTypes.BlockerType.RAVINE:
			smooth_iterations = 1
			smooth_neighbors = 2
	var smoothed: Array[Vector2i] = GenerationUtilsClass.smooth_points(map_data, points, smooth_iterations, smooth_neighbors)
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

func _extract_components_above_size(points: Array[Vector2i], min_size: int) -> Array[Vector2i]:
	if points.is_empty():
		return []
	var selected := {}
	for point in points:
		selected[point] = true
	var visited := {}
	var preserved := {}
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
		if component.size() < min_size:
			continue
		for item in component:
			preserved[item] = true
	var output: Array[Vector2i] = []
	output.assign(preserved.keys())
	return output

func _clamp_world(point: Vector2, map_data: MapData) -> Vector2:
	return Vector2(
		clampf(point.x, 1.0, float(map_data.width - 2)),
		clampf(point.y, 1.0, float(map_data.height - 2))
	)
