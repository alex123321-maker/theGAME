extends Node3D
class_name MapRenderer3D

const WorldGridProjection3DClass = preload("res://scripts/presentation/world_grid_projection_3d.gd")
const MapDebugOverlayClass = preload("res://scripts/presentation/map_debug_overlay.gd")
const MountainRegionBuilderClass = preload("res://scripts/presentation/mountain_region_builder.gd")
const MountainSurfaceShader = preload("res://scripts/presentation/mountain_surface.gdshader")

const TERRAIN_Y: float = 0.0
const WATER_Y: float = -0.10
const ROAD_Y: float = 0.03
const BRIDGE_Y: float = 0.12
const TRANSITION_Y: float = 0.04
const BLOCKER_Y: float = 0.55
const DECOR_Y: float = 0.18
const HOVER_Y: float = 0.08

var map_data: MapData
var is_grid_visible: bool = false
var is_props_visible: bool = true
var overlay_mode: String = "none"

var _surface_root: Node3D
var _road_root: Node3D
var _water_root: Node3D
var _boundary_root: Node3D
var _blocker_root: Node3D
var _mountain_root: Node3D
var _transition_root: Node3D
var _decor_root: Node3D
var _grid_root: Node3D
var _overlay_root: Node3D
var _hover_root: Node3D
var _hover_mesh: MeshInstance3D
var _debug_overlay

var _quad_mesh: QuadMesh
var _strip_mesh: BoxMesh
var _block_mesh: BoxMesh
var _decor_mesh: CylinderMesh
var _material_cache: Dictionary = {}
var _mountain_builder := MountainRegionBuilderClass.new()
var _mountain_material: ShaderMaterial
var _mountain_ramp_texture: GradientTexture1D
var _mountain_light_direction: Vector3 = Vector3(0.61, 0.50, 0.61).normalized()

func _ready() -> void:
	_surface_root = _ensure_layer("SurfaceRoot")
	_road_root = _ensure_layer("RoadRoot")
	_water_root = _ensure_layer("WaterRoot")
	_boundary_root = _ensure_layer("BoundaryRoot")
	_blocker_root = _ensure_layer("BlockerRoot")
	_mountain_root = _ensure_layer("MountainRoot")
	_transition_root = _ensure_layer("TransitionRoot")
	_decor_root = _ensure_layer("DecorRoot")
	_grid_root = _ensure_layer("GridRoot")
	_overlay_root = _ensure_layer("OverlayRoot")
	_hover_root = _ensure_layer("HoverRoot")
	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = Vector2(WorldGridProjection3DClass.TILE_WORLD_WIDTH, WorldGridProjection3DClass.TILE_WORLD_DEPTH)
	_strip_mesh = BoxMesh.new()
	_strip_mesh.size = Vector3(WorldGridProjection3DClass.TILE_WORLD_WIDTH * 0.88, 0.02, WorldGridProjection3DClass.TILE_WORLD_DEPTH * 0.88)
	_block_mesh = BoxMesh.new()
	_block_mesh.size = Vector3(WorldGridProjection3DClass.TILE_WORLD_WIDTH * 0.92, 1.0, WorldGridProjection3DClass.TILE_WORLD_DEPTH * 0.92)
	_decor_mesh = CylinderMesh.new()
	_decor_mesh.top_radius = 0.18
	_decor_mesh.bottom_radius = 0.22
	_decor_mesh.height = 0.55
	_hover_mesh = _build_hover_mesh()
	_hover_root.add_child(_hover_mesh)
	_hover_mesh.visible = false
	_debug_overlay = MapDebugOverlayClass.new()
	_overlay_root.add_child(_debug_overlay)

func set_map_data(new_map_data: MapData) -> void:
	map_data = new_map_data
	_rebuild()

func set_grid_visible(value: bool) -> void:
	is_grid_visible = value
	if _grid_root != null:
		_grid_root.visible = value

func set_props_visible(value: bool) -> void:
	is_props_visible = value
	if _decor_root != null:
		_decor_root.visible = value

func set_overlay_mode(mode: String) -> void:
	overlay_mode = mode
	if _debug_overlay != null:
		_debug_overlay.set_overlay_mode(mode)

