extends RefCounted
class_name ExpressivenessValidator

func evaluate(map_data: MapData) -> Dictionary:
	var metrics := {
		"obstacle_mass_count": 0,
		"obstacle_area_min": 0,
		"obstacle_area_max": 0,
		"obstacle_area_avg": 0.0,
		"obstacle_area_cv": 0.0,
		"narrow_passage_count": 0,
		"passage_width_histogram": {"1": 0, "2": 0, "3": 0, "4+": 0},
		"mean_entry_path_curviness": 0.0,
		"mean_entry_path_length": 0.0,
		"quadrant_asymmetry": 0.0,
		"obstacle_perimeter_area_ratio": 0.0,
		"flank_count": 0,
	}
	var warnings: Array[String] = []
	var errors: Array[String] = []

	var obstacle_components: Array = _obstacle_components(map_data)
	metrics["obstacle_mass_count"] = obstacle_components.size()
	var area_values: Array[int] = []
	for component in obstacle_components:
		area_values.append(component.size())
	if not area_values.is_empty():
		metrics["obstacle_area_min"] = _array_min(area_values)
		metrics["obstacle_area_max"] = _array_max(area_values)
		metrics["obstacle_area_avg"] = _array_mean(area_values)
		metrics["obstacle_area_cv"] = _array_coefficient_variation(area_values)

	metrics["obstacle_perimeter_area_ratio"] = _obstacle_perimeter_area_ratio(map_data)
	metrics["quadrant_asymmetry"] = _quadrant_asymmetry(map_data)
	metrics["flank_count"] = _flank_count(map_data)
	metrics["passage_width_histogram"] = _passage_width_histogram(map_data)
	metrics["narrow_passage_count"] = _narrow_passage_count(map_data)

	var entry_path_report: Dictionary = _entry_path_metrics(map_data)
	metrics["mean_entry_path_curviness"] = entry_path_report.get("mean_curviness", 0.0)
	metrics["mean_entry_path_length"] = entry_path_report.get("mean_length", 0.0)

	if int(metrics["obstacle_mass_count"]) == 0:
		errors.append("no_obstacle_masses")
	if int(metrics["obstacle_mass_count"]) < 2:
		warnings.append("low_obstacle_mass_count")
	if int(metrics["narrow_passage_count"]) < 2:
		warnings.append("low_narrow_passage_count")
	if float(metrics["quadrant_asymmetry"]) < 0.08:
		warnings.append("map_too_symmetric")
	if float(metrics["mean_entry_path_curviness"]) < 1.08:
		warnings.append("entry_paths_too_straight")
	if float(metrics["obstacle_perimeter_area_ratio"]) < 0.34:
		warnings.append("obstacle_silhouette_too_soft")
	if int(metrics["flank_count"]) < 2:
		warnings.append("insufficient_flank_diversity")
	if warnings.size() >= 5:
		errors.append("expressiveness_below_threshold")

	return {
		"metrics": metrics,
		"warnings": warnings,
		"errors": errors,
	}

func _obstacle_components(map_data: MapData) -> Array:
	var visited := {}
	var components: Array = []
	for tile in map_data.tiles:
		var point := Vector2i(tile.x, tile.y)
		if visited.has(point):
			continue
		if not _is_obstacle_tile(tile):
			continue
		var component: Array[Vector2i] = []
		var frontier: Array[Vector2i] = [point]
		visited[point] = true
		while not frontier.is_empty():
			var current: Vector2i = frontier.pop_front()
			component.append(current)
			for neighbor in [current + Vector2i.LEFT, current + Vector2i.RIGHT, current + Vector2i.UP, current + Vector2i.DOWN]:
				if visited.has(neighbor):
					continue
				if not map_data.is_in_bounds(neighbor.x, neighbor.y):
					continue
				var next_tile = map_data.get_tile(neighbor.x, neighbor.y)
				if next_tile == null or not _is_obstacle_tile(next_tile):
					continue
				visited[neighbor] = true
				frontier.append(neighbor)
		components.append(component)
	return components

