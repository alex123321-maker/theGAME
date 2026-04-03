extends RefCounted
class_name TransitionResolver

func resolve(map_data: MapData) -> void:
	for tile in map_data.tiles:
		var road_sides: Dictionary = _side_flags(map_data, tile.x, tile.y, func(other) -> bool: return other.is_road)
		var water_sides: Dictionary = _side_flags(map_data, tile.x, tile.y, func(other) -> bool: return other.is_water)
		var blocker_sides: Dictionary = _side_flags(map_data, tile.x, tile.y, func(other) -> bool: return other.is_blocked)
		var clearing_sides: Dictionary = _side_flags(map_data, tile.x, tile.y, func(other) -> bool: return other.base_terrain_type == MapTypes.TerrainType.CLEARING)
		var flags := {
			"near_road": _any_side(road_sides),
			"road_sides": road_sides,
			"near_water": _any_side(water_sides),
			"water_sides": water_sides,
			"near_blocker": _any_side(blocker_sides),
			"blocker_sides": blocker_sides,
			"near_clearing": _any_side(clearing_sides),
			"clearing_sides": clearing_sides,
		}
		tile.transition_flags = flags
		tile.transition_type = _resolve_transition_type(tile, flags)
		if tile.transition_type == MapTypes.TransitionType.RAVINE_EDGE:
			tile.terrain_type = MapTypes.TerrainType.RAVINE_EDGE

func build_buildable_mask(map_data: MapData) -> void:
	for tile in map_data.tiles:
		tile.is_buildable = tile.region_type == MapTypes.RegionType.CENTER_CLEARING \
			and not tile.transition_flags.get("near_water", false) \
			and not tile.transition_flags.get("near_blocker", false) \
			and not tile.is_road
		tile.is_future_wallable = tile.base_terrain_type == MapTypes.TerrainType.CLEARING or tile.base_terrain_type == MapTypes.TerrainType.GROUND

func _resolve_transition_type(tile, flags: Dictionary) -> int:
	if tile.blocker_type == MapTypes.BlockerType.RAVINE and _is_exposed(flags):
		return MapTypes.TransitionType.RAVINE_EDGE
	if not tile.is_road and bool(flags.get("near_road", false)):
		return MapTypes.TransitionType.ROAD_EDGE
	if tile.base_terrain_type == MapTypes.TerrainType.GROUND or tile.base_terrain_type == MapTypes.TerrainType.CLEARING:
		if bool(flags.get("near_water", false)):
			return MapTypes.TransitionType.WET_EDGE
		if bool(flags.get("near_blocker", false)):
			return MapTypes.TransitionType.BLOCKER_EDGE
		if bool(flags.get("near_clearing", false)) and tile.base_terrain_type == MapTypes.TerrainType.GROUND:
			return MapTypes.TransitionType.CLEARING_EDGE
	return MapTypes.TransitionType.NONE

func _touches(map_data: MapData, x: int, y: int, predicate: Callable) -> bool:
	return _any_side(_side_flags(map_data, x, y, predicate))

func _side_flags(map_data: MapData, x: int, y: int, predicate: Callable) -> Dictionary:
	var result := {
		"up": false,
		"right": false,
		"down": false,
		"left": false,
	}
	var directions := {
		"up": Vector2i.UP,
		"right": Vector2i.RIGHT,
		"down": Vector2i.DOWN,
		"left": Vector2i.LEFT,
	}
	for side in directions.keys():
		var next: Vector2i = Vector2i(x, y) + directions[side]
		if not map_data.is_in_bounds(next.x, next.y):
			continue
		var neighbor = map_data.get_tile(next.x, next.y)
		if neighbor != null and predicate.call(neighbor):
			result[side] = true
	return result

func _any_side(flags: Dictionary) -> bool:
	for side in ["up", "right", "down", "left"]:
		if bool(flags.get(side, false)):
			return true
	return false

func _is_exposed(flags: Dictionary) -> bool:
	return bool(flags.get("near_clearing", false)) or bool(flags.get("near_road", false))
