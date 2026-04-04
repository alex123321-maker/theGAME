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
		if not _passes_density(tile, map_data.seed, map_data):
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

func _passes_density(tile, seed: int, map_data: MapData) -> bool:
	var zone_density: float = _zone_density(tile, map_data)
	var cluster_bonus: float = _cluster_bonus(tile, seed, map_data)
	var limit: int = int(clampf((zone_density + cluster_bonus) * 100.0, 0.0, 94.0))
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

func _zone_density(tile, map_data: MapData) -> float:
	if tile.terrain_type == MapTypes.TerrainType.FOREST:
		return 0.20 if tile.debug_tags.has("forest_fringe") else 0.13
	if tile.terrain_type == MapTypes.TerrainType.ROCK:
		return 0.16 if tile.rock_role == MapTypes.RockRole.FOOT or tile.rock_role == MapTypes.RockRole.TALUS or tile.debug_tags.has("rock_edge") else 0.10
	if _is_near_road(tile, map_data):
		return 0.06
	if tile.base_terrain_type == MapTypes.TerrainType.CLEARING:
		return 0.0
	return 0.03

func _cluster_bonus(tile, seed: int, map_data: MapData) -> float:
	var cluster_x: int = int(floor(float(tile.x) / 5.0))
	var cluster_y: int = int(floor(float(tile.y) / 5.0))
	var cluster_hash: int = abs(int((cluster_x * 911) ^ (cluster_y * 3571) ^ (seed * 97)))
	if tile.terrain_type == MapTypes.TerrainType.FOREST:
		return 0.12 if (cluster_hash % 100) < 64 else 0.0
	if tile.terrain_type == MapTypes.TerrainType.ROCK:
		return 0.10 if (cluster_hash % 100) < 52 else 0.0
	if _is_near_road(tile, map_data):
		return 0.07 if (cluster_hash % 100) < 34 else 0.0
	return 0.0

func _is_near_road(tile, map_data: MapData) -> bool:
	for direction in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
		var nx: int = tile.x + direction.x
		var ny: int = tile.y + direction.y
		if not map_data.is_in_bounds(nx, ny):
			continue
		var neighbor = map_data.get_tile(nx, ny)
		if neighbor != null and neighbor.is_road:
			return true
	return false