func set_mountain_light_direction(direction: Vector3) -> void:
	if direction.length_squared() <= 0.00001:
		return
	_mountain_light_direction = direction.normalized()
	if _mountain_material != null:
		_mountain_material.set_shader_parameter("light_direction", _mountain_light_direction)

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
	if map_data == null:
		return
	_clear_children(_surface_root)
	_clear_children(_road_root)
	_clear_children(_water_root)
	_clear_children(_boundary_root)
	_clear_children(_blocker_root)
	_clear_children(_mountain_root)
	_clear_children(_transition_root)
	_clear_children(_decor_root)
	_clear_children(_grid_root)
	_build_surface_layer()
	_build_road_layer()
	_build_water_layer()
	_build_mountain_layer()
	_build_blocker_layer()
	_build_transition_layer()
	_build_decor_layer()
	_build_grid()
	_grid_root.visible = is_grid_visible
	_decor_root.visible = is_props_visible
	if _debug_overlay != null:
		_debug_overlay.set_map_data(map_data)
		_debug_overlay.set_overlay_mode(overlay_mode)

func _build_surface_layer() -> void:
	for tile in map_data.tiles:
		if tile.is_water:
			continue
		var color: Color = _surface_color(tile)
		var mesh_instance := _build_flat_tile_mesh(color, TERRAIN_Y)
		mesh_instance.position = WorldGridProjection3DClass.logical_to_world(Vector2i(tile.x, tile.y), mesh_instance.position.y)
		_surface_root.add_child(mesh_instance)

func _build_road_layer() -> void:
	for tile in map_data.tiles:
		if not tile.is_road:
			continue
		var mesh := MeshInstance3D.new()
		var road_mesh := BoxMesh.new()
		var horizontal: bool = _has_road_neighbor(tile.x - 1, tile.y) or _has_road_neighbor(tile.x + 1, tile.y)
		var vertical: bool = _has_road_neighbor(tile.x, tile.y - 1) or _has_road_neighbor(tile.x, tile.y + 1)
		var width: float = _road_visual_width(tile.road_width_cells)
		var length: float = 0.98 if horizontal != vertical else width
		road_mesh.size = Vector3(
			length if horizontal else width,
			0.08 if tile.is_bridge else 0.04,
			length if vertical else width
		)
		mesh.mesh = road_mesh
		mesh.material_override = _material(_road_material_key(tile), _road_color(tile), 0.08)
		mesh.position = WorldGridProjection3DClass.logical_to_world(Vector2i(tile.x, tile.y), BRIDGE_Y if tile.is_bridge else ROAD_Y)
		_road_root.add_child(mesh)
		if tile.is_bridge:
			_build_bridge_rails(tile, horizontal, vertical, width)

func _build_water_layer() -> void:
	for tile in map_data.tiles:
		if not tile.is_water:
			continue
		var mesh_instance := _build_flat_tile_mesh(Color(0.14, 0.28, 0.46, 0.94), WATER_Y)
		mesh_instance.position = WorldGridProjection3DClass.logical_to_world(Vector2i(tile.x, tile.y), WATER_Y)
		_water_root.add_child(mesh_instance)

func _build_blocker_layer() -> void:
	for tile in map_data.tiles:
		if not tile.is_blocked or tile.is_road:
			continue
		if tile.blocker_type == MapTypes.BlockerType.ROCK:
			continue
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _block_mesh
		mesh_instance.material_override = _material(
			"blocker_%d" % tile.blocker_type,
			_blocker_color(tile.blocker_type),
			0.12
		)
		mesh_instance.position = WorldGridProjection3DClass.logical_to_world(Vector2i(tile.x, tile.y), BLOCKER_Y)
		mesh_instance.scale = Vector3.ONE * _blocker_scale(tile.blocker_type)
		_blocker_root.add_child(mesh_instance)

func _build_mountain_layer() -> void:
	var profiles: Array[Dictionary] = _mountain_builder.build_profiles(map_data)
	if profiles.is_empty():
		return
	var material := _mountain_surface_material()
	for profile in profiles:
		var region_mesh = _mountain_builder.build_mesh(profile)
		if region_mesh == null:
			continue
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.name = "Mountain_%d" % int(profile.get("id", 0))
		mesh_instance.mesh = region_mesh
		mesh_instance.material_override = material
		mesh_instance.position.y = TERRAIN_Y
		_mountain_root.add_child(mesh_instance)

func _build_transition_layer() -> void:
	for tile in map_data.tiles:
		if tile.transition_type == MapTypes.TransitionType.NONE:
			continue
		var transition_mesh := MeshInstance3D.new()
		transition_mesh.mesh = _strip_mesh
		transition_mesh.material_override = _material(
			"transition_%d" % tile.transition_type,
			_transition_color(tile.transition_type),
			0.00
		)
		transition_mesh.position = WorldGridProjection3DClass.logical_to_world(Vector2i(tile.x, tile.y), TRANSITION_Y)
		_transition_root.add_child(transition_mesh)
		if _needs_boundary_strip(tile.transition_type):
			_build_boundary_strips(tile)

