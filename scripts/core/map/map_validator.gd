extends RefCounted
class_name MapValidator

const GameConfigData = preload("res://autoload/game_config.gd")
const ExpressivenessValidatorClass = preload("res://scripts/core/map/validators/expressiveness_validator.gd")

var _expressiveness_validator := ExpressivenessValidatorClass.new()

func validate(map_data: MapData) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var stages: Array[Dictionary] = []
	var metrics := {
		"entry_count": map_data.entry_points.size(),
		"central_zone_tile_count": map_data.central_zone_tiles.size(),
		"reachable_entries": 0,
		"connected_center_tiles": 0,
		"buildable_tiles": 0,
		"buildable_in_center_pct": 0.0,
		"road_tile_count": 0,
		"bridge_tile_count": 0,
		"water_tile_count": 0,
		"blocker_tile_count": 0,
	}

	if map_data.entry_points.size() < GameConfigData.MIN_ENTRY_COUNT:
		errors.append("entry_count_below_minimum")

	if map_data.central_zone_tiles.is_empty():
		errors.append("missing_central_zone")

	for tile in map_data.tiles:
		if tile.is_buildable:
			metrics["buildable_tiles"] += 1
		if tile.is_road:
			metrics["road_tile_count"] += 1
		if tile.is_bridge:
			metrics["bridge_tile_count"] += 1
		if tile.is_water:
			metrics["water_tile_count"] += 1
		if tile.is_blocked:
			metrics["blocker_tile_count"] += 1

	var center_targets := {}
	for point in map_data.central_zone_tiles:
		center_targets[point] = true

	if not map_data.central_zone_tiles.is_empty():
		metrics["connected_center_tiles"] = _count_connected_center_tiles(map_data, map_data.central_zone_tiles[0], center_targets)
		if int(metrics["connected_center_tiles"]) != map_data.central_zone_tiles.size():
			errors.append("central_zone_disconnected")
		stages.append({
			"stage": "validate_center_connectivity",
			"ok": int(metrics["connected_center_tiles"]) == map_data.central_zone_tiles.size(),
			"reason": "" if int(metrics["connected_center_tiles"]) == map_data.central_zone_tiles.size() else "center_zone_is_split",
		})

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
	stages.append({
		"stage": "validate_entry_paths",
		"ok": metrics["reachable_entries"] >= min(GameConfigData.MIN_ENTRY_COUNT, map_data.entry_points.size()),
		"reason": "" if metrics["reachable_entries"] >= min(GameConfigData.MIN_ENTRY_COUNT, map_data.entry_points.size()) else "not_all_entries_reach_center",
	})

	if metrics["buildable_tiles"] < GameConfigData.DEFAULT_MIN_CENTER_AREA * 0.45:
		errors.append("buildable_area_below_target")
	stages.append({
		"stage": "validate_buildable_area",
		"ok": metrics["buildable_tiles"] >= GameConfigData.DEFAULT_MIN_CENTER_AREA * 0.45,
		"reason": "" if metrics["buildable_tiles"] >= GameConfigData.DEFAULT_MIN_CENTER_AREA * 0.45 else "buildable_area_too_small",
	})

	if metrics["road_tile_count"] <= 0:
		errors.append("missing_roads")
	var expects_water: bool = false
	for region in map_data.regions:
		if int(region.get("type", MapTypes.RegionType.NONE)) == MapTypes.RegionType.WATER_REGION:
			expects_water = true
			break
	if expects_water and metrics["water_tile_count"] <= 0:
		errors.append("missing_water_region")

	var expressiveness_report: Dictionary = _expressiveness_validator.evaluate(map_data)
	var expressiveness_metrics: Dictionary = expressiveness_report.get("metrics", {})
	var expressiveness_errors: Array = expressiveness_report.get("errors", [])
	for key in expressiveness_metrics.keys():
		metrics[key] = expressiveness_metrics[key]
	for warning in expressiveness_report.get("warnings", []):
		warnings.append(String(warning))
	for issue in expressiveness_errors:
		errors.append(String(issue))
	stages.append({
		"stage": "validate_expressiveness",
		"ok": expressiveness_errors.is_empty(),
		"reason": "" if expressiveness_errors.is_empty() else "expressiveness_below_threshold",
	})

	var report := {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"metrics": metrics,
		"stages": stages,
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
			if not tile.is_walkable:
				continue

			visited[next] = true
			frontier.push_back(next)

	return false

func _count_connected_center_tiles(map_data: MapData, start: Vector2i, center_targets: Dictionary) -> int:
	var frontier: Array[Vector2i] = [start]
	var visited := {start: true}
	var count: int = 0
	while not frontier.is_empty():
		var current: Vector2i = frontier.pop_front()
		if not center_targets.has(current):
			continue
		count += 1
		for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = current + direction
			if visited.has(next):
				continue
			if not center_targets.has(next):
				continue
			visited[next] = true
			frontier.push_back(next)
	return count
