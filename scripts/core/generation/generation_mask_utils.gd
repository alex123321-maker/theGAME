extends RefCounted
class_name GenerationMaskUtils

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")

static func stamp_disc(selected: Dictionary, center: Vector2i, radius: float, map_data: MapData) -> void:
	var r: int = ceili(maxf(1.0, radius))
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			if not map_data.is_in_bounds(x, y):
				continue
			var point := Vector2i(x, y)
			if Vector2(point).distance_to(Vector2(center)) <= radius:
				selected[point] = true

static func stamp_mask(mask: Dictionary, center: Vector2i, radius: int, map_data: MapData, padding: float = 0.2) -> void:
	var r: int = maxi(radius, 0)
	for y in range(center.y - r, center.y + r + 1):
		for x in range(center.x - r, center.x + r + 1):
			if not map_data.is_in_bounds(x, y):
				continue
			var point := Vector2i(x, y)
			if Vector2(point).distance_to(Vector2(center)) <= float(r) + padding:
				mask[point] = true

static func points_from_lookup(points: Dictionary) -> Array[Vector2i]:
	var output: Array[Vector2i] = []
	for key in points.keys():
		output.append(key)
	return output

static func extract_largest_component(points: Array[Vector2i]) -> Array[Vector2i]:
	if points.is_empty():
		return []
	var selected := {}
	for point in points:
		selected[point] = true
	var visited := {}
	var best_component: Array[Vector2i] = []
	for point in points:
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

static func extract_components_above_size(points: Array[Vector2i], min_size: int) -> Array[Vector2i]:
	if points.is_empty():
		return []
	var selected := {}
	for point in points:
		selected[point] = true
	var visited := {}
	var preserved := {}
	for point in points:
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
	return points_from_lookup(preserved)

static func build_corridor_mask(
	map_data: MapData,
	composition: Dictionary,
	radius: int,
	include_entry_axes: bool,
	entry_radius_bonus: int = 0,
	center_radius_bonus: int = 0
) -> Dictionary:
	var mask := {}
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var center_point := Vector2i(roundi(center.x), roundi(center.y))
	for entry_spec in composition.get("entries", []):
		var entry_point: Vector2i = entry_spec.get("point", Vector2i.ZERO)
		if include_entry_axes:
			var samples: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([Vector2(entry_point), center])
			for sample in samples:
				stamp_mask(mask, sample, radius, map_data)
		stamp_mask(mask, entry_point, radius + entry_radius_bonus, map_data)
	stamp_mask(mask, center_point, radius + center_radius_bonus, map_data)
	return mask
