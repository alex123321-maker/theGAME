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
	var radius_x: float = sqrt(float(target_area)) * rng.randf_range(0.55, 0.78)
	var radius_y: float = sqrt(float(target_area)) * rng.randf_range(0.55, 0.78)
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var region_id: int = 10
	map_data.register_region(region_id, MapTypes.RegionType.CENTER_CLEARING, "center_clearing", {"target_area": target_area})

	var raw_points := GenerationUtilsClass.fill_blob(
		map_data,
		center,
		radius_x,
		radius_y,
		rng
	)
	var points: Array[Vector2i] = GenerationUtilsClass.smooth_points(map_data, raw_points, 2, 3)
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
