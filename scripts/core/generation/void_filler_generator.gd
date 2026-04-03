extends RefCounted
class_name VoidFillerGenerator

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")

func generate(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	var keep_corridor_mask: Dictionary = _build_keep_corridor_mask(map_data, composition, config)
	var center_point: Vector2i = _center_point(composition, map_data)
	var center_dist: Array[int] = _distance_field(map_data, [center_point])
	var entry_dist: Array[int] = _distance_field(map_data, map_data.entry_points)
	var occupied_sources: Array[Vector2i] = _occupied_sources(map_data)
	var occupied_dist: Array[int] = _distance_field(map_data, occupied_sources)

	var peaks: Array[Dictionary] = _select_void_peaks(
		map_data,
		rng,
		keep_corridor_mask,
		center_dist,
		entry_dist,
		occupied_dist
	)
	if peaks.is_empty():
		return

	var region_id: int = 500
	for peak_data in peaks:
		var center: Vector2i = peak_data.get("point", Vector2i.ZERO)
		var style: String = _pick_filler_style(peak_data, rng)
		var points: Array[Vector2i] = _build_filler_shape(map_data, center, style, rng, keep_corridor_mask)
		if points.size() < 6:
			continue
		map_data.register_region(
			region_id,
			MapTypes.RegionType.BLOCKER_MASS,
			"void_filler_%d" % region_id,
			{
				"soft": true,
				"style": style,
				"tile_count": points.size(),
			}
		)
		_stamp_filler_tiles(map_data, points, region_id, style)
		region_id += 1

func _select_void_peaks(
	map_data: MapData,
	rng: RandomNumberGenerator,
	keep_corridor_mask: Dictionary,
	center_dist: Array[int],
	entry_dist: Array[int],
	occupied_dist: Array[int]
) -> Array[Dictionary]:
	var open_components: Array[Dictionary] = _largest_open_components(map_data, keep_corridor_mask, 6)
	if open_components.is_empty():
		return []

	var selected: Array[Dictionary] = []
	var target_count: int = rng.randi_range(3, 5)
	var focused_component_count: int = mini(2, open_components.size())
	for index in range(focused_component_count):
		var focused: Dictionary = open_components[index]
		var peak: Dictionary = _best_peak_in_component(
			map_data,
			focused.get("points", []),
			rng,
			keep_corridor_mask,
			center_dist,
			entry_dist,
			occupied_dist,
			selected
		)
		if peak.is_empty():
			continue
		selected.append(peak)

	for component in open_components:
		if selected.size() >= target_count:
			break
		var component_size: int = int(component.get("size", 0))
		var peaks_for_component: int = 2 if component_size > 320 else 1
		var placed_for_component: int = 0
		while placed_for_component < peaks_for_component and selected.size() < target_count:
			var next_peak: Dictionary = _best_peak_in_component(
				map_data,
				component.get("points", []),
				rng,
				keep_corridor_mask,
				center_dist,
				entry_dist,
				occupied_dist,
				selected
			)
			if next_peak.is_empty():
				break
			selected.append(next_peak)
			placed_for_component += 1

	return selected

func _largest_open_components(map_data: MapData, keep_corridor_mask: Dictionary, limit: int) -> Array[Dictionary]:
	var visited := {}
	var components: Array[Dictionary] = []
	for tile in map_data.tiles:
		var start := Vector2i(tile.x, tile.y)
		if visited.has(start):
			continue
		if keep_corridor_mask.has(start):
			continue
		if not _is_open_candidate_tile(tile):
			continue
		var component_points: Array[Vector2i] = []
		var frontier: Array[Vector2i] = [start]
		visited[start] = true
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_front()
			component_points.append(current)
			for neighbor in [current + Vector2i.LEFT, current + Vector2i.RIGHT, current + Vector2i.UP, current + Vector2i.DOWN]:
				if visited.has(neighbor):
					continue
				if not map_data.is_in_bounds(neighbor.x, neighbor.y):
					continue
				if keep_corridor_mask.has(neighbor):
					continue
				var next_tile = map_data.get_tile(neighbor.x, neighbor.y)
				if not _is_open_candidate_tile(next_tile):
					continue
				visited[neighbor] = true
				frontier.append(neighbor)
		if component_points.size() < 24:
			continue
		components.append({
			"size": component_points.size(),
			"points": component_points,
		})
	components.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("size", 0)) > int(b.get("size", 0))
	)
	if components.size() > limit:
		components.resize(limit)
	return components

