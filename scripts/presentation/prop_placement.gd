extends RefCounted
class_name PropPlacement

const PACK_ROOT := "res://assets/vendor/isometric_sketch_asset_pack"
const SHADOW_MEDIUM := PACK_ROOT + "/shadows/shadow_mask_medium.png"
const SHADOW_LARGE := PACK_ROOT + "/shadows/shadow_mask_large.png"

const _PROP_POOLS := {
	"wood": [
		PACK_ROOT + "/props/stump_01.png",
		PACK_ROOT + "/props/stump_02.png",
		PACK_ROOT + "/props/dead_tree_01.png",
		PACK_ROOT + "/props/dead_tree_02.png",
		PACK_ROOT + "/props/log_pile_01.png",
		PACK_ROOT + "/props/log_pile_02.png",
	],
	"stone": [
		PACK_ROOT + "/props/boulder_01.png",
		PACK_ROOT + "/props/boulder_02.png",
		PACK_ROOT + "/props/boulder_03.png",
		PACK_ROOT + "/props/ruins_fragment_01.png",
		PACK_ROOT + "/props/ruins_fragment_02.png",
		PACK_ROOT + "/props/ruins_fragment_03.png",
	],
	"ground": [
		PACK_ROOT + "/props/boulder_01.png",
		PACK_ROOT + "/props/stump_01.png",
		PACK_ROOT + "/props/broken_fence_01.png",
		PACK_ROOT + "/props/broken_fence_02.png",
		PACK_ROOT + "/props/cart_fragment_01.png",
		PACK_ROOT + "/props/cart_fragment_02.png",
	],
}

func build_props(map_data: MapData) -> Array[Dictionary]:
	var props: Array[Dictionary] = []
	for tile in map_data.tiles:
		if not _can_place_on_tile(tile):
			continue
		if not _passes_density(tile, map_data.seed):
			continue

		var texture_path: String = _choose_texture(tile, map_data.seed)
		var shadow_path: String = SHADOW_LARGE if texture_path.contains("dead_tree") or texture_path.contains("ruins_fragment") else SHADOW_MEDIUM
		props.append({
			"logical": Vector2i(tile.x, tile.y),
			"texture_path": texture_path,
			"shadow_texture_path": shadow_path,
			"offset": Vector2(_jitter_x(tile, map_data.seed), 0.0),
			"shadow_alpha": 0.33,
		})
	return props

func _can_place_on_tile(tile) -> bool:
	if tile.terrain_type == MapTypes.TerrainType.WATER:
		return false
	if tile.terrain_type == MapTypes.TerrainType.RAVINE:
		return false
	if tile.terrain_type == MapTypes.TerrainType.ROAD:
		return false
	return tile.terrain_type != MapTypes.TerrainType.CLEARING

func _passes_density(tile, seed: int) -> bool:
	var limit: int = 10
	if tile.terrain_type == MapTypes.TerrainType.FOREST:
		limit = 24
	elif tile.terrain_type == MapTypes.TerrainType.ROCK:
		limit = 20
	elif tile.resource_tag == MapTypes.ResourceTag.WOOD or tile.resource_tag == MapTypes.ResourceTag.STONE:
		limit = 18

	var h: int = abs(int((tile.x * 2654435761) ^ (tile.y * 805459861) ^ (seed * 104729)))
	return (h % 100) < limit

func _choose_texture(tile, seed: int) -> String:
	var pool: Array = _resolve_pool(tile)
	var idx: int = abs(int((tile.x * 911) ^ (tile.y * 3571) ^ (seed * 97))) % pool.size()
	return String(pool[idx])

func _resolve_pool(tile) -> Array:
	if tile.resource_tag == MapTypes.ResourceTag.WOOD or tile.terrain_type == MapTypes.TerrainType.FOREST:
		return _PROP_POOLS["wood"]
	if tile.resource_tag == MapTypes.ResourceTag.STONE or tile.terrain_type == MapTypes.TerrainType.ROCK:
		return _PROP_POOLS["stone"]
	return _PROP_POOLS["ground"]

func _jitter_x(tile, seed: int) -> float:
	var h: int = abs(int((tile.x * 149) ^ (tile.y * 263) ^ (seed * 401)))
	return float((h % 13) - 6)
