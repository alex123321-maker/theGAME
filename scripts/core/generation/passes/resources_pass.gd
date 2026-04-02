extends RefCounted
class_name ResourcesPass

## Converts terrain into resource tags and points of interest.
func apply(map_data: MapData, _rng: RandomNumberGenerator, _config: Dictionary) -> void:
	for tile in map_data.tiles:
		match tile.terrain_type:
			MapTypes.TerrainType.FOREST:
				tile.resource_tag = MapTypes.ResourceTag.WOOD
				if tile.poi_tag == MapTypes.PoiTag.NONE:
					tile.poi_tag = MapTypes.PoiTag.RESOURCE_CLUSTER
			MapTypes.TerrainType.ROCK:
				tile.resource_tag = MapTypes.ResourceTag.STONE
				if tile.poi_tag == MapTypes.PoiTag.NONE:
					tile.poi_tag = MapTypes.PoiTag.RESOURCE_CLUSTER
			_:
				tile.resource_tag = MapTypes.ResourceTag.NONE
