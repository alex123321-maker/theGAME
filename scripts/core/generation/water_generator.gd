extends RefCounted
class_name WaterGenerator

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")

func generate(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> bool:
	var water_spec: Variant = composition.get("water")
	if water_spec == null:
		return false
	if rng.randf() > config.water_chance:
		return false
	var center := Vector2(
		float(water_spec.get("anchor", Vector2(0.75, 0.22)).x) * float(map_data.width - 1),
		float(water_spec.get("anchor", Vector2(0.75, 0.22)).y) * float(map_data.height - 1)
	)
	var target_area: int = rng.randi_range(config.min_water_area, config.max_water_area)
	var size_bias: float = float(water_spec.get("size_bias", 1.0))
	var radius_x: float = sqrt(float(target_area)) * rng.randf_range(0.65, 0.88) * size_bias
	var radius_y: float = sqrt(float(target_area)) * rng.randf_range(0.55, 0.75) * size_bias
	var raw_points := GenerationUtilsClass.fill_blob(
		map_data,
		center,
		radius_x,
		radius_y,
		rng
	)
	var points: Array[Vector2i] = GenerationUtilsClass.smooth_points(map_data, raw_points, 3, 4)
	if points.size() < config.min_water_area / 2:
		return false
	var region_id: int = 300
	map_data.register_region(region_id, MapTypes.RegionType.WATER_REGION, "water_body", {"target_area": target_area})
	for point in points:
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
			continue
		tile.base_terrain_type = MapTypes.TerrainType.WATER
		tile.terrain_type = MapTypes.TerrainType.WATER
		tile.region_id = region_id
		tile.region_type = MapTypes.RegionType.WATER_REGION
		tile.is_walkable = false
		tile.is_water = true
		tile.is_blocked = false
		tile.is_buildable = false
		tile.walk_cost = 999.0
		tile.debug_tags.clear()
		tile.debug_tags.append("water_region")
	return true