func _best_peak_in_component(
	map_data: MapData,
	component_points: Array,
	rng: RandomNumberGenerator,
	keep_corridor_mask: Dictionary,
	center_dist: Array[int],
	entry_dist: Array[int],
	occupied_dist: Array[int],
	selected: Array[Dictionary]
) -> Dictionary:
	var best_peak: Dictionary = {}
	var best_score: float = -1_000_000.0
	for point_variant in component_points:
		var point: Vector2i = point_variant
		if keep_corridor_mask.has(point):
			continue
		if _near_selected_peak(point, selected, 14):
			continue
		if (point.x % 2) != 0 or (point.y % 2) != 0:
			continue
		var index: int = map_data.index_of(point.x, point.y)
		var d_center: int = center_dist[index]
		var d_entry: int = entry_dist[index]
		var d_occ: int = occupied_dist[index]
		if d_occ < 6:
			continue
		var score: float = (float(d_occ) * 0.56) + (float(d_center) * 0.27) + (float(d_entry) * 0.17)
		if point.x < 8 or point.y < 8 or point.x > map_data.width - 9 or point.y > map_data.height - 9:
			score *= 0.82
		score += rng.randf_range(-0.9, 0.9)
		if score > best_score:
			best_score = score
			best_peak = {
				"point": point,
				"score": score,
				"d_occ": d_occ,
			}
	if not best_peak.is_empty():
		return best_peak
	for point_variant in component_points:
		var point: Vector2i = point_variant
		if _near_selected_peak(point, selected, 12):
			continue
		var index: int = map_data.index_of(point.x, point.y)
		var d_occ: int = occupied_dist[index]
		if d_occ < 4:
			continue
		return {
			"point": point,
			"score": float(d_occ),
			"d_occ": d_occ,
		}
	return {}

func _build_filler_shape(
	map_data: MapData,
	center: Vector2i,
	style: String,
	rng: RandomNumberGenerator,
	keep_corridor_mask: Dictionary
) -> Array[Vector2i]:
	var selected := {}
	match style:
		"forest_patch":
			var nuclei: int = rng.randi_range(3, 5)
			for _i in range(nuclei):
				var direction: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
				var local_center: Vector2 = Vector2(center) + (direction * rng.randf_range(0.0, 7.2))
				var radius: float = rng.randf_range(2.6, 5.2)
				_stamp_disc(selected, Vector2i(roundi(local_center.x), roundi(local_center.y)), radius, map_data)
		"rock_scree":
			var direction: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
			var length: float = rng.randf_range(9.0, 16.0)
			var points: Array[Vector2] = [Vector2(center), Vector2(center) + direction * length]
			var spine: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline(points)
			for point in spine:
				_stamp_disc(selected, point, rng.randf_range(1.6, 2.8), map_data)
		_:
			_stamp_disc(selected, center, rng.randf_range(2.4, 5.2), map_data)
			for point in GenerationUtilsClass.cardinal_neighbors(center):
				if rng.randf() < 0.6:
					_stamp_disc(selected, point, rng.randf_range(1.6, 2.6), map_data)

	var points: Array[Vector2i] = []
	for key in selected.keys():
		var point: Vector2i = key
		if keep_corridor_mask.has(point):
			continue
		if not map_data.is_in_bounds(point.x, point.y):
			continue
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
			continue
		if tile.is_road or tile.is_water or tile.is_blocked:
			continue
		points.append(point)
	return points

func _stamp_filler_tiles(map_data: MapData, points: Array[Vector2i], region_id: int, style: String) -> void:
	for point in points:
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		tile.region_id = region_id
		tile.region_type = MapTypes.RegionType.BLOCKER_MASS
		tile.is_buildable = false
		tile.is_future_wallable = false
		tile.is_blocked = false
		tile.is_walkable = true
		match style:
			"forest_patch":
				tile.base_terrain_type = MapTypes.TerrainType.FOREST
				tile.terrain_type = MapTypes.TerrainType.FOREST
				tile.blocker_type = MapTypes.BlockerType.FOREST
				tile.resource_tag = MapTypes.ResourceTag.WOOD
				tile.walk_cost = 1.95
			"rock_scree":
				tile.base_terrain_type = MapTypes.TerrainType.ROCK
				tile.terrain_type = MapTypes.TerrainType.ROCK
				tile.blocker_type = MapTypes.BlockerType.ROCK
				tile.resource_tag = MapTypes.ResourceTag.STONE
				tile.walk_cost = 3.30
			_:
				tile.base_terrain_type = MapTypes.TerrainType.GROUND
				tile.terrain_type = MapTypes.TerrainType.GROUND
				tile.blocker_type = MapTypes.BlockerType.NONE
				tile.resource_tag = MapTypes.ResourceTag.NONE
				tile.walk_cost = 1.40
		if not tile.debug_tags.has("void_filler"):
			tile.debug_tags.append("void_filler")
		if not tile.debug_tags.has("soft_filler"):
			tile.debug_tags.append("soft_filler")
		if style == "forest_patch" and not tile.debug_tags.has("forest_fringe"):
			tile.debug_tags.append("forest_fringe")
		if style == "rock_scree" and not tile.debug_tags.has("rock_edge"):
			tile.debug_tags.append("rock_edge")