func _build_decor_layer() -> void:
	if not is_props_visible:
		return
	for tile in map_data.tiles:
		if tile.is_road or tile.is_water or tile.is_blocked:
			continue
		if tile.region_type == MapTypes.RegionType.BLOCKER_MASS and (
			tile.rock_role != MapTypes.RockRole.NONE
			or tile.debug_tags.has("rock_edge")
			or tile.debug_tags.has("rock_core")
		):
			continue
		if tile.base_terrain_type == MapTypes.TerrainType.CLEARING:
			continue
		var density: float = _decor_density(tile)
		if density <= 0.0:
			continue
		var cluster_x: int = int(floor(float(tile.x) / 6.0))
		var cluster_y: int = int(floor(float(tile.y) / 6.0))
		var cluster_hash: int = abs(int((cluster_x * 92821) ^ (cluster_y * 68917) ^ (map_data.seed * 173)))
		var local_hash: int = abs(int((tile.x * 12011) ^ (tile.y * 39119) ^ (map_data.seed * 137)))
		var cluster_bonus: float = 0.0
		if tile.base_terrain_type == MapTypes.TerrainType.FOREST and (cluster_hash % 100) < 68:
			cluster_bonus = 0.12
		elif tile.base_terrain_type == MapTypes.TerrainType.ROCK and (cluster_hash % 100) < 54:
			cluster_bonus = 0.10
		elif _is_near_road_tile(tile.x, tile.y) and (cluster_hash % 100) < 36:
			cluster_bonus = 0.07
		var threshold: int = int(clampf((density + cluster_bonus) * 100.0, 0.0, 92.0))
		if (local_hash % 100) >= threshold:
			continue
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _decor_mesh
		mesh_instance.material_override = _material("decor_%d" % tile.base_terrain_type, _decor_color(tile), 0.08)
		mesh_instance.position = WorldGridProjection3DClass.logical_to_world(Vector2i(tile.x, tile.y), DECOR_Y)
		mesh_instance.rotation.y = float(local_hash % 4) * (PI * 0.5)
		var scale_jitter: float = 0.84 + (float(local_hash % 21) / 100.0)
		mesh_instance.scale = Vector3.ONE * scale_jitter
		_decor_root.add_child(mesh_instance)

func _build_grid() -> void:
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.albedo_color = Color(0.0, 0.0, 0.0, 0.18)
	for x in range(map_data.width + 1):
		var from := WorldGridProjection3DClass.logical_to_world(Vector2i(x, 0), 0.01)
		var to := WorldGridProjection3DClass.logical_to_world(Vector2i(x, map_data.height), 0.01)
		_grid_root.add_child(_build_line_mesh(from, to, line_material))
	for y in range(map_data.height + 1):
		var from := WorldGridProjection3DClass.logical_to_world(Vector2i(0, y), 0.01)
		var to := WorldGridProjection3DClass.logical_to_world(Vector2i(map_data.width, y), 0.01)
		_grid_root.add_child(_build_line_mesh(from, to, line_material))

func _build_boundary_strips(tile) -> void:
	var side_flags: Dictionary = _transition_side_flags(tile.transition_flags, tile.transition_type)
	for side in ["up", "right", "down", "left"]:
		if not bool(side_flags.get(side, false)):
			continue
		var mesh_instance := MeshInstance3D.new()
		var strip := BoxMesh.new()
		strip.size = Vector3(WorldGridProjection3DClass.TILE_WORLD_WIDTH * 0.55, 0.04, WorldGridProjection3DClass.TILE_WORLD_DEPTH * 0.16)
		mesh_instance.mesh = strip
		mesh_instance.material_override = _material("boundary_%s_%d" % [side, tile.transition_type], _transition_color(tile.transition_type), 0.04)
		mesh_instance.position = WorldGridProjection3DClass.logical_to_world(Vector2i(tile.x, tile.y), TRANSITION_Y + 0.03)
		match side:
			"up":
				mesh_instance.position.z -= 0.52
			"down":
				mesh_instance.position.z += 0.52
			"right":
				mesh_instance.position.x += 0.52
				mesh_instance.rotation.y = PI * 0.5
			"left":
				mesh_instance.position.x -= 0.52
				mesh_instance.rotation.y = PI * 0.5
		_boundary_root.add_child(mesh_instance)

func _build_flat_tile_mesh(color: Color, y: float) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _quad_mesh
	mesh_instance.material_override = _material("flat_%s" % color.to_html(), color, 0.03)
	mesh_instance.rotation_degrees.x = -90.0
	mesh_instance.position.y = y
	return mesh_instance

