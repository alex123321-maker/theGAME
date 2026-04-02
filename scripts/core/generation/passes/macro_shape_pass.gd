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
			tile.height_class = _choose_height_class(y, map_data.height)
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
	var frontier: Array[Vector2i] = [center]
	var limit_radius: float = sqrt(float(target_count)) * 1.35
	var directions: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]

	while village.size() < target_count and not frontier.is_empty():
		var current: Vector2i = frontier[rng.randi_range(0, frontier.size() - 1)]
		var direction: Vector2i = directions[rng.randi_range(0, directions.size() - 1)]
		var next: Vector2i = current + direction

		if selected.has(next):
			frontier.erase(current)
			continue
		if not map_data.is_in_bounds(next.x, next.y):
			frontier.erase(current)
			continue
		if next.distance_to(center) > limit_radius and rng.randf() < 0.85:
			continue

		selected[next] = true
		village.append(next)
		frontier.append(next)

		if rng.randf() < 0.18 and frontier.size() > 8:
			frontier.remove_at(rng.randi_range(0, frontier.size() - 1))

	return village

func _choose_height_class(y: int, map_height: int) -> int:
	var band_ratio: float = float(y) / max(1.0, float(map_height - 1))
	if band_ratio < 0.33:
		return MapTypes.HeightClass.LOW
	if band_ratio < 0.66:
		return MapTypes.HeightClass.MID
	return MapTypes.HeightClass.HIGH