func _obstacle_perimeter_area_ratio(map_data: MapData) -> float:
	var area: int = 0
	var perimeter: int = 0
	for tile in map_data.tiles:
		if not _is_obstacle_tile(tile):
			continue
		area += 1
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var nx: int = tile.x + direction.x
			var ny: int = tile.y + direction.y
			if not map_data.is_in_bounds(nx, ny):
				perimeter += 1
				continue
			var neighbor = map_data.get_tile(nx, ny)
			if neighbor == null or not _is_obstacle_tile(neighbor):
				perimeter += 1
	return 0.0 if area <= 0 else float(perimeter) / float(area)

func _quadrant_asymmetry(map_data: MapData) -> float:
	var mid_x: int = map_data.width / 2
	var mid_y: int = map_data.height / 2
	var quadrants: Array[int] = [0, 0, 0, 0]
	var total: int = 0
	for tile in map_data.tiles:
		if not _is_obstacle_tile(tile):
			continue
		total += 1
		var right: bool = tile.x >= mid_x
		var bottom: bool = tile.y >= mid_y
		var index: int = 0
		if right and not bottom:
			index = 1
		elif not right and bottom:
			index = 2
		elif right and bottom:
			index = 3
		quadrants[index] += 1
	if total <= 0:
		return 0.0
	var diag_a: int = absi(quadrants[0] - quadrants[3])
	var diag_b: int = absi(quadrants[1] - quadrants[2])
	return float(diag_a + diag_b) / float(total)

func _flank_count(map_data: MapData) -> int:
	if map_data.central_zone_tiles.is_empty():
		return 0
	var average := Vector2.ZERO
	for point in map_data.central_zone_tiles:
		average += Vector2(point)
	average /= float(map_data.central_zone_tiles.size())
	var center := Vector2i(roundi(average.x), roundi(average.y))
	var radius: int = maxi(6, mini(map_data.width, map_data.height) / 5)
	var totals: Array[int] = [0, 0, 0, 0]
	var open_tiles: Array[int] = [0, 0, 0, 0]
	for y in range(center.y - radius, center.y + radius + 1):
		for x in range(center.x - radius, center.x + radius + 1):
			if not map_data.is_in_bounds(x, y):
				continue
			var point := Vector2i(x, y)
			if point.distance_to(center) > radius:
				continue
			var quadrant: int = 0
			if x >= center.x and y < center.y:
				quadrant = 1
			elif x < center.x and y >= center.y:
				quadrant = 2
			elif x >= center.x and y >= center.y:
				quadrant = 3
			totals[quadrant] += 1
			var tile = map_data.get_tile(x, y)
			if tile != null and tile.is_walkable and not tile.is_water and not _is_obstacle_tile(tile):
				open_tiles[quadrant] += 1
	var flank_count: int = 0
	for index in range(4):
		if totals[index] <= 0:
			continue
		var open_ratio: float = float(open_tiles[index]) / float(totals[index])
		if open_ratio >= 0.52:
			flank_count += 1
	return flank_count

func _passage_width_histogram(map_data: MapData) -> Dictionary:
	var histogram := {"1": 0, "2": 0, "3": 0, "4+": 0}
	for tile in map_data.tiles:
		if not tile.is_walkable or tile.is_water:
			continue
		var width: int = _local_passage_width(map_data, Vector2i(tile.x, tile.y), 5)
		if width <= 1:
			histogram["1"] += 1
		elif width == 2:
			histogram["2"] += 1
		elif width == 3:
			histogram["3"] += 1
		else:
			histogram["4+"] += 1
	return histogram

func _narrow_passage_count(map_data: MapData) -> int:
	var count: int = 0
	for tile in map_data.tiles:
		if not tile.is_walkable or tile.is_water or tile.is_road:
			continue
		var left_blocked: bool = _is_obstacle_at(map_data, tile.x - 1, tile.y)
		var right_blocked: bool = _is_obstacle_at(map_data, tile.x + 1, tile.y)
		var up_blocked: bool = _is_obstacle_at(map_data, tile.x, tile.y - 1)
		var down_blocked: bool = _is_obstacle_at(map_data, tile.x, tile.y + 1)
		var corridor_like: bool = (left_blocked and right_blocked and not (up_blocked and down_blocked)) \
			or (up_blocked and down_blocked and not (left_blocked and right_blocked))
		if not corridor_like:
			continue
		if _local_passage_width(map_data, Vector2i(tile.x, tile.y), 4) <= 2:
			count += 1
	return count