func _distance_field(map_data: MapData, sources: Array[Vector2i]) -> Array[int]:
	var size: int = map_data.width * map_data.height
	var distances: Array[int] = []
	distances.resize(size)
	for i in range(size):
		distances[i] = 1_000_000
	var frontier: Array[Vector2i] = []
	for source in sources:
		if not map_data.is_in_bounds(source.x, source.y):
			continue
		var index: int = map_data.index_of(source.x, source.y)
		if distances[index] == 0:
			continue
		distances[index] = 0
		frontier.append(source)
	if frontier.is_empty():
		for i in range(size):
			distances[i] = 64
		return distances

	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		var current_distance: int = distances[map_data.index_of(current.x, current.y)]
		for neighbor in [current + Vector2i.LEFT, current + Vector2i.RIGHT, current + Vector2i.UP, current + Vector2i.DOWN]:
			if not map_data.is_in_bounds(neighbor.x, neighbor.y):
				continue
			var next_index: int = map_data.index_of(neighbor.x, neighbor.y)
			if distances[next_index] <= current_distance + 1:
				continue
			distances[next_index] = current_distance + 1
			frontier.append(neighbor)
	return distances

func _occupied_sources(map_data: MapData) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	for tile in map_data.tiles:
		if tile.is_road or tile.is_water or tile.is_blocked:
			points.append(Vector2i(tile.x, tile.y))
			continue
		if tile.base_terrain_type == MapTypes.TerrainType.FOREST or tile.base_terrain_type == MapTypes.TerrainType.ROCK:
			points.append(Vector2i(tile.x, tile.y))
	return points

func _pick_filler_style(peak_data: Dictionary, rng: RandomNumberGenerator) -> String:
	var d_occ: int = int(peak_data.get("d_occ", 0))
	if d_occ > 12 and rng.randf() < 0.56:
		return "forest_patch"
	if rng.randf() < 0.50:
		return "rock_scree"
	return "rough_patch"

func _near_selected_peak(point: Vector2i, selected: Array[Dictionary], min_distance: int) -> bool:
	for item in selected:
		var other: Vector2i = item.get("point", Vector2i.ZERO)
		if point.distance_to(other) < float(min_distance):
			return true
	return false

func _build_keep_corridor_mask(map_data: MapData, composition: Dictionary, config) -> Dictionary:
	var mask := {}
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var center_point := Vector2i(roundi(center.x), roundi(center.y))
	var corridor_width: int = int(composition.get("corridor_width", maxi(config.minimum_path_width + 1, 3)))
	var corridor_radius: int = maxi(1, int(floor(float(corridor_width) * 0.5)) + 1)
	for entry_spec in composition.get("entries", []):
		var entry_point: Vector2i = entry_spec.get("point", Vector2i.ZERO)
		var samples: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([Vector2(entry_point), center])
		for sample in samples:
			_stamp_mask(mask, sample, corridor_radius, map_data)
		_stamp_mask(mask, entry_point, corridor_radius + 1, map_data)
	_stamp_mask(mask, center_point, corridor_radius + 1, map_data)
	return mask

func _center_point(composition: Dictionary, map_data: MapData) -> Vector2i:
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	return Vector2i(roundi(center.x), roundi(center.y))

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
	var r: int = maxi(0, radius)
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			if not map_data.is_in_bounds(x, y):
				continue
			var point := Vector2i(x, y)
			if Vector2(point).distance_to(Vector2(center)) <= float(r) + 0.2:
				mask[point] = true

func _is_open_candidate_tile(tile) -> bool:
	if tile == null:
		return false
	if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
		return false
	if tile.is_road or tile.is_water or tile.is_blocked:
		return false
	if tile.base_terrain_type == MapTypes.TerrainType.FOREST or tile.base_terrain_type == MapTypes.TerrainType.ROCK:
		return false
	return true
