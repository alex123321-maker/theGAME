extends Node3D
class_name MapRenderer3D

const WorldGridProjection3DClass = preload("res://scripts/presentation/world_grid_projection_3d.gd")

const ASSET_ROOT := "res://assets/vendor/village_world_3d_min_pack/village_world_3d_min_pack/environment"
const CUSTOM_GROUND_MODEL := "res://assets/custom/ground_replacement.glb"
const CUSTOM_GROUND_SCALE := 2.4
const TERRAIN_Y: float = 0.0
const HOVER_Y: float = 0.06
const PROP_Y: float = 0.02

const _GROUND_MODELS: Array[String] = [
	CUSTOM_GROUND_MODEL,
]
const _CLEARING_MODELS: Array[String] = [
	ASSET_ROOT + "/terrain/clearing/clearing_01.glb",
	ASSET_ROOT + "/terrain/clearing/clearing_02.glb",
]
const _ROAD_STRAIGHT_MODELS: Array[String] = [
	ASSET_ROOT + "/terrain/road/road_narrow_straight.glb",
	ASSET_ROOT + "/terrain/road/road_medium_straight.glb",
	ASSET_ROOT + "/terrain/road/road_wide_straight.glb",
]
const _ROAD_CORNER_MODEL := ASSET_ROOT + "/terrain/road/road_narrow_corner.glb"
const _ROAD_T_MODEL := ASSET_ROOT + "/terrain/road/road_medium_t.glb"

const _BOUNDARY_MODELS := {
	MapTypes.TerrainType.FOREST: {
		"straight": ASSET_ROOT + "/boundaries/forest/forest_edge_straight.glb",
		"corner": ASSET_ROOT + "/boundaries/forest/forest_edge_corner.glb",
		"alt": ASSET_ROOT + "/boundaries/forest/forest_edge_sparse.glb",
	},
	MapTypes.TerrainType.ROCK: {
		"straight": ASSET_ROOT + "/boundaries/rock/rock_edge_straight.glb",
		"corner": ASSET_ROOT + "/boundaries/rock/rock_edge_corner.glb",
		"alt": ASSET_ROOT + "/boundaries/rock/rock_edge_ridge.glb",
	},
	MapTypes.TerrainType.WATER: {
		"straight": ASSET_ROOT + "/boundaries/water/water_edge_straight.glb",
		"corner": ASSET_ROOT + "/boundaries/water/water_edge_corner.glb",
		"alt": ASSET_ROOT + "/boundaries/water/water_channel.glb",
	},
	MapTypes.TerrainType.RAVINE: {
		"straight": ASSET_ROOT + "/boundaries/ravine/ravine_edge_straight.glb",
		"corner": ASSET_ROOT + "/boundaries/ravine/ravine_edge_corner.glb",
		"alt": ASSET_ROOT + "/boundaries/ravine/ravine_narrow_pass.glb",
	},
}

const _PROP_POOLS := {
	"wood": [
		ASSET_ROOT + "/props/major/stump_wide.glb",
		ASSET_ROOT + "/props/major/dead_tree_a.glb",
		ASSET_ROOT + "/props/major/dead_tree_b.glb",
		ASSET_ROOT + "/props/major/log_pile.glb",
	],
	"stone": [
		ASSET_ROOT + "/props/major/boulder_large.glb",
		ASSET_ROOT + "/props/major/ruins_fragment.glb",
	],
	"ground": [
		ASSET_ROOT + "/props/major/boulder_large.glb",
		ASSET_ROOT + "/props/major/broken_fence_segment.glb",
		ASSET_ROOT + "/props/major/cart_fragment.glb",
		ASSET_ROOT + "/props/major/log_pile.glb",
	],
}

const _ROTATABLE_PROPS := {
	ASSET_ROOT + "/props/major/broken_fence_segment.glb": true,
	ASSET_ROOT + "/props/major/cart_fragment.glb": true,
	ASSET_ROOT + "/props/major/log_pile.glb": true,
}

var map_data: MapData
var is_grid_visible: bool = false
var is_props_visible: bool = true
var overlay_mode: String = "none"

var _scene_cache: Dictionary = {}

var _terrain_root: Node3D
var _props_root: Node3D
var _hover_root: Node3D
var _grid_root: Node3D
var _hover_mesh: MeshInstance3D