func _surface_color(tile) -> Color:
	match tile.base_terrain_type:
		MapTypes.TerrainType.CLEARING:
			return Color(0.78, 0.76, 0.66, 1.0)
		MapTypes.TerrainType.ROAD:
			return Color(0.63, 0.55, 0.46, 1.0)
		MapTypes.TerrainType.WATER:
			return Color(0.12, 0.25, 0.42, 1.0)
		MapTypes.TerrainType.FOREST:
			return Color(0.24, 0.35, 0.23, 1.0)
		MapTypes.TerrainType.ROCK:
			return Color(0.42, 0.42, 0.44, 1.0)
		MapTypes.TerrainType.BLOCKER:
			match tile.blocker_type:
				MapTypes.BlockerType.FOREST:
					return Color(0.20, 0.29, 0.21, 1.0)
				MapTypes.BlockerType.ROCK:
					return Color(0.36, 0.37, 0.38, 1.0)
				MapTypes.BlockerType.RAVINE:
					return Color(0.24, 0.20, 0.19, 1.0)
				_:
					return Color(0.32, 0.34, 0.31, 1.0)
		_:
			return Color(0.56, 0.59, 0.51, 1.0)

func _road_visual_width(width_cells: int) -> float:
	match clampi(width_cells, 1, 3):
		3:
			return 0.92
		2:
			return 0.84
		_:
			return 0.72

func _road_color(tile) -> Color:
	if tile.is_bridge:
		return Color(0.44, 0.30, 0.18, 1.0)
	if tile.is_water or tile.base_terrain_type == MapTypes.TerrainType.WATER:
		return Color(0.66, 0.61, 0.50, 1.0)
	if tile.base_terrain_type == MapTypes.TerrainType.FOREST:
		return Color(0.42, 0.35, 0.24, 1.0)
	if tile.base_terrain_type == MapTypes.TerrainType.ROCK:
		return Color(0.58, 0.53, 0.46, 1.0)
	if tile.base_terrain_type == MapTypes.TerrainType.BLOCKER:
		match tile.blocker_type:
			MapTypes.BlockerType.FOREST:
				return Color(0.39, 0.31, 0.22, 1.0)
			MapTypes.BlockerType.ROCK:
				return Color(0.52, 0.47, 0.40, 1.0)
			MapTypes.BlockerType.RAVINE:
				return Color(0.47, 0.41, 0.35, 1.0)
	return Color(0.53, 0.41, 0.31, 1.0)

func _road_material_key(tile) -> String:
	if tile.is_bridge:
		return "bridge_%d" % tile.road_width_cells
	if tile.is_water or tile.base_terrain_type == MapTypes.TerrainType.WATER:
		return "road_water_%d" % tile.road_width_cells
	if tile.base_terrain_type == MapTypes.TerrainType.BLOCKER:
		return "road_blocker_%d_%d" % [tile.blocker_type, tile.road_width_cells]
	return "road_ground_%d" % tile.road_width_cells

func _blocker_color(blocker_type: int) -> Color:
	match blocker_type:
		MapTypes.BlockerType.FOREST:
			return Color(0.17, 0.26, 0.18, 1.0)
		MapTypes.BlockerType.ROCK:
			return Color(0.37, 0.37, 0.39, 1.0)
		MapTypes.BlockerType.RAVINE:
			return Color(0.20, 0.17, 0.16, 1.0)
		_:
			return Color(0.28, 0.31, 0.28, 1.0)

func _transition_color(transition_type: int) -> Color:
	match transition_type:
		MapTypes.TransitionType.WET_EDGE:
			return Color(0.22, 0.35, 0.48, 0.9)
		MapTypes.TransitionType.ROAD_EDGE:
			return Color(0.52, 0.43, 0.33, 0.9)
		MapTypes.TransitionType.CLEARING_EDGE:
			return Color(0.83, 0.81, 0.69, 0.9)
		MapTypes.TransitionType.BLOCKER_EDGE:
			return Color(0.31, 0.28, 0.25, 0.95)
		MapTypes.TransitionType.RAVINE_EDGE:
			return Color(0.12, 0.10, 0.10, 0.95)
		_:
			return Color(1.0, 1.0, 1.0, 0.0)

func _blocker_scale(blocker_type: int) -> float:
	match blocker_type:
		MapTypes.BlockerType.FOREST:
			return 1.00
		MapTypes.BlockerType.ROCK:
			return 0.88
		MapTypes.BlockerType.RAVINE:
			return 1.15
		_:
			return 1.0

