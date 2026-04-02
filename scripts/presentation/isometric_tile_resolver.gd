extends RefCounted
class_name IsometricTileResolver

const TILESET_RESOURCE_PATH := "res://resources/tilesets/world_isometric_tileset.tres"
const PACK_ROOT := "res://assets/vendor/isometric_sketch_asset_pack"
const FALLBACK_TEXTURE := PACK_ROOT + "/terrain/base/ground_01.png"

const _BASE_TEXTURES := {
	MapTypes.TerrainType.GROUND: [
		PACK_ROOT + "/terrain/base/ground_01.png",
		PACK_ROOT + "/terrain/base/ground_02.png",
		PACK_ROOT + "/terrain/base/ground_03.png",
		PACK_ROOT + "/terrain/base/ground_04.png",
		PACK_ROOT + "/terrain/base/ground_05.png",
		PACK_ROOT + "/terrain/base/ground_06.png",
	],
	MapTypes.TerrainType.CLEARING: [
		PACK_ROOT + "/terrain/base/clearing_01.png",
		PACK_ROOT + "/terrain/base/clearing_02.png",
		PACK_ROOT + "/terrain/base/clearing_03.png",
		PACK_ROOT + "/terrain/base/clearing_04.png",
	],
	MapTypes.TerrainType.ROAD: [
		PACK_ROOT + "/terrain/base/road_01.png",
		PACK_ROOT + "/terrain/base/road_02.png",
		PACK_ROOT + "/terrain/base/road_03.png",
		PACK_ROOT + "/terrain/base/road_04.png",
		PACK_ROOT + "/terrain/base/road_05.png",
		PACK_ROOT + "/terrain/base/road_06.png",
	],
}

const _EDGE_TEXTURES := {
	MapTypes.TerrainType.FOREST: {
		"north": PACK_ROOT + "/terrain/edges/forest_edge_north.png",
		"east": PACK_ROOT + "/terrain/edges/forest_edge_east.png",
		"south": PACK_ROOT + "/terrain/edges/forest_edge_south.png",
		"west": PACK_ROOT + "/terrain/edges/forest_edge_west.png",
	},
	MapTypes.TerrainType.ROCK: {
		"north": PACK_ROOT + "/terrain/edges/rock_edge_north.png",
		"east": PACK_ROOT + "/terrain/edges/rock_edge_east.png",
		"south": PACK_ROOT + "/terrain/edges/rock_edge_south.png",
		"west": PACK_ROOT + "/terrain/edges/rock_edge_west.png",
	},
	MapTypes.TerrainType.WATER: {
		"north": PACK_ROOT + "/terrain/edges/water_edge_north.png",
		"east": PACK_ROOT + "/terrain/edges/water_edge_east.png",
		"south": PACK_ROOT + "/terrain/edges/water_edge_south.png",
		"west": PACK_ROOT + "/terrain/edges/water_edge_west.png",
	},
	MapTypes.TerrainType.RAVINE: {
		"north": PACK_ROOT + "/terrain/edges/ravine_edge_north.png",
		"east": PACK_ROOT + "/terrain/edges/ravine_edge_east.png",
		"south": PACK_ROOT + "/terrain/edges/ravine_edge_south.png",
		"west": PACK_ROOT + "/terrain/edges/ravine_edge_west.png",
	},
}

const _TRANSITION_TEXTURES := {
	"road_to_ground": [
		PACK_ROOT + "/terrain/transitions/road_to_ground_01.png",
		PACK_ROOT + "/terrain/transitions/road_to_ground_02.png",
		PACK_ROOT + "/terrain/transitions/road_to_ground_03.png",
		PACK_ROOT + "/terrain/transitions/road_to_ground_04.png",
	],
	"clearing_to_ground": [
		PACK_ROOT + "/terrain/transitions/clearing_to_ground_01.png",
		PACK_ROOT + "/terrain/transitions/clearing_to_ground_02.png",
		PACK_ROOT + "/terrain/transitions/clearing_to_ground_03.png",
		PACK_ROOT + "/terrain/transitions/clearing_to_ground_04.png",
	],
	"obstacle_transition": [
		PACK_ROOT + "/terrain/transitions/obstacle_transition_01.png",
		PACK_ROOT + "/terrain/transitions/obstacle_transition_02.png",
		PACK_ROOT + "/terrain/transitions/obstacle_transition_03.png",
		PACK_ROOT + "/terrain/transitions/obstacle_transition_04.png",
	],
}

var _missing_log: Dictionary = {}
var _tileset_resource: TileSet

func _init() -> void:
	_tileset_resource = load(TILESET_RESOURCE_PATH)
	if _tileset_resource == null:
		push_warning("IsometricTileResolver: tileset resource is missing at %s." % TILESET_RESOURCE_PATH)

func resolve_tile_visual(tile, map_data: MapData) -> Dictionary:
	if _BASE_TEXTURES.has(tile.terrain_type):
		return _resolve_base_visual(tile, map_data)
	if _EDGE_TEXTURES.has(tile.terrain_type):
		return _build_visual(_resolve_edge(tile, map_data))

	_log_missing_terrain(tile.terrain_type)
	return _build_visual(FALLBACK_TEXTURE)

func resolve_tile_texture_path(tile, map_data: MapData) -> String:
	return String(resolve_tile_visual(tile, map_data).get("texture_path", FALLBACK_TEXTURE))

func has_missing_entries() -> bool:
	return not _missing_log.is_empty()

func get_missing_entries() -> Dictionary:
	return _missing_log.duplicate(true)