func _ready() -> void:
	_terrain_root = _ensure_layer("TerrainRoot")
	_props_root = _ensure_layer("PropsRoot")
	_hover_root = _ensure_layer("HoverRoot")
	_grid_root = _ensure_layer("GridRoot")
	_hover_mesh = _build_hover_mesh()
	_hover_root.add_child(_hover_mesh)
	_hover_mesh.visible = false

func set_map_data(new_map_data: MapData) -> void:
	map_data = new_map_data
	_rebuild()

func set_grid_visible(value: bool) -> void:
	is_grid_visible = value
	if _grid_root != null:
		_grid_root.visible = value

func set_props_visible(value: bool) -> void:
	is_props_visible = value
	_rebuild_props()

func set_overlay_mode(mode: String) -> void:
	overlay_mode = mode
	# 3D pack uses meshes, so overlay is currently represented only by hover/grid diagnostics.

func set_hover_tile(logical: Vector2i, is_valid: bool) -> void:
	if _hover_mesh == null:
		return
	if not is_valid:
		_hover_mesh.visible = false
		return
	_hover_mesh.visible = true
	_hover_mesh.position = WorldGridProjection3DClass.logical_to_world(logical, HOVER_Y)

func get_logical_from_world(world_position: Vector3) -> Vector2i:
	return WorldGridProjection3DClass.world_to_logical(world_position)

func _rebuild() -> void:
	_rebuild_terrain()
	_rebuild_props()
	_rebuild_grid()

func _rebuild_terrain() -> void:
	if _terrain_root == null:
		return
	_clear_children(_terrain_root)
	if map_data == null:
		return

	for tile in map_data.tiles:
		var visual: Dictionary = _resolve_terrain_visual(tile)
		var model_path: String = String(visual.get("model_path", ""))
		var model: Node3D = _instantiate_model(model_path)
		if model == null:
			continue
		model.position = WorldGridProjection3DClass.logical_to_world(Vector2i(tile.x, tile.y), TERRAIN_Y)
		model.rotation.y = float(visual.get("rotation_y", 0.0))
		model.scale = _model_scale_for_path(model_path)
		_terrain_root.add_child(model)

func _rebuild_props() -> void:
	if _props_root == null:
		return
	_clear_children(_props_root)
	if map_data == null or not is_props_visible:
		return

	for tile in map_data.tiles:
		if not _can_place_prop(tile):
			continue
		if not _passes_prop_density(tile):
			continue

		var model_path: String = _choose_prop_model(tile)
		var model: Node3D = _instantiate_model(model_path)
		if model == null:
			continue

		model.position = WorldGridProjection3DClass.logical_to_world(Vector2i(tile.x, tile.y), PROP_Y)
		model.scale = _model_scale_for_path(model_path)
		if _ROTATABLE_PROPS.has(model_path):
			model.rotation.y = _random_y_rotation(tile.x, tile.y, 31)
		_props_root.add_child(model)

func _rebuild_grid() -> void:
	if _grid_root == null:
		return
	_clear_children(_grid_root)
	if map_data == null:
		return

	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(0.0, 0.0, 0.0, 0.22)

	for x in range(map_data.width + 1):
		var from := WorldGridProjection3DClass.logical_to_world(Vector2i(x, 0), 0.01)
		var to := WorldGridProjection3DClass.logical_to_world(Vector2i(x, map_data.height), 0.01)
		_grid_root.add_child(_build_line_mesh(from, to, line_material))
	for y in range(map_data.height + 1):
		var from := WorldGridProjection3DClass.logical_to_world(Vector2i(0, y), 0.01)
		var to := WorldGridProjection3DClass.logical_to_world(Vector2i(map_data.width, y), 0.01)
		_grid_root.add_child(_build_line_mesh(from, to, line_material))

	_grid_root.visible = is_grid_visible