func _entry_path_metrics(map_data: MapData) -> Dictionary:
	if map_data.entry_points.is_empty() or map_data.central_zone_tiles.is_empty():
		return {"mean_curviness": 0.0, "mean_length": 0.0}
	var center_targets := {}
	for point in map_data.central_zone_tiles:
		center_targets[point] = true
	var total_curviness: float = 0.0
	var total_length: float = 0.0
	var count: int = 0
	for entry in map_data.entry_points:
		var path_length: int = _shortest_path_length(map_data, entry, center_targets)
		if path_length <= 0:
			continue
		var manhattan: int = _closest_center_manhattan(entry, map_data.central_zone_tiles)
		var curviness: float = float(path_length) / maxf(float(manhattan), 1.0)
		total_curviness += curviness
		total_length += float(path_length)
		count += 1
	if count <= 0:
		return {"mean_curviness": 0.0, "mean_length": 0.0}
	return {
		"mean_curviness": total_curviness / float(count),
		"mean_length": total_length / float(count),
	}

func _shortest_path_length(map_data: MapData, start: Vector2i, center_targets: Dictionary) -> int:
	var frontier: Array[Vector2i] = [start]
	var distance := {start: 0}
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if center_targets.has(current):
			return int(distance[current])
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + direction
			if distance.has(next):
				continue
			if not map_data.is_in_bounds(next.x, next.y):
				continue
			var tile = map_data.get_tile(next.x, next.y)
			if tile == null or not tile.is_walkable or tile.is_water:
				continue
			distance[next] = int(distance[current]) + 1
			frontier.append(next)
	return -1

func _closest_center_manhattan(entry: Vector2i, center_points: Array[Vector2i]) -> int:
	var best: int = 1_000_000
	for point in center_points:
		var distance: int = absi(entry.x - point.x) + absi(entry.y - point.y)
		if distance < best:
			best = distance
	return max(1, best)

func _local_passage_width(map_data: MapData, point: Vector2i, max_probe: int) -> int:
	var horizontal: int = 1 + _walkable_span(map_data, point, Vector2i.LEFT, max_probe) + _walkable_span(map_data, point, Vector2i.RIGHT, max_probe)
	var vertical: int = 1 + _walkable_span(map_data, point, Vector2i.UP, max_probe) + _walkable_span(map_data, point, Vector2i.DOWN, max_probe)
	return mini(horizontal, vertical)

func _walkable_span(map_data: MapData, origin: Vector2i, direction: Vector2i, max_probe: int) -> int:
	var span: int = 0
	var probe: Vector2i = origin + direction
	while span < max_probe and map_data.is_in_bounds(probe.x, probe.y):
		var tile = map_data.get_tile(probe.x, probe.y)
		if tile == null or not tile.is_walkable or tile.is_water:
			break
		if _is_obstacle_tile(tile):
			break
		span += 1
		probe += direction
	return span

func _is_obstacle_at(map_data: MapData, x: int, y: int) -> bool:
	if not map_data.is_in_bounds(x, y):
		return true
	var tile = map_data.get_tile(x, y)
	return _is_obstacle_tile(tile)

func _is_obstacle_tile(tile) -> bool:
	if tile == null:
		return false
	if tile.is_water or tile.is_blocked:
		return true
	if tile.terrain_type == MapTypes.TerrainType.FOREST or tile.terrain_type == MapTypes.TerrainType.ROCK:
		return true
	if tile.base_terrain_type == MapTypes.TerrainType.FOREST or tile.base_terrain_type == MapTypes.TerrainType.ROCK:
		return true
	return false

func _array_min(values: Array[int]) -> int:
	var result: int = values[0]
	for value in values:
		result = mini(result, value)
	return result

func _array_max(values: Array[int]) -> int:
	var result: int = values[0]
	for value in values:
		result = maxi(result, value)
	return result

func _array_mean(values: Array[int]) -> float:
	var total: int = 0
	for value in values:
		total += value
	return float(total) / maxf(1.0, float(values.size()))

func _array_coefficient_variation(values: Array[int]) -> float:
	if values.size() <= 1:
		return 0.0
	var mean: float = _array_mean(values)
	if mean <= 0.001:
		return 0.0
	var variance: float = 0.0
	for value in values:
		var diff: float = float(value) - mean
		variance += diff * diff
	variance /= float(values.size())
	return sqrt(variance) / mean