func _resolve_base_visual(tile, map_data: MapData) -> Dictionary:
	if tile.terrain_type == MapTypes.TerrainType.ROAD:
		return _resolve_road_visual(tile, map_data)
	if tile.terrain_type == MapTypes.TerrainType.CLEARING and _touches_any(tile, map_data, [MapTypes.TerrainType.GROUND]):
		return _build_visual(_pick_variant(_TRANSITION_TEXTURES["clearing_to_ground"], tile, map_data.seed))
	return _build_visual(_pick_variant(_BASE_TEXTURES[tile.terrain_type], tile, map_data.seed))

func _resolve_road_visual(tile, map_data: MapData) -> Dictionary:
	var neighbors: Dictionary = _get_road_neighbors(tile, map_data)
	var use_vertical_axis: bool = _use_vertical_road_axis(tile, map_data, neighbors)
	var texture_path: String = _pick_variant(_BASE_TEXTURES[MapTypes.TerrainType.ROAD], tile, map_data.seed)
	return _build_visual(texture_path, use_vertical_axis)

func _resolve_edge(tile, map_data: MapData) -> String:
	var side: String = _resolve_exposed_side(tile, map_data)
	var options: Dictionary = _EDGE_TEXTURES[tile.terrain_type]
	if not options.has(side):
		_log_missing_terrain(tile.terrain_type)
		return FALLBACK_TEXTURE
	return String(options[side])

func _resolve_exposed_side(tile, map_data: MapData) -> String:
	var probes := [
		{"name": "north", "delta": Vector2i.UP},
		{"name": "east", "delta": Vector2i.RIGHT},
		{"name": "south", "delta": Vector2i.DOWN},
		{"name": "west", "delta": Vector2i.LEFT},
	]

	for probe in probes:
		var delta: Vector2i = probe["delta"]
		var nx: int = tile.x + delta.x
		var ny: int = tile.y + delta.y
		if not map_data.is_in_bounds(nx, ny):
			return String(probe["name"])
		var neighbor = map_data.get_tile(nx, ny)
		if neighbor == null or neighbor.terrain_type != tile.terrain_type:
			return String(probe["name"])

	return "south"

func _touches_any(tile, map_data: MapData, terrain_types: Array) -> bool:
	var deltas: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
	for delta in deltas:
		var nx: int = tile.x + delta.x
		var ny: int = tile.y + delta.y
		if not map_data.is_in_bounds(nx, ny):
			continue
		var neighbor = map_data.get_tile(nx, ny)
		if neighbor != null and terrain_types.has(neighbor.terrain_type):
			return true
	return false

func _get_road_neighbors(tile, map_data: MapData) -> Dictionary:
	return {
		"left": _has_matching_neighbor(tile, map_data, Vector2i.LEFT, [MapTypes.TerrainType.ROAD]),
		"right": _has_matching_neighbor(tile, map_data, Vector2i.RIGHT, [MapTypes.TerrainType.ROAD]),
		"up": _has_matching_neighbor(tile, map_data, Vector2i.UP, [MapTypes.TerrainType.ROAD]),
		"down": _has_matching_neighbor(tile, map_data, Vector2i.DOWN, [MapTypes.TerrainType.ROAD]),
	}

func _use_vertical_road_axis(tile, map_data: MapData, neighbors: Dictionary) -> bool:
	var horizontal_connections: int = (1 if bool(neighbors["left"]) else 0) + (1 if bool(neighbors["right"]) else 0)
	var vertical_connections: int = (1 if bool(neighbors["up"]) else 0) + (1 if bool(neighbors["down"]) else 0)
	if vertical_connections > horizontal_connections:
		return true
	if horizontal_connections > vertical_connections:
		return false

	var horizontal_span: int = _measure_road_span(tile, map_data, Vector2i.LEFT) + _measure_road_span(tile, map_data, Vector2i.RIGHT)
	var vertical_span: int = _measure_road_span(tile, map_data, Vector2i.UP) + _measure_road_span(tile, map_data, Vector2i.DOWN)
	if vertical_span > horizontal_span:
		return true
	if horizontal_span > vertical_span:
		return false

	return _stable_variant_index(tile.x, tile.y, 2, map_data.seed) == 1

func _measure_road_span(tile, map_data: MapData, delta: Vector2i) -> int:
	var distance: int = 0
	var probe := Vector2i(tile.x, tile.y) + delta
	while map_data.is_in_bounds(probe.x, probe.y):
		var neighbor = map_data.get_tile(probe.x, probe.y)
		if neighbor == null or neighbor.terrain_type != MapTypes.TerrainType.ROAD:
			break
		distance += 1
		probe += delta
	return distance

func _has_matching_neighbor(tile, map_data: MapData, delta: Vector2i, terrain_types: Array) -> bool:
	var nx: int = tile.x + delta.x
	var ny: int = tile.y + delta.y
	if not map_data.is_in_bounds(nx, ny):
		return false
	var neighbor = map_data.get_tile(nx, ny)
	return neighbor != null and terrain_types.has(neighbor.terrain_type)

func _build_visual(texture_path: String, flip_h: bool = false) -> Dictionary:
	return {
		"texture_path": texture_path,
		"flip_h": flip_h,
	}

func _pick_variant(variants: Array, tile, seed: int) -> String:
	if variants.is_empty():
		return FALLBACK_TEXTURE
	var idx: int = _stable_variant_index(tile.x, tile.y, variants.size(), seed)
	return String(variants[idx])

func _log_missing_terrain(terrain_type: int) -> void:
	if _missing_log.has(terrain_type):
		return
	_missing_log[terrain_type] = true
	push_warning("IsometricTileResolver: missing terrain mapping for terrain_type=%d." % terrain_type)

func _stable_variant_index(x: int, y: int, size: int, seed: int) -> int:
	if size <= 0:
		return 0
	var h: int = int((x * 73856093) ^ (y * 19349663) ^ (seed * 83492791))
	return abs(h) % size
