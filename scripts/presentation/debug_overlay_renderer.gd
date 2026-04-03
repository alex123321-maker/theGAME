extends Node2D
class_name DebugOverlayRenderer

const WorldProjection = preload("res://scripts/presentation/world_projection.gd")
const PACK_ROOT := "res://assets/vendor/isometric_sketch_asset_pack"

const ENTRY_MARKER_PATH := PACK_ROOT + "/overlays/entry_marker.png"
const BUILDABLE_MASK_PATH := PACK_ROOT + "/overlays/buildable_mask.png"
const THREAT_HEAT_PATH := PACK_ROOT + "/overlays/threat_heat.png"

var map_data: MapData
var overlay_mode: String = "none"
var hover_logical: Vector2i = Vector2i.ZERO
var has_hover: bool = false
var _texture_cache: Dictionary = {}

func set_map_data(new_map_data: MapData) -> void:
	map_data = new_map_data
	queue_redraw()

func set_overlay_mode(new_overlay_mode: String) -> void:
	overlay_mode = new_overlay_mode
	queue_redraw()

func set_hover_tile(logical: Vector2i, is_valid: bool) -> void:
	hover_logical = logical
	has_hover = is_valid
	queue_redraw()

func _draw() -> void:
	if map_data == null:
		return

	if overlay_mode != "none":
		for tile in map_data.tiles:
			_draw_overlay_for_tile(tile)

	_draw_entry_markers()
	if has_hover:
		_draw_hover_highlight(hover_logical)

func _draw_overlay_for_tile(tile) -> void:
	if overlay_mode == "resources":
		var points := WorldProjection.get_diamond_points(Vector2i(tile.x, tile.y))
		var color: Color = _resource_overlay_color(tile)
		if color.a > 0.0:
			draw_colored_polygon(points, color)
		return

	var texture_path: String = _overlay_texture_path()
	if texture_path.is_empty():
		return

	var texture: Texture2D = _load_texture(texture_path)
	if texture == null:
		return

	var modulate: Color = _overlay_modulate_for_tile(tile)
	if modulate.a <= 0.0:
		return

	var logical := Vector2i(tile.x, tile.y)
	draw_texture(texture, WorldProjection.get_flat_tile_top_left(logical, texture.get_size()), modulate)

func _draw_entry_markers() -> void:
	var texture: Texture2D = _load_texture(ENTRY_MARKER_PATH)
	if texture == null:
		return
	for entry in map_data.entry_points:
		draw_texture(texture, WorldProjection.get_top_left_from_anchor(entry, texture.get_size()))

func _draw_hover_highlight(logical: Vector2i) -> void:
	var points: PackedVector2Array = WorldProjection.get_diamond_points(logical)
	var line_points: PackedVector2Array = _close_polygon(points)
	draw_colored_polygon(points, Color(1.0, 0.95, 0.35, 0.16))
	draw_polyline(line_points, Color(1.0, 0.75, 0.15, 0.95), 2.0)

func _overlay_texture_path() -> String:
	match overlay_mode:
		"buildable":
			return BUILDABLE_MASK_PATH
		"threat":
			return THREAT_HEAT_PATH
		_:
			return ""

func _overlay_modulate_for_tile(tile) -> Color:
	match overlay_mode:
		"buildable":
			return Color(0.1, 0.85, 0.2, 0.24) if tile.is_buildable else Color(0.95, 0.2, 0.25, 0.12)
		"threat":
			return Color(1.0, 1.0, 1.0, clampf(tile.threat_value * 0.48, 0.0, 0.48))
	return Color(0.0, 0.0, 0.0, 0.0)

func _resource_overlay_color(tile) -> Color:
	match tile.resource_tag:
		MapTypes.ResourceTag.WOOD:
			return Color(0.16, 0.76, 0.26, 0.18)
		MapTypes.ResourceTag.STONE:
			return Color(0.55, 0.56, 0.65, 0.18)
		MapTypes.ResourceTag.MIXED:
			return Color(0.74, 0.49, 0.17, 0.18)
		_:
			return Color(0.0, 0.0, 0.0, 0.0)

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

func _close_polygon(points: PackedVector2Array) -> PackedVector2Array:
	if points.size() == 0:
		return points
	var closed := PackedVector2Array(points)
	closed.push_back(points[0])
	return closed
