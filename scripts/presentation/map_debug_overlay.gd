extends Node3D
class_name MapDebugOverlay

const WorldGridProjection3DClass = preload("res://scripts/presentation/world_grid_projection_3d.gd")

const OVERLAY_Y: float = 0.12

var map_data: MapData
var overlay_mode: String = "none"
var _quad_mesh: QuadMesh
var _overlay_root: Node3D
var _graph_root: Node3D
var _material_cache: Dictionary = {}

func _ready() -> void:
	_overlay_root = Node3D.new()
	_overlay_root.name = "OverlayTiles"
	add_child(_overlay_root)
	_graph_root = Node3D.new()
	_graph_root.name = "OverlayGraph"
	add_child(_graph_root)
	_quad_mesh = QuadMesh.new()
	_quad_mesh.size = Vector2(WorldGridProjection3DClass.TILE_WORLD_WIDTH * 0.88, WorldGridProjection3DClass.TILE_WORLD_DEPTH * 0.88)

func set_map_data(new_map_data: MapData) -> void:
	map_data = new_map_data
	_rebuild()

func set_overlay_mode(mode: String) -> void:
	overlay_mode = mode
	_rebuild()

func _rebuild() -> void:
	if _overlay_root == null or _graph_root == null:
		return
	_clear_children(_overlay_root)
	_clear_children(_graph_root)
	visible = overlay_mode != "none"
	if map_data == null or overlay_mode == "none":
		return
	for tile in map_data.tiles:
		var color: Color = _overlay_color(tile)
		if color.a <= 0.0:
			continue
		var mesh_instance := MeshInstance3D.new()
		mesh_instance.mesh = _quad_mesh
		mesh_instance.rotation_degrees.x = -90.0
		mesh_instance.position = WorldGridProjection3DClass.logical_to_world(Vector2i(tile.x, tile.y), OVERLAY_Y)
		mesh_instance.material_override = _material("%s_%s" % [overlay_mode, color.to_html()], color)
		_overlay_root.add_child(mesh_instance)
	if overlay_mode == "roads":
		_build_road_graph()

func _overlay_color(tile) -> Color:
	match overlay_mode:
		"base_terrain":
			match tile.base_terrain_type:
				MapTypes.TerrainType.CLEARING:
					return Color(0.92, 0.88, 0.54, 0.26)
				MapTypes.TerrainType.ROAD:
					return Color(0.81, 0.52, 0.30, 0.34)
				MapTypes.TerrainType.WATER:
					return Color(0.20, 0.45, 0.88, 0.34)
				MapTypes.TerrainType.FOREST:
					return Color(0.16, 0.42, 0.18, 0.34)
				MapTypes.TerrainType.ROCK:
					return Color(0.52, 0.52, 0.54, 0.34)
				MapTypes.TerrainType.BLOCKER:
					return Color(0.16, 0.24, 0.16, 0.34)
				_:
					return Color(0.70, 0.72, 0.70, 0.14)
		"regions":
			if tile.region_id == 0:
				return Color(0.0, 0.0, 0.0, 0.0)
			return Color.from_hsv(float(tile.region_id % 16) / 16.0, 0.55, 0.92, 0.26)
		"roads":
			return Color(1.0, 0.70, 0.22, 0.34) if tile.is_road else Color(0.0, 0.0, 0.0, 0.0)
		"water":
			return Color(0.20, 0.52, 0.95, 0.34) if tile.is_water else Color(0.0, 0.0, 0.0, 0.0)
		"blockers":
			return Color(0.18, 0.18, 0.18, 0.34) if tile.is_blocked else Color(0.0, 0.0, 0.0, 0.0)
		"buildable":
			return Color(0.20, 0.78, 0.34, 0.28) if tile.is_buildable else Color(0.68, 0.08, 0.08, 0.08)
		"validation":
			return Color(0.18, 0.68, 0.32, 0.18) if bool(map_data.validation_report.get("ok", false)) else Color(0.88, 0.20, 0.18, 0.18)
		_:
			return Color(0.0, 0.0, 0.0, 0.0)

func _build_road_graph() -> void:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(1.0, 0.88, 0.32, 0.95)
	for road in map_data.roads:
		var points: Array[Vector3] = _road_graph_points(road)
		for index in range(points.size() - 1):
			_graph_root.add_child(_build_line_mesh(points[index], points[index + 1], material))

func _road_graph_points(road: Dictionary) -> Array[Vector3]:
	var points: Array[Vector3] = []
	var spine_tiles: Array = road.get("spine_tiles", [])
	if not spine_tiles.is_empty():
		for raw_point in spine_tiles:
			var point: Vector2i = _dict_to_vec2i(raw_point)
			points.append(WorldGridProjection3DClass.logical_to_world(point, OVERLAY_Y + 0.03))
		return points

	var entry_point: Dictionary = road.get("entry_point", {})
	points.append(
		WorldGridProjection3DClass.logical_to_world(
			Vector2i(int(entry_point.get("x", 0)), int(entry_point.get("y", 0))),
			OVERLAY_Y + 0.03
		)
	)
	for control in road.get("control_points", []):
		points.append(
			Vector3(
				float(control.get("x", 0.0)) * WorldGridProjection3DClass.TILE_WORLD_SIZE,
				OVERLAY_Y + 0.03,
				float(control.get("y", 0.0)) * WorldGridProjection3DClass.TILE_WORLD_SIZE
			)
		)
	var attach_point: Dictionary = road.get("attach_point", {})
	points.append(
		WorldGridProjection3DClass.logical_to_world(
			Vector2i(int(attach_point.get("x", 0)), int(attach_point.get("y", 0))),
			OVERLAY_Y + 0.03
		)
	)
	return points

func _dict_to_vec2i(value) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Dictionary:
		return Vector2i(int(value.get("x", 0)), int(value.get("y", 0)))
	return Vector2i.ZERO

func _material(key: String, color: Color) -> StandardMaterial3D:
	if _material_cache.has(key):
		return _material_cache[key]
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = color
	_material_cache[key] = material
	return material

func _build_line_mesh(from: Vector3, to: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var immediate := ImmediateMesh.new()
	immediate.surface_begin(Mesh.PRIMITIVE_LINES, material)
	immediate.surface_add_vertex(from)
	immediate.surface_add_vertex(to)
	immediate.surface_end()
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = immediate
	return mesh_instance

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.free()