func _resolve_terrain_visual(tile) -> Dictionary:
	match tile.terrain_type:
		MapTypes.TerrainType.GROUND:
			return {
				"model_path": _pick_variant(_GROUND_MODELS, tile.x, tile.y, 11),
				"rotation_y": 0.0,
			}
		MapTypes.TerrainType.CLEARING:
			return {
				"model_path": _pick_variant(_CLEARING_MODELS, tile.x, tile.y, 13),
				"rotation_y": 0.0,
			}
		MapTypes.TerrainType.ROAD:
			return _resolve_road_visual(tile)
		MapTypes.TerrainType.FOREST, MapTypes.TerrainType.ROCK, MapTypes.TerrainType.WATER, MapTypes.TerrainType.RAVINE:
			return _resolve_boundary_visual(tile)
		_:
			return {
				"model_path": _GROUND_MODELS[0],
				"rotation_y": 0.0,
			}

func _resolve_road_visual(tile) -> Dictionary:
	var n: Dictionary = _neighbors_of_type(tile.x, tile.y, MapTypes.TerrainType.ROAD)
	var count: int = _true_count(n)

	if count >= 3:
		return {
			"model_path": _ROAD_T_MODEL,
			"rotation_y": _t_rotation_from_neighbors(n),
		}
	if count == 2 and _is_corner(n):
		return {
			"model_path": _ROAD_CORNER_MODEL,
			"rotation_y": _corner_rotation_from_neighbors(n),
		}

	var straight_path: String = _pick_variant(_ROAD_STRAIGHT_MODELS, tile.x, tile.y, 17)
	var vertical_axis: bool = bool(n["up"]) or bool(n["down"])
	if not vertical_axis and not bool(n["left"]) and not bool(n["right"]):
		vertical_axis = (_hash(tile.x, tile.y, 19) % 2) == 0
	return {
		"model_path": straight_path,
		"rotation_y": 0.0 if vertical_axis else PI * 0.5,
	}

func _resolve_boundary_visual(tile) -> Dictionary:
	var terrain_type: int = tile.terrain_type
	var options: Dictionary = _BOUNDARY_MODELS.get(terrain_type, {})
	var exposed: Dictionary = _exposed_sides(tile.x, tile.y, terrain_type)
	var count: int = _true_count(exposed)

	if count >= 2 and _is_corner(exposed):
		return {
			"model_path": String(options.get("corner", _GROUND_MODELS[0])),
			"rotation_y": _corner_rotation_from_neighbors(exposed),
		}
	if count >= 1:
		var straight_model: String = String(options.get("straight", _GROUND_MODELS[0]))
		var primary_side: String = _first_true_side(exposed)
		return {
			"model_path": straight_model,
			"rotation_y": _straight_rotation_from_side(primary_side),
		}

	return {
		"model_path": String(options.get("alt", _GROUND_MODELS[0])),
		"rotation_y": _random_y_rotation(tile.x, tile.y, 23),
	}

func _can_place_prop(tile) -> bool:
	if tile.terrain_type == MapTypes.TerrainType.ROAD:
		return false
	if tile.terrain_type == MapTypes.TerrainType.WATER:
		return false
	if tile.terrain_type == MapTypes.TerrainType.RAVINE:
		return false
	if tile.terrain_type == MapTypes.TerrainType.CLEARING:
		return false
	return true

func _passes_prop_density(tile) -> bool:
	var threshold: int = 12
	if tile.terrain_type == MapTypes.TerrainType.FOREST or tile.resource_tag == MapTypes.ResourceTag.WOOD:
		threshold = 26
	elif tile.terrain_type == MapTypes.TerrainType.ROCK or tile.resource_tag == MapTypes.ResourceTag.STONE:
		threshold = 20
	var h: int = _hash(tile.x, tile.y, 29) % 100
	return h < threshold

func _choose_prop_model(tile) -> String:
	var pool_key: String = "ground"
	if tile.resource_tag == MapTypes.ResourceTag.WOOD or tile.terrain_type == MapTypes.TerrainType.FOREST:
		pool_key = "wood"
	elif tile.resource_tag == MapTypes.ResourceTag.STONE or tile.terrain_type == MapTypes.TerrainType.ROCK:
		pool_key = "stone"
	var pool: Array = _PROP_POOLS[pool_key]
	return String(pool[_hash(tile.x, tile.y, 37) % pool.size()])

func _neighbors_of_type(x: int, y: int, terrain_type: int) -> Dictionary:
	return {
		"up": _is_terrain(x, y - 1, terrain_type),
		"right": _is_terrain(x + 1, y, terrain_type),
		"down": _is_terrain(x, y + 1, terrain_type),
		"left": _is_terrain(x - 1, y, terrain_type),
	}

