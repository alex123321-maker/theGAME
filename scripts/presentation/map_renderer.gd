extends Node2D
class_name MapRenderer

const WorldProjection = preload("res://scripts/presentation/world_projection.gd")
const IsometricTileResolverClass = preload("res://scripts/presentation/isometric_tile_resolver.gd")
const PropPlacementClass = preload("res://scripts/presentation/prop_placement.gd")
const TERRAIN_TILE_CLEANUP_SHADER = preload("res://scripts/presentation/terrain_tile_cleanup.gdshader")

var map_data: MapData
var is_grid_visible: bool = true
var is_props_visible: bool = true

var _tile_resolver := IsometricTileResolverClass.new()
var _prop_placement := PropPlacementClass.new()
var _texture_cache: Dictionary = {}
var _terrain_material: ShaderMaterial

var _terrain_root: Node2D
var _props_root: Node2D

func _ready() -> void:
	_terrain_root = _ensure_layer("TerrainRoot", true, 0)
	_props_root = _ensure_layer("PropsRoot", true, 10)
	_terrain_material = ShaderMaterial.new()
	_terrain_material.shader = TERRAIN_TILE_CLEANUP_SHADER

func set_map_data(new_map_data: MapData) -> void:
	map_data = new_map_data
	_rebuild_visual_layers()

func set_grid_visible(value: bool) -> void:
	is_grid_visible = value
	queue_redraw()

func set_props_visible(value: bool) -> void:
	is_props_visible = value
	_rebuild_props_layer()

func _draw() -> void:
	if map_data == null or not is_grid_visible:
		return

	for tile in map_data.tiles:
		var logical := Vector2i(tile.x, tile.y)
		var points: PackedVector2Array = WorldProjection.get_diamond_points(logical)
		var line_points: PackedVector2Array = _close_polygon(points)
		draw_polyline(line_points, Color(0.0, 0.0, 0.0, 0.18), 1.0)

func _rebuild_visual_layers() -> void:
	if _terrain_root == null or _props_root == null:
		return
	_clear_children(_terrain_root)
	_clear_children(_props_root)

	if map_data == null:
		queue_redraw()
		return

	for tile in map_data.tiles:
		var visual: Dictionary = _tile_resolver.resolve_tile_visual(tile, map_data)
		var path: String = String(visual.get("texture_path", ""))
		var texture: Texture2D = _load_texture(path)
		if texture == null:
			continue

		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		sprite.flip_h = bool(visual.get("flip_h", false))
		sprite.material = _terrain_material
		sprite.z_index = 0
		sprite.position = WorldProjection.logical_to_screen(Vector2i(tile.x, tile.y))
		_terrain_root.add_child(sprite)

	_rebuild_props_layer()
	queue_redraw()

func _rebuild_props_layer() -> void:
	if _props_root == null:
		return

	_clear_children(_props_root)
	if map_data == null or not is_props_visible:
		return

	var props: Array[Dictionary] = _prop_placement.build_props(map_data)
	for prop in props:
		var texture: Texture2D = _load_texture(String(prop["texture_path"]))
		if texture == null:
			continue
		var shadow_texture: Texture2D = _load_texture(String(prop["shadow_texture_path"]))
		var logical: Vector2i = prop["logical"]
		var offset: Vector2 = prop["offset"]
		var shadow_alpha: float = float(prop["shadow_alpha"])

		if shadow_texture != null:
			var shadow := Sprite2D.new()
			shadow.texture = shadow_texture
			shadow.centered = true
			shadow.modulate = Color(1.0, 1.0, 1.0, shadow_alpha)
			shadow.position = WorldProjection.logical_to_screen(logical) + WorldProjection.get_anchor_offset_for_height(shadow_texture.get_height())
			shadow.z_index = 0
			_props_root.add_child(shadow)

		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.centered = true
		sprite.position = WorldProjection.logical_to_screen(logical) + WorldProjection.get_anchor_offset_for_height(texture.get_height()) + offset
		sprite.z_index = 1
		_props_root.add_child(sprite)

func _ensure_layer(node_name: String, y_sort: bool, z_index: int) -> Node2D:
	var existing: Node = get_node_or_null(node_name)
	if existing != null:
		return existing as Node2D

	var layer := Node2D.new()
	layer.name = node_name
	layer.y_sort_enabled = y_sort
	layer.z_index = z_index
	add_child(layer)
	return layer

func _load_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if path.get_extension().to_lower() == "png" and FileAccess.file_exists(path):
		var image: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
		if image != null and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	else:
		texture = load(path)
	_texture_cache[path] = texture
	return texture

func _clear_children(node: Node) -> void:
	for child in node.get_children():
		child.free()

func _close_polygon(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() == 0:
		return points
	var closed := PackedVector2Array(points)
	closed.push_back(points[0])
	return closed
