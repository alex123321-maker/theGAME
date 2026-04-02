extends RefCounted
class_name ObstaclesPass

const GameConfigData = preload("res://autoload/game_config.gd")

## Adds forest, rock and limited water clusters outside the central clearing.
func apply(map_data: MapData, rng: RandomNumberGenerator, config: Dictionary) -> void:
	_stamp_clusters(
		map_data,
		rng,
		int(config.get("forest_cluster_count", 7)),
		MapTypes.TerrainType.FOREST,
		3,
		7
	)

	_stamp_clusters(
		map_data,
		rng,
		int(config.get("rock_cluster_count", 4)),
		MapTypes.TerrainType.ROCK,
		2,
		5
	)

	_stamp_clusters(
		map_data,
		rng,
		int(config.get("water_cluster_count", 2)),
		MapTypes.TerrainType.WATER,
		2,
		4
	)

func _stamp_clusters(
	map_data: MapData,
	rng: RandomNumberGenerator,
	cluster_count: int,
	terrain_type: int,
	min_radius: int,
	max_radius: int
) -> void:
	var center := Vector2i(map_data.width / 2, map_data.height / 2)
	var safe_radius: float = float(GameConfigData.DEFAULT_CENTRAL_ZONE_RADIUS + 4)

	for _i in range(cluster_count):
		var cluster_center := Vector2i(
			rng.randi_range(0, map_data.width - 1),
			rng.randi_range(0, map_data.height - 1)
		)

		if cluster_center.distance_to(center) <= safe_radius:
			continue

		var radius: int = rng.randi_range(min_radius, max_radius)
		for y in range(cluster_center.y - radius, cluster_center.y + radius + 1):
			for x in range(cluster_center.x - radius, cluster_center.x + radius + 1):
				if not map_data.is_in_bounds(x, y):
					continue

				var point := Vector2i(x, y)
				if point.distance_to(cluster_center) > radius:
					continue

				var tile = map_data.get_tile(x, y)
				if tile.terrain_type == MapTypes.TerrainType.ROAD:
					continue
				if tile.terrain_type == MapTypes.TerrainType.CLEARING:
					continue

				tile.terrain_type = terrain_type
				tile.is_buildable = false
				tile.is_future_wallable = terrain_type != MapTypes.TerrainType.WATER
				tile.walk_cost = _walk_cost_for_terrain(terrain_type)

func _walk_cost_for_terrain(terrain_type: int) -> float:
	match terrain_type:
		MapTypes.TerrainType.FOREST:
			return 1.6
		MapTypes.TerrainType.ROCK:
			return 3.0
		MapTypes.TerrainType.WATER:
			return 999.0
		_:
			return 1.0