func _has_road_neighbor(x: int, y: int) -> bool:
	if map_data == null or not map_data.is_in_bounds(x, y):
		return false
	var tile = map_data.get_tile(x, y)
	return tile != null and tile.is_road

func _needs_boundary_strip(transition_type: int) -> bool:
	return transition_type != MapTypes.TransitionType.NONE

func _transition_side_flags(flags: Dictionary, transition_type: int) -> Dictionary:
	match transition_type:
		MapTypes.TransitionType.WET_EDGE:
			return flags.get("water_sides", {})
		MapTypes.TransitionType.ROAD_EDGE:
			return flags.get("road_sides", {})
		MapTypes.TransitionType.CLEARING_EDGE:
			return flags.get("clearing_sides", {})
		MapTypes.TransitionType.BLOCKER_EDGE, MapTypes.TransitionType.RAVINE_EDGE:
			return flags.get("blocker_sides", {})
		_:
			return {}

func _material(key: String, color: Color, roughness: float) -> StandardMaterial3D:
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material_cache[key] = material
	return material

func _mountain_surface_material() -> ShaderMaterial:
	if _mountain_material != null:
		return _mountain_material
	_mountain_material = ShaderMaterial.new()
	_mountain_material.shader = MountainSurfaceShader
	_mountain_material.set_shader_parameter("light_ramp", _mountain_ramp())
	_mountain_material.set_shader_parameter("light_direction", _mountain_light_direction)
	return _mountain_material

func _mountain_ramp() -> GradientTexture1D:
	if _mountain_ramp_texture != null:
		return _mountain_ramp_texture
	var gradient := Gradient.new()
	gradient.add_point(0.0, Color(0.12, 0.12, 0.12, 1.0))
	gradient.add_point(0.22, Color(0.28, 0.28, 0.28, 1.0))
	gradient.add_point(0.50, Color(0.60, 0.60, 0.60, 1.0))
	gradient.add_point(0.78, Color(0.86, 0.86, 0.86, 1.0))
	gradient.add_point(1.0, Color(1.0, 1.0, 1.0, 1.0))
	_mountain_ramp_texture = GradientTexture1D.new()
	_mountain_ramp_texture.gradient = gradient
	_mountain_ramp_texture.width = 8
	return _mountain_ramp_texture

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

func _build_bridge_rails(tile, horizontal: bool, vertical: bool, width: float) -> void:
	var rail_offsets: Array[float] = []
	var half_extent: float = maxf(0.24, width * 0.52)
	if horizontal != vertical:
		rail_offsets = [-half_extent, half_extent]
	else:
		rail_offsets = [-0.28, 0.28]
	for offset in rail_offsets:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(
			0.92 if horizontal or not vertical else 0.10,
			0.05,
			0.92 if vertical or not horizontal else 0.10
		)
		rail.mesh = rail_mesh
		rail.material_override = _material("bridge_rail", Color(0.31, 0.20, 0.12, 1.0), 0.18)
		rail.position = WorldGridProjection3DClass.logical_to_world(Vector2i(tile.x, tile.y), BRIDGE_Y + 0.08)
		if horizontal and not vertical:
			rail.position.z += offset
		elif vertical and not horizontal:
			rail.position.x += offset
			rail.rotation.y = PI * 0.5
		else:
			rail.position.z += offset
		_road_root.add_child(rail)

func _decor_density(tile) -> float:
	if tile.base_terrain_type == MapTypes.TerrainType.FOREST:
		return 0.14 if tile.debug_tags.has("forest_fringe") else 0.07
	if tile.base_terrain_type == MapTypes.TerrainType.ROCK:
		return 0.11 if tile.rock_role == MapTypes.RockRole.FOOT or tile.rock_role == MapTypes.RockRole.TALUS or tile.debug_tags.has("rock_edge") else 0.05
	if _is_near_road_tile(tile.x, tile.y):
		return 0.05
	return 0.015

func _decor_color(tile) -> Color:
	match tile.base_terrain_type:
		MapTypes.TerrainType.FOREST:
			return Color(0.34, 0.30, 0.23, 1.0)
		MapTypes.TerrainType.ROCK:
			return Color(0.48, 0.44, 0.39, 1.0)
		_:
			return Color(0.42, 0.37, 0.30, 1.0)

func _is_near_road_tile(x: int, y: int) -> bool:
	if map_data == null:
		return false
	var directions: Array[Vector2i] = [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]
	for direction in directions:
		var target: Vector2i = Vector2i(x, y) + direction
		if not map_data.is_in_bounds(target.x, target.y):
			continue
		var tile = map_data.get_tile(target.x, target.y)
		if tile != null and tile.is_road:
			return true
	return false
