extends RefCounted
class_name MacroShapePass

const GameConfigData = preload("res://autoload/game_config.gd")

## Initializes base terrain and creates a connected irregular village core.
func apply(map_data: MapData, rng: RandomNumberGenerator, config: Dictionary) -> void:
	var center := Vector2i(map_data.width / 2, map_data.height / 2)
	var village_tile_count: int = clampi(
		int(config.get("village_tile_count", GameConfigData.DEFAULT_VILLAGE_TILE_COUNT)),
		GameConfigData.MIN_VILLAGE_TILE_COUNT,
		GameConfigData.MAX_VILLAGE_TILE_COUNT
	)

	for y in range(map_data.height):
		for x in range(map_data.width):
			var tile = map_data.get_tile(x, y)
			tile.terrain_type = MapTypes.TerrainType.GROUND
			tile.height_class = MapTypes.HeightClass.MID
			tile.walk_cost = 1.0
			tile.is_buildable = false
			tile.is_future_wallable = false
			tile.resource_tag = MapTypes.ResourceTag.NONE
			tile.threat_value = 0.0
			tile.poi_tag = MapTypes.PoiTag.NONE

	var village_tiles: Array[Vector2i] = _build_irregular_village(center, village_tile_count, map_data, rng)
	for point in village_tiles:
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		tile.terrain_type = MapTypes.TerrainType.CLEARING
		tile.is_buildable = true
		tile.is_future_wallable = true
		map_data.central_zone_tiles.append(point)

func _build_irregular_village(
	center: Vector2i,
	target_count: int,
	map_data: MapData,
	rng: RandomNumberGenerator
) -> Array[Vector2i]:
	var village: Array[Vector2i] = [center]
	var selected := {center: true}
	var frontier: Array[Vector2i] = []
	var limit_radius: float = sqrt(float(target_count)) * 1.5

	_push_frontier_neighbors(center, map_data, selected, frontier)

	while village.size() < target_count and not frontier.is_empty():
		var frontier_index: int = rng.randi_range(0, frontier.size() - 1)
		var candidate: Vector2i = frontier[frontier_index]
		frontier.remove_at(frontier_index)

		if selected.has(candidate):
			continue
		if not map_data.is_in_bounds(candidate.x, candidate.y):
			continue

		var distance_to_center: float = candidate.distance_to(center)
		if distance_to_center > limit_radius:
			if rng.randf() < 0.92:
				continue
		elif distance_to_center > limit_radius * 0.82:
			if rng.randf() < 0.45:
				continue

		selected[candidate] = true
		village.append(candidate)
		_push_frontier_neighbors(candidate, map_data, selected, frontier)

	return village

func _push_frontier_neighbors(
	point: Vector2i,
	map_data: MapData,
	selected: Dictionary,
	frontier: Array[Vector2i]
) -> void:
	var directions: Array[Vector2i] = [
		Vector2i.UP,
		Vector2i.RIGHT,
		Vector2i.DOWN,
		Vector2i.LEFT,
	]
	for direction in directions:
		var next: Vector2i = point + direction
		if selected.has(next):
			continue
		if not map_data.is_in_bounds(next.x, next.y):
			continue
		if frontier.has(next):
			continue
		frontier.append(next)
