extends RefCounted
class_name WorldProjection

const TILE_WIDTH: float = 128.0
const TILE_HEIGHT: float = 64.0
const WORLD_ORIGIN: Vector2 = Vector2(0.0, 0.0)

static func logical_to_screen(logical: Vector2i) -> Vector2:
	var half_w: float = TILE_WIDTH * 0.5
	var half_h: float = TILE_HEIGHT * 0.5
	return Vector2(
		(float(logical.x) - float(logical.y)) * half_w,
		(float(logical.x) + float(logical.y)) * half_h
	) + WORLD_ORIGIN

static func screen_to_logical_approx(screen_position: Vector2) -> Vector2i:
	var half_w: float = TILE_WIDTH * 0.5
	var half_h: float = TILE_HEIGHT * 0.5
	var local: Vector2 = screen_position - WORLD_ORIGIN
	var lx: float = ((local.y / half_h) + (local.x / half_w)) * 0.5
	var ly: float = ((local.y / half_h) - (local.x / half_w)) * 0.5
	return Vector2i(roundi(lx), roundi(ly))

static func screen_to_logical_precise(screen_position: Vector2) -> Vector2i:
	var local: Vector2 = screen_position - WORLD_ORIGIN
	var half_w: float = TILE_WIDTH * 0.5
	var half_h: float = TILE_HEIGHT * 0.5
	var lx: float = ((local.y / half_h) + (local.x / half_w)) * 0.5
	var ly: float = ((local.y / half_h) - (local.x / half_w)) * 0.5
	var base := Vector2i(floori(lx), floori(ly))
	var best_tile := base
	var best_score: float = INF

	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var candidate := base + Vector2i(offset_x, offset_y)
			if not _point_is_inside_diamond(screen_position, candidate):
				continue
			var candidate_center: Vector2 = logical_to_screen(candidate)
			var score: float = candidate_center.distance_squared_to(screen_position)
			if score < best_score:
				best_score = score
				best_tile = candidate

	if best_score == INF:
		return screen_to_logical_approx(screen_position)
	return best_tile

static func get_tile_anchor_offset() -> Vector2:
	# Sprite anchor is bottom-center so visuals stay stable across variants.
	return get_anchor_offset_for_height(TILE_HEIGHT)

static func get_anchor_offset_for_height(sprite_height: float) -> Vector2:
	return Vector2(0.0, -sprite_height * 0.5)

static func get_top_left_from_anchor(logical: Vector2i, texture_size: Vector2) -> Vector2:
	return logical_to_screen(logical) + Vector2(-texture_size.x * 0.5, -texture_size.y)

static func get_flat_tile_top_left(logical: Vector2i, texture_size: Vector2) -> Vector2:
	return logical_to_screen(logical) - (texture_size * 0.5)

static func get_diamond_points(logical: Vector2i) -> PackedVector2Array:
	var center: Vector2 = logical_to_screen(logical)
	var half_w: float = TILE_WIDTH * 0.5
	var half_h: float = TILE_HEIGHT * 0.5
	return PackedVector2Array([
		center + Vector2(0.0, -half_h),
		center + Vector2(half_w, 0.0),
		center + Vector2(0.0, half_h),
		center + Vector2(-half_w, 0.0),
	])

static func _point_is_inside_diamond(screen_position: Vector2, logical: Vector2i) -> bool:
	var center: Vector2 = logical_to_screen(logical)
	var half_w: float = TILE_WIDTH * 0.5
	var half_h: float = TILE_HEIGHT * 0.5
	var delta: Vector2 = screen_position - center
	var normalized: float = (absf(delta.x) / half_w) + (absf(delta.y) / half_h)
	return normalized <= 1.0
