extends RefCounted
class_name BlockerGenerator

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")

func generate(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	for blocker_spec in composition.get("blockers", []):
		var anchor: Vector2 = blocker_spec.get("anchor", Vector2(0.25, 0.25))
		var world_center := Vector2(anchor.x * float(map_data.width - 1), anchor.y * float(map_data.height - 1))
		if world_center.distance_to(center) < float(config.min_blocker_distance_from_center):
			continue
		var target_area: int = rng.randi_range(config.min_blocker_area, config.max_blocker_area)
		var size_bias: float = float(blocker_spec.get("size_bias", 1.0))
		var radius_x: float = sqrt(float(target_area)) * rng.randf_range(0.58, 0.82) * size_bias
		var radius_y: float = sqrt(float(target_area)) * rng.randf_range(0.54, 0.80) * size_bias
		var raw_points := GenerationUtilsClass.fill_blob(
			map_data,
			world_center,
			radius_x,
			radius_y,
			rng
		)
		var points: Array[Vector2i] = GenerationUtilsClass.smooth_points(map_data, raw_points, 2, 3)
		var region_id: int = int(blocker_spec.get("region_id", 200))
		var blocker_type: int = int(blocker_spec.get("kind", MapTypes.BlockerType.FOREST))
		map_data.register_region(region_id, MapTypes.RegionType.BLOCKER_MASS, "blocker_%d" % region_id, {"blocker_type": blocker_type})
		for point in points:
			var tile = map_data.get_tile(point.x, point.y)
			if tile == null:
				continue
			if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
				continue
			tile.base_terrain_type = MapTypes.TerrainType.BLOCKER
			tile.terrain_type = MapTypes.TerrainType.BLOCKER
			tile.blocker_type = blocker_type
			tile.region_id = region_id
			tile.region_type = MapTypes.RegionType.BLOCKER_MASS
			tile.is_walkable = false
			tile.is_blocked = true
			tile.is_buildable = false
			tile.walk_cost = 999.0
			tile.debug_tags.clear()
			tile.debug_tags.append("major_blocker")
			tile.debug_tags.append(MapTypes.blocker_name(blocker_type))
