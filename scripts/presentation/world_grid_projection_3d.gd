extends RefCounted
class_name WorldGridProjection3D

const TILE_WORLD_SIZE: float = 2.0
const TILE_WORLD_WIDTH: float = TILE_WORLD_SIZE
const TILE_WORLD_DEPTH: float = TILE_WORLD_SIZE

static func logical_to_world(logical: Vector2i, y: float = 0.0) -> Vector3:
	return Vector3(
		float(logical.x) * TILE_WORLD_SIZE,
		y,
		float(logical.y) * TILE_WORLD_SIZE
	)

static func world_to_logical(world_position: Vector3) -> Vector2i:
	return Vector2i(
		floori((world_position.x / TILE_WORLD_SIZE) + 0.5),
		floori((world_position.z / TILE_WORLD_SIZE) + 0.5)
	)

static func map_center_world(width: int, height: int, y: float = 0.0) -> Vector3:
	return Vector3(
		(float(width - 1) * TILE_WORLD_SIZE) * 0.5,
		y,
		(float(height - 1) * TILE_WORLD_SIZE) * 0.5
	)
