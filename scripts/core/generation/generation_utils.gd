extends RefCounted
class_name GenerationUtils

static func hash2d(x: int, y: int, salt: int) -> int:
	return abs(int((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)))

static func point_on_side(side: String, map_width: int, map_height: int, offset_ratio: float, padding: int = 2) -> Vector2i:
	var x_min: int = padding
	var y_min: int = padding
	var x_max: int = max(padding, map_width - 1 - padding)
	var y_max: int = max(padding, map_height - 1 - padding)
	var t: float = clampf(offset_ratio, 0.1, 0.9)
	match side:
		"north":
			return Vector2i(roundi(lerpf(float(x_min), float(x_max), t)), 0)
		"south":
			return Vector2i(roundi(lerpf(float(x_min), float(x_max), t)), map_height - 1)
		"east":
			return Vector2i(map_width - 1, roundi(lerpf(float(y_min), float(y_max), t)))
		"west":
			return Vector2i(0, roundi(lerpf(float(y_min), float(y_max), t)))
		_:
			return Vector2i(map_width / 2, map_height / 2)

static func cardinal_neighbors(point: Vector2i) -> Array[Vector2i]:
	return [
		point + Vector2i.LEFT,
		point + Vector2i.RIGHT,
		point + Vector2i.UP,
		point + Vector2i.DOWN,
	]

static func fill_blob(
	map_data: MapData,
	center: Vector2,
	radius_x: float,
	radius_y: float,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var points: Array[Vector2i] = []
	var x_from: int = floori(center.x - radius_x - 2.0)
	var x_to: int = ceili(center.x + radius_x + 2.0)
	var y_from: int = floori(center.y - radius_y - 2.0)
	var y_to: int = ceili(center.y + radius_y + 2.0)
	for y in range(y_from, y_to + 1):
		for x in range(x_from, x_to + 1):
			if not map_data.is_in_bounds(x, y):
				continue
			var nx: float = (float(x) - center.x) / max(radius_x, 1.0)
			var ny: float = (float(y) - center.y) / max(radius_y, 1.0)
			var falloff: float = (nx * nx) + (ny * ny)
			var noise_hash: int = hash2d(x, y, int(center.x * 13.0) + int(center.y * 17.0)) % 1000
			var noise: float = float(noise_hash) / 1000.0
			var threshold: float = 1.0 + ((rng.randf() - 0.5) * 0.18) + ((noise - 0.5) * 0.22)
			if falloff <= threshold:
				var point := Vector2i(x, y)
				points.append(point)
	return points

static func smooth_points(map_data: MapData, points: Array[Vector2i], keep_min_neighbors: int = 2, grow_min_neighbors: int = 3) -> Array[Vector2i]:
	var selected := {}
	for point in points:
		selected[point] = true
	var result := selected.duplicate(true)
	for point in points:
		var count: int = 0
		for neighbor in cardinal_neighbors(point):
			if selected.has(neighbor):
				count += 1
		if count < keep_min_neighbors:
			result.erase(point)
	for point in points:
		for neighbor in cardinal_neighbors(point):
			if not map_data.is_in_bounds(neighbor.x, neighbor.y):
				continue
			var count: int = 0
			for inner_neighbor in cardinal_neighbors(neighbor):
				if selected.has(inner_neighbor):
					count += 1
			if count >= grow_min_neighbors:
				result[neighbor] = true
	var smoothed: Array[Vector2i] = []
	for key in result.keys():
		smoothed.append(key)
	return smoothed

static func rasterize_polyline(points: Array[Vector2]) -> Array[Vector2i]:
	var output: Array[Vector2i] = []
	if points.is_empty():
		return output
	for index in range(points.size() - 1):
		var start: Vector2 = points[index]
		var finish: Vector2 = points[index + 1]
		var distance_steps: int = maxi(1, int(round(start.distance_to(finish) * 1.75)))
		for step in range(distance_steps + 1):
			var t: float = float(step) / float(distance_steps)
			var sample: Vector2 = start.lerp(finish, t)
			var logical := Vector2i(roundi(sample.x), roundi(sample.y))
			if output.is_empty() or output[output.size() - 1] != logical:
				output.append(logical)
	return output
