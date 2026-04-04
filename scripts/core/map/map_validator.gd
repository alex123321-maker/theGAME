extends RefCounted
class_name MapValidator

const GameConfigData = preload("res://autoload/game_config.gd")
const ExpressivenessValidatorClass = preload("res://scripts/core/map/validators/expressiveness_validator.gd")

var _expressiveness_validator := ExpressivenessValidatorClass.new()

func validate(map_data: MapData, generation_config = null) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []
	var stages: Array[Dictionary] = []
	var expected_entry_count: int = generation_config.entry_count if generation_config != null else map_data.entry_points.size()
	var requested_center_area: int = generation_config.requested_center_area if generation_config != null else GameConfigData.DEFAULT_VILLAGE_TILE_COUNT
	var minimum_buildable_tiles: int = maxi(96, int(round(float(requested_center_area) * 0.38)))
	var metrics := {
		"requested_entry_count": expected_entry_count,
		"requested_center_area": requested_center_area,
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

	if map_data.entry_points.size() < expected_entry_count:
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

	if metrics["reachable_entries"] < min(expected_entry_count, map_data.entry_points.size()):
		errors.append("insufficient_reachable_entries")
	stages.append({
		"stage": "validate_entry_paths",
		"ok": metrics["reachable_entries"] >= min(expected_entry_count, map_data.entry_points.size()),
		"reason": "" if metrics["reachable_entries"] >= min(expected_entry_count, map_data.entry_points.size()) else "not_all_entries_reach_center",
	})

	if metrics["buildable_tiles"] < minimum_buildable_tiles:
		errors.append("buildable_area_below_target")
	stages.append({
		"stage": "validate_buildable_area",
		"ok": metrics["buildable_tiles"] >= minimum_buildable_tiles,
		"reason": "" if metrics["buildable_tiles"] >= minimum_buildable_tiles else "buildable_area_too_small",
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

	var score_report: Dictionary = _score_quality(metrics, errors, warnings, expects_water, generation_config)

	var report := {
		"ok": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"metrics": metrics,
		"stages": stages,
		"quality_score": float(score_report.get("score", 0.0)),
		"quality_tier": String(score_report.get("tier", "rough")),
		"quality_breakdown": score_report.get("breakdown", {}),
	}
	return report

func _score_quality(
	metrics: Dictionary,
	errors: Array[String],
	warnings: Array[String],
	expects_water: bool,
	generation_config
) -> Dictionary:
	var requested_entries: int = maxi(1, int(metrics.get("requested_entry_count", metrics.get("entry_count", 1))))
	var requested_center_area: int = maxi(1, int(metrics.get("requested_center_area", GameConfigData.DEFAULT_VILLAGE_TILE_COUNT)))
	var reachable_ratio: float = float(metrics.get("reachable_entries", 0)) / float(requested_entries)
	var center_connectivity: float = 0.0
	var center_tiles: int = int(metrics.get("central_zone_tile_count", 0))
	if center_tiles > 0:
		center_connectivity = float(metrics.get("connected_center_tiles", 0)) / float(center_tiles)
	var buildable_center_ratio: float = float(metrics.get("buildable_in_center_pct", 0.0)) / 100.0
	var buildable_scale: float = float(metrics.get("buildable_tiles", 0)) / float(maxi(1, int(round(float(requested_center_area) * 0.42))))
	var occupied_quadrants_ratio: float = float(metrics.get("occupied_quadrants", 0)) / 4.0
	var flank_ratio: float = float(metrics.get("flank_count", 0)) / 3.0
	var passage_ratio: float = float(metrics.get("narrow_passage_count", 0)) / 4.0
	var curviness: float = float(metrics.get("mean_entry_path_curviness", 0.0))
	var curviness_score: float = clampf((curviness - 1.02) / 0.18, 0.0, 1.0)
	var dispersion_score: float = clampf(float(metrics.get("obstacle_centroid_dispersion", 0.0)) / 0.28, 0.0, 1.0)
	var variation_score: float = clampf(float(metrics.get("obstacle_area_cv", 0.0)) / 0.45, 0.0, 1.0)
	var openness_score: float = clampf((0.40 - float(metrics.get("largest_open_region_ratio", 0.0))) / 0.18, 0.0, 1.0)
	var water_score: float = 1.0
	if expects_water:
		var min_water_tiles: int = generation_config.min_water_area if generation_config != null else GameConfigData.DEFAULT_MIN_WATER_AREA
		water_score = clampf(float(metrics.get("water_tile_count", 0)) / float(maxi(1, min_water_tiles)), 0.0, 1.0)

	var breakdown := {
		"reachability": roundf(reachable_ratio * 18.0 * 10.0) / 10.0,
		"center_connectivity": roundf(center_connectivity * 14.0 * 10.0) / 10.0,
		"buildable_center": roundf(clampf(buildable_center_ratio, 0.0, 1.0) * 16.0 * 10.0) / 10.0,
		"buildable_scale": roundf(clampf(buildable_scale, 0.0, 1.0) * 10.0 * 10.0) / 10.0,
		"quadrants": roundf(clampf(occupied_quadrants_ratio, 0.0, 1.0) * 8.0 * 10.0) / 10.0,
		"flanks": roundf(clampf(flank_ratio, 0.0, 1.0) * 8.0 * 10.0) / 10.0,
		"passages": roundf(clampf(passage_ratio, 0.0, 1.0) * 8.0 * 10.0) / 10.0,
		"curviness": roundf(curviness_score * 8.0 * 10.0) / 10.0,
		"dispersion": roundf(dispersion_score * 5.0 * 10.0) / 10.0,
		"variation": roundf(variation_score * 5.0 * 10.0) / 10.0,
		"open_space_balance": roundf(openness_score * 6.0 * 10.0) / 10.0,
		"water_fit": roundf(water_score * 4.0 * 10.0) / 10.0,
		"error_penalty": float(errors.size()) * -12.0,
		"warning_penalty": float(warnings.size()) * -2.5,
	}
	var score: float = 0.0
	for key in breakdown.keys():
		score += float(breakdown[key])
	score = clampf(score, 0.0, 100.0)
	return {
		"score": score,
		"tier": _quality_tier(score),
		"breakdown": breakdown,
	}

func _quality_tier(score: float) -> String:
	if score >= 88.0:
		return "excellent"
	if score >= 76.0:
		return "strong"
	if score >= 62.0:
		return "playable"
	return "rough"

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