func _exposed_sides(x: int, y: int, terrain_type: int) -> Dictionary:
	return {
		"up": not _is_terrain(x, y - 1, terrain_type),
		"right": not _is_terrain(x + 1, y, terrain_type),
		"down": not _is_terrain(x, y + 1, terrain_type),
		"left": not _is_terrain(x - 1, y, terrain_type),
	}

func _is_terrain(x: int, y: int, terrain_type: int) -> bool:
	if map_data == null or not map_data.is_in_bounds(x, y):
		return false
	var tile = map_data.get_tile(x, y)
	return tile != null and tile.terrain_type == terrain_type

func _true_count(flags: Dictionary) -> int:
	var count: int = 0
	for key in ["up", "right", "down", "left"]:
		if bool(flags.get(key, false)):
			count += 1
	return count

func _is_corner(flags: Dictionary) -> bool:
	return (bool(flags["up"]) and bool(flags["right"])) \
		or (bool(flags["right"]) and bool(flags["down"])) \
		or (bool(flags["down"]) and bool(flags["left"])) \
		or (bool(flags["left"]) and bool(flags["up"]))

func _corner_rotation_from_neighbors(flags: Dictionary) -> float:
	if bool(flags["up"]) and bool(flags["right"]):
		return 0.0
	if bool(flags["right"]) and bool(flags["down"]):
		return PI * 0.5
	if bool(flags["down"]) and bool(flags["left"]):
		return PI
	return -PI * 0.5

func _t_rotation_from_neighbors(flags: Dictionary) -> float:
	if not bool(flags["down"]):
		return 0.0
	if not bool(flags["left"]):
		return PI * 0.5
	if not bool(flags["up"]):
		return PI
	return -PI * 0.5

func _first_true_side(flags: Dictionary) -> String:
	for key in ["up", "right", "down", "left"]:
		if bool(flags.get(key, false)):
			return key
	return "up"

func _straight_rotation_from_side(side: String) -> float:
	match side:
		"up", "down":
			return 0.0
		"right", "left":
			return PI * 0.5
		_:
			return 0.0

func _instantiate_model(path: String) -> Node3D:
	if path.is_empty():
		return null
	var packed: PackedScene = _load_scene(path)
	if packed == null:
		return null
	var instance: Node = packed.instantiate()
	return instance as Node3D

func _load_scene(path: String) -> PackedScene:
	if _scene_cache.has(path):
		return _scene_cache[path]
	var packed: PackedScene = load(path)
	_scene_cache[path] = packed
	return packed

func _pick_variant(pool: Array, x: int, y: int, salt: int) -> String:
	if pool.is_empty():
		return ""
	return String(pool[_hash(x, y, salt) % pool.size()])

func _hash(x: int, y: int, salt: int) -> int:
	return abs(int((x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)))

func _random_y_rotation(x: int, y: int, salt: int) -> float:
	return float(_hash(x, y, salt) % 4) * (PI * 0.5)

func _model_scale_for_path(path: String) -> Vector3:
	if path == CUSTOM_GROUND_MODEL:
		return Vector3.ONE * CUSTOM_GROUND_SCALE
	return Vector3.ONE

func _build_hover_mesh() -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	var mesh := QuadMesh.new()
	mesh.size = Vector2(WorldGridProjection3DClass.TILE_WORLD_WIDTH * 0.9, WorldGridProjection3DClass.TILE_WORLD_DEPTH * 0.9)
	mesh_instance.mesh = mesh
	mesh_instance.rotation_degrees.x = -90.0

	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.9, 0.2, 0.24)
	mesh_instance.material_override = material
	return mesh_instance

func _build_line_mesh(from: Vector3, to: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate.surface_add_vertex(from)
	immediate.surface_add_vertex(to)
	immediate.surface_end()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = immediate
	return mesh_instance

func _ensure_layer(node_name: String) -> Node3D:
	var existing: Node = get_node_or_null(node_name)
	if existing != null:
		return existing as Node3D
	var node := Node3D.new()
	node.name = node_name
	add_child(node)
	return node

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.free()
