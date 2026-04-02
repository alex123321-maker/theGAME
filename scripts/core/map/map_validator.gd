extends RefCounted
class_name MapValidator

const GameConfigData = preload("res://autoload/game_config.gd")

func validate(map_data: MapData) -> Dictionary:
	var errors: Array[String] = []
	var metrics := {
		"entry_count": map_data.entry_points.size(),
		"central_zone_tile_count": map_data.central_zone_tiles.size(),
		"reachable_entries": 0,
		"buildable_tiles": 0,
		"buildable_in_center_pct": 0.0,
	}

	if map_data.entry_points.size() < GameConfigData.MIN_ENTRY_COUNT:
		errors.append("entry_count_below_minimum")

	if map_data.central_zone_tiles.is_empty():
		errors.append("missing_central_zone")

	for tile in map_data.tiles:
		if tile.is_buildable:
			metrics["buildable_tiles"] += 1

	var center_targets := {}
	for point in map_data.central_zone_tiles:
		center_targets[point] = true

	if not map_data.central_zone_tiles.is_empty():
		var buildable_center_count: int = 0
		for center_point in map_data.central_zone_tiles:
			var center_tile = map_data.get_tile(center_point.x, center_point.y)
			if center_tile != null and center_tile.is_buildable:
				buildable_center_count += 1
		metrics["buildable_in_center_pct"] = (float(buildable_center_count) / float(map_data.central_zone_tiles.size())) * 100.0

	for entry_point in map_data.entry_points:
		if _has_path_to_any_center(map_data, entry_point, center_targets):
			metrics["reachable_entries"] += 1

	if metrics["reachable_entries"] < min(GameConfigData.MIN_ENTRY_COUNT, map_data.entry_points.size()):
		errors.append("insufficient_reachable_entries")

	var report := {
		"ok": errors.is_empty(),
		"errors": errors,
		"metrics": metrics,
	}
	return report

func _has_path_to_any_center(
	map_data: MapData,
	start: Vector2i,
	center_targets: Dictionary
) -> bool:
	var frontier: Array[Vector2i] = [start]
	var visited := {start: true}
	var directions: Array[Vector2i] = [
		Vector2i.LEFT,
		Vector2i.RIGHT,
		Vector2i.UP,
		Vector2i.DOWN,
	]

	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if center_targets.has(current):
			return true

		for direction in directions:
			var next: Vector2i = current + direction
			if visited.has(next):
				continue
			if not map_data.is_in_bounds(next.x, next.y):
				continue

			var tile = map_data.get_tile(next.x, next.y)
			if tile == null:
				continue
			if GameConfigData.BLOCKED_TERRAINS.has(tile.terrain_type):
				continue

			visited[next] = true
			frontier.push_back(next)

	return false
