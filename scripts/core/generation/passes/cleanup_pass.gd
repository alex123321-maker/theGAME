extends RefCounted
class_name CleanupPass

## Performs small consistency corrections after terrain stamping.
func apply(map_data: MapData, _rng: RandomNumberGenerator, _config: Dictionary) -> void:
	for tile in map_data.tiles:
		if tile.terrain_type == MapTypes.TerrainType.WATER:
			tile.is_buildable = false
			tile.is_future_wallable = false
			continue

		if tile.terrain_type == MapTypes.TerrainType.ROAD:
			tile.is_buildable = false
			tile.is_future_wallable = false
			continue

		if tile.terrain_type == MapTypes.TerrainType.GROUND:
			tile.is_buildable = false
			tile.is_future_wallable = true
