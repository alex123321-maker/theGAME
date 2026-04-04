extends RefCounted
class_name MountainRegionBuilder

const WorldGridProjection3DClass = preload("res://scripts/presentation/world_grid_projection_3d.gd")
const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")

const MIN_VISIBLE_HEIGHT: float = 0.04
const PEAK_HEIGHT_SCALE: float = 1.22
const CLIFF_VERTICAL_SEGMENTS: int = 8
const CLIFF_HORIZONTAL_SEGMENTS: int = 6
const CLIFF_LEDGE_DEPTH: float = 1.15
const CLIFF_BREAKUP_STRENGTH: float = 0.85
const SHORE_TOP_FLARE_DEPTH: float = 0.95
const MIN_GEOMETRY_PUSH_DELTA: float = 0.03
const MIN_TRIANGLE_AREA_SQ: float = 0.0000005
const TOP_BLOCK_PUSH_MULTIPLIER: float = 0.30

func build_profiles(map_data: MapData) -> Array[Dictionary]:
	var raw_regions: Dictionary = {}
	var region_labels: Dictionary = {}
	var region_metadata: Dictionary = {}
	for raw_region in map_data.regions:
		var region: Dictionary = raw_region
		var metadata: Dictionary = region.get("metadata", {})
		if int(metadata.get("blocker_type", MapTypes.BlockerType.NONE)) != MapTypes.BlockerType.ROCK:
			continue
		var region_id: int = int(region.get("id", 0))
		region_labels[region_id] = String(region.get("label", "rock_region"))
		region_metadata[region_id] = metadata.duplicate(true)

	for raw_tile in map_data.tiles:
		var tile = raw_tile
		if not _is_mountain_tile(tile, region_labels):
			continue
		var point := Vector2i(tile.x, tile.y)
		var region_id: int = int(tile.region_id)
		if region_id == 0:
			region_id = -100000 - map_data.index_of(tile.x, tile.y)
		if not raw_regions.has(region_id):
			raw_regions[region_id] = {
				"id": region_id,
				"label": String(region_labels.get(region_id, "rock_region_%d" % region_id)),
				"seed": abs(int((map_data.seed * 92821) ^ (region_id * 68917))),
				"cells": [],
				"core_cells": [],
				"edge_cells": [],
				"cell_set": {},
				"core_set": {},
				"edge_set": {},
				"metadata": region_metadata.get(region_id, {}).duplicate(true),
				"role_map": {},
				"summit_profile_votes": {},
			}
		var profile: Dictionary = raw_regions[region_id]
		var cells: Array = profile["cells"]
		var cell_set: Dictionary = profile["cell_set"]
		if not cell_set.has(point):
			cells.append(point)
			cell_set[point] = true
		var role_map: Dictionary = profile["role_map"]
		if int(tile.rock_role) != MapTypes.RockRole.NONE:
			role_map[point] = int(tile.rock_role)
		if int(tile.rock_summit_profile) != MapTypes.RockSummitProfile.NONE:
			var votes: Dictionary = profile["summit_profile_votes"]
			votes[int(tile.rock_summit_profile)] = int(votes.get(int(tile.rock_summit_profile), 0)) + 1

		var is_explicit_core: bool = int(tile.rock_role) == MapTypes.RockRole.WALL \
			or int(tile.rock_role) == MapTypes.RockRole.SHELF \
			or int(tile.rock_role) == MapTypes.RockRole.SUMMIT
		if tile.blocker_type == MapTypes.BlockerType.ROCK or is_explicit_core or tile.debug_tags.has("rock_core"):
			var core_cells: Array = profile["core_cells"]
			var core_set: Dictionary = profile["core_set"]
			if not core_set.has(point):
				core_cells.append(point)
				core_set[point] = true
		var is_explicit_edge: bool = int(tile.rock_role) == MapTypes.RockRole.FOOT or int(tile.rock_role) == MapTypes.RockRole.TALUS
		if is_explicit_edge or tile.debug_tags.has("rock_edge"):
			var edge_cells: Array = profile["edge_cells"]
			var edge_set: Dictionary = profile["edge_set"]
			if not edge_set.has(point):
				edge_cells.append(point)
				edge_set[point] = true

	var profiles: Array[Dictionary] = []
	for region_key in raw_regions.keys():
		var profile: Dictionary = raw_regions[region_key]
		if profile.get("cells", []).size() < 2:
			continue
		_finalize_profile(profile, map_data)
		profiles.append(profile)

	profiles.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)
	return profiles

func build_mesh(profile: Dictionary):
	var cells: Array = profile.get("cells", [])
	var cell_set: Dictionary = profile.get("cell_set", {})
	var corner_samples: Dictionary = profile.get("corner_samples", {})
	var shore_sides: Dictionary = profile.get("shore_sides", {})
	if cells.is_empty() or corner_samples.is_empty():
		return null

	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_geometry: bool = false

	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		var nw_corner := Vector2i(cell.x, cell.y)
		var ne_corner := Vector2i(cell.x + 1, cell.y)
		var se_corner := Vector2i(cell.x + 1, cell.y + 1)
		var sw_corner := Vector2i(cell.x, cell.y + 1)

		var nw_sample: Dictionary = _corner_sample(corner_samples, nw_corner)
		var ne_sample: Dictionary = _corner_sample(corner_samples, ne_corner)
		var se_sample: Dictionary = _corner_sample(corner_samples, se_corner)
		var sw_sample: Dictionary = _corner_sample(corner_samples, sw_corner)

		var nw: Vector3 = _corner_world(nw_corner, nw_sample)
		var ne: Vector3 = _corner_world(ne_corner, ne_sample)
		var se: Vector3 = _corner_world(se_corner, se_sample)
		var sw: Vector3 = _corner_world(sw_corner, sw_sample)

		if maxf(maxf(nw.y, ne.y), maxf(se.y, sw.y)) > MIN_VISIBLE_HEIGHT:
			_add_blocky_top_face(
				surface,
				nw, nw_sample,
				sw, sw_sample,
				se, se_sample,
				ne, ne_sample,
				float(cell.x + cell.y * 12.3)
			)
			has_geometry = true

		var ground_nw: Vector3 = _ground_world(nw_corner, nw_sample)
		var ground_ne: Vector3 = _ground_world(ne_corner, ne_sample)
		var ground_se: Vector3 = _ground_world(se_corner, se_sample)
		var ground_sw: Vector3 = _ground_world(sw_corner, sw_sample)

		if not cell_set.has(Vector2i(cell.x, cell.y - 1)) and maxf(nw.y, ne.y) > MIN_VISIBLE_HEIGHT:
			_add_cliff_face(
				surface,
				nw,
				nw_sample,
				ne,
				ne_sample,
				ground_nw,
				ground_ne,
				Vector3(0.0, 0.0, -1.0),
				bool(shore_sides.get(_cell_side_key(cell, "north"), false))
			)
			has_geometry = true
		if not cell_set.has(Vector2i(cell.x + 1, cell.y)) and maxf(ne.y, se.y) > MIN_VISIBLE_HEIGHT:
			_add_cliff_face(
				surface,
				ne,
				ne_sample,
				se,
				se_sample,
				ground_ne,
				ground_se,
				Vector3(1.0, 0.0, 0.0),
				bool(shore_sides.get(_cell_side_key(cell, "east"), false))
			)
			has_geometry = true
		if not cell_set.has(Vector2i(cell.x, cell.y + 1)) and maxf(se.y, sw.y) > MIN_VISIBLE_HEIGHT:
			_add_cliff_face(
				surface,
				se,
				se_sample,
				sw,
				sw_sample,
				ground_se,
				ground_sw,
				Vector3(0.0, 0.0, 1.0),
				bool(shore_sides.get(_cell_side_key(cell, "south"), false))
			)
			has_geometry = true
		if not cell_set.has(Vector2i(cell.x - 1, cell.y)) and maxf(sw.y, nw.y) > MIN_VISIBLE_HEIGHT:
			_add_cliff_face(
				surface,
				sw,
				sw_sample,
				nw,
				nw_sample,
				ground_sw,
				ground_nw,
				Vector3(-1.0, 0.0, 0.0),
				bool(shore_sides.get(_cell_side_key(cell, "west"), false))
			)
			has_geometry = true

	if not has_geometry:
		return null
	surface.index()
	surface.generate_normals()
	return surface.commit()

func _is_mountain_tile(tile, rock_region_labels: Dictionary) -> bool:
	if tile.region_type != MapTypes.RegionType.BLOCKER_MASS:
		return false
	if rock_region_labels.has(int(tile.region_id)):
		return true
	if int(tile.rock_role) != MapTypes.RockRole.NONE:
		return true
	return tile.blocker_type == MapTypes.BlockerType.ROCK \
		or tile.debug_tags.has("rock_core") \
		or tile.debug_tags.has("rock_edge")

func _finalize_profile(profile: Dictionary, map_data: MapData) -> void:
	var cells: Array = profile.get("cells", [])
	var cell_set: Dictionary = profile.get("cell_set", {})
	var center := Vector2.ZERO
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		center += Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
	center /= maxf(1.0, float(cells.size()))

	var boundary_cells: Array[Vector2i] = []
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		var is_boundary: bool = false
		for neighbor in GenerationUtilsClass.cardinal_neighbors(cell):
			if not cell_set.has(neighbor):
				is_boundary = true
				break
		if is_boundary:
			boundary_cells.append(cell)
	if boundary_cells.is_empty():
		for raw_cell in cells:
			boundary_cells.append(raw_cell)

	var axis_data: Dictionary = _principal_axis(cells, center)
	var distance_map: Dictionary = _distance_field(cell_set, boundary_cells)
	var max_distance: int = 0
	for value in distance_map.values():
		max_distance = maxi(max_distance, int(value))

	var metadata: Dictionary = profile.get("metadata", {})
	var explicit_role_map: Dictionary = profile.get("role_map", {})
	var profile_type: String = _resolve_profile_type(metadata, axis_data, max_distance, boundary_cells.size(), cells.size())
	var type_config: Dictionary = _type_config(profile_type, axis_data, max_distance)
	var region_seed: int = int(profile.get("seed", 0))
	var summit_profile: String = _resolve_summit_profile(metadata, profile, profile_type, axis_data, max_distance, cells.size(), region_seed)
	var branches: Array = _build_secondary_branches(axis_data, type_config)
	var peak_height: float = _peak_height(max_distance, axis_data, profile_type, summit_profile)
	var edge_set: Dictionary = profile.get("edge_set", {})
	var core_set: Dictionary = profile.get("core_set", {})

	var context_map: Dictionary = {}
	var height_map: Dictionary = {}
	var zone_map: Dictionary = {}
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		var context: Dictionary = _build_cell_context(
			cell,
			center,
			distance_map,
			max_distance,
			axis_data,
			branches,
			type_config,
			region_seed,
			core_set.has(cell),
			edge_set.has(cell)
		)
		context["rock_role"] = int(explicit_role_map.get(cell, MapTypes.RockRole.NONE))
		var terraced: Dictionary = _apply_terraces(
			clampf(float(context.get("smooth01", 0.0)) + float(context.get("terrace_offset", 0.0)), 0.0, 1.0),
			int(type_config.get("terraces", 4)),
			float(type_config.get("terrace_softness", 0.12))
		)
		context["terrace_plateau"] = float(terraced.get("plateau", 0.0))
		context["terrace_cliff"] = float(terraced.get("cliff", 0.0))
		var height01: float = _shape_height01(
			clampf(float(terraced.get("value", 0.0)), 0.0, 1.0),
			context,
			summit_profile,
			type_config,
			cell,
			region_seed
		)
		if edge_set.has(cell):
			height01 *= 0.72
		height01 = maxf(height01, 0.05)
		context["height01"] = height01
		context_map[cell] = context
		height_map[cell] = peak_height * height01

	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		var context: Dictionary = context_map.get(cell, {})
		var relief: float = _local_relief(cell, height_map, cell_set, peak_height)
		zone_map[cell] = _build_zone_sample(context, relief, profile_type, summit_profile, type_config, edge_set.has(cell))

	profile["center"] = center
	profile["boundary_cells"] = boundary_cells
	profile["distance_map"] = distance_map
	profile["max_distance"] = max_distance
	profile["axis"] = axis_data
	profile["profile_type"] = profile_type
	profile["summit_profile"] = summit_profile
	profile["type_config"] = type_config
	profile["branches"] = branches
	profile["peak_height"] = peak_height
	profile["height_map"] = height_map
	profile["zone_map"] = zone_map
	profile["shore_sides"] = _build_shore_side_map(cells, cell_set, map_data)
	profile["corner_samples"] = _build_corner_samples(profile)

func _principal_axis(cells: Array, center: Vector2) -> Dictionary:
	var xx: float = 0.0
	var xy: float = 0.0
	var yy: float = 0.0
	var min_x: float = INF
	var max_x: float = -INF
	var min_y: float = INF
	var max_y: float = -INF
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		min_x = minf(min_x, float(cell.x))
		max_x = maxf(max_x, float(cell.x))
		min_y = minf(min_y, float(cell.y))
		max_y = maxf(max_y, float(cell.y))
		var offset := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) - center
		xx += offset.x * offset.x
		xy += offset.x * offset.y
		yy += offset.y * offset.y

	var trace: float = xx + yy
	var determinant: float = (xx * yy) - (xy * xy)
	var term: float = sqrt(maxf(0.0, (trace * trace * 0.25) - determinant))
	var lambda: float = (trace * 0.5) + term
	var direction := Vector2(xy, lambda - xx)
	if direction.length_squared() <= 0.0001:
		var x_span: float = max_x - min_x
		var y_span: float = max_y - min_y
		direction = Vector2.RIGHT if x_span >= y_span else Vector2.DOWN
	direction = direction.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)

	var min_along: float = INF
	var max_along: float = -INF
	var max_perp: float = 0.0
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		var offset := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5) - center
		var along: float = offset.dot(direction)
		var perp_value: float = absf(offset.dot(perpendicular))
		min_along = minf(min_along, along)
		max_along = maxf(max_along, along)
		max_perp = maxf(max_perp, perp_value)

	var major_span: float = maxf(1.0, max_along - min_along)
	var minor_span: float = maxf(1.0, max_perp * 2.0)
	return {
		"origin": center,
		"direction": direction,
		"perpendicular": perpendicular,
		"major_span": major_span,
		"minor_span": minor_span,
		"max_perp": max_perp,
		"min_along": min_along,
		"max_along": max_along,
		"elongation": (major_span + 1.0) / (minor_span + 1.0),
	}

func _distance_field(cell_set: Dictionary, boundary_cells: Array[Vector2i]) -> Dictionary:
	var distance_map: Dictionary = {}
	var queue: Array[Vector2i] = []
	for point in boundary_cells:
		if distance_map.has(point):
			continue
		distance_map[point] = 0
		queue.append(point)
	var index: int = 0
	while index < queue.size():
		var point: Vector2i = queue[index]
		index += 1
		var distance_value: int = int(distance_map.get(point, 0))
		for neighbor in GenerationUtilsClass.cardinal_neighbors(point):
			if not cell_set.has(neighbor) or distance_map.has(neighbor):
				continue
			distance_map[neighbor] = distance_value + 1
			queue.append(neighbor)

	return distance_map

func _classify_profile_type(axis_data: Dictionary, max_distance: int, boundary_count: int, cell_count: int) -> String:
	var elongation: float = float(axis_data.get("elongation", 1.0))
	var minor_span: float = float(axis_data.get("minor_span", 1.0))
	var boundary_ratio: float = float(boundary_count) / maxf(1.0, float(cell_count))
	if max_distance <= 1 or (boundary_ratio > 0.64 and minor_span < 6.0):
		return "broken_cliff"
	if elongation >= 1.85 and minor_span <= 7.5:
		return "ridge"
	return "massif"

func _resolve_profile_type(
	metadata: Dictionary,
	axis_data: Dictionary,
	max_distance: int,
	boundary_count: int,
	cell_count: int
) -> String:
	var explicit_profile: String = String(metadata.get("rock_mass_profile", ""))
	if explicit_profile == "ridge" or explicit_profile == "massif":
		return explicit_profile
	return _classify_profile_type(axis_data, max_distance, boundary_count, cell_count)

func _resolve_summit_profile(
	metadata: Dictionary,
	profile: Dictionary,
	profile_type: String,
	axis_data: Dictionary,
	max_distance: int,
	cell_count: int,
	region_seed: int
) -> String:
	var explicit_value: int = int(metadata.get("rock_summit_profile", MapTypes.RockSummitProfile.NONE))
	if explicit_value == MapTypes.RockSummitProfile.NONE:
		var votes: Dictionary = profile.get("summit_profile_votes", {})
		var best_vote: int = 0
		for key in votes.keys():
			var count: int = int(votes.get(key, 0))
			if count <= best_vote:
				continue
			best_vote = count
			explicit_value = int(key)
	if explicit_value != MapTypes.RockSummitProfile.NONE:
		return MapTypes.rock_summit_profile_name(explicit_value)
	return _select_summit_profile(profile_type, axis_data, max_distance, cell_count, region_seed)

func _type_config(profile_type: String, _axis_data: Dictionary, max_distance: int) -> Dictionary:
	match profile_type:
		"ridge":
			return {
				"terraces": 3,
				"terrace_softness": 0.10,
				"ridge_weight": 0.84,
				"branch_weight": 0.12,
				"branch_count": 1 if max_distance >= 2 else 0,
				"silhouette_amp": 0.30,
				"body_noise": 0.04,
				"terrace_noise": 0.08,
				"foot_width": 0.52,
				"cap_threshold": 0.82,
				"depth_curve": 1.42,
				"body_curve": 0.90,
				"wall_start": 0.20,
				"wall_end": 0.72,
				"summit_start": 0.84,
				"foot_scale": 0.74,
			}
		"broken_cliff":
			return {
				"terraces": 3 if max_distance <= 2 else 4,
				"terrace_softness": 0.09,
				"ridge_weight": 0.24,
				"branch_weight": 0.0,
				"branch_count": 0,
				"silhouette_amp": 0.38,
				"body_noise": 0.04,
				"terrace_noise": 0.10,
				"foot_width": 0.62,
				"cap_threshold": 0.86,
				"depth_curve": 1.22,
				"body_curve": 0.96,
				"wall_start": 0.18,
				"wall_end": 0.74,
				"summit_start": 0.80,
				"foot_scale": 0.72,
			}
		_:
			return {
				"terraces": 4 if max_distance >= 4 else 3,
				"terrace_softness": 0.08,
				"ridge_weight": 0.52,
				"branch_weight": 0.32,
				"branch_count": 2 if max_distance >= 3 else 1,
				"silhouette_amp": 0.34,
				"body_noise": 0.04,
				"terrace_noise": 0.10,
				"foot_width": 0.58,
				"cap_threshold": 0.74,
				"depth_curve": 1.10,
				"body_curve": 0.88,
				"wall_start": 0.16,
				"wall_end": 0.78,
				"summit_start": 0.76,
				"foot_scale": 0.70,
			}

func _select_summit_profile(
	profile_type: String,
	axis_data: Dictionary,
	max_distance: int,
	cell_count: int,
	region_seed: int
) -> String:
	if profile_type == "ridge":
		return "peak"
	if profile_type == "broken_cliff":
		return "broken_top"

	var elongation: float = float(axis_data.get("elongation", 1.0))
	var minor_span: float = float(axis_data.get("minor_span", 1.0))
	var is_wide_mass: bool = minor_span >= 7.5 and max_distance >= 3 and cell_count >= 24
	var is_medium_mass: bool = minor_span >= 6.0 and max_distance >= 3 and cell_count >= 18
	var selector: int = abs(region_seed) % 100

	if is_wide_mass and elongation <= 1.45:
		return "plateau" if selector < 46 else "broken_top"
	if is_medium_mass and elongation <= 1.75:
		return "broken_top" if selector < 62 else "peak"
	return "peak"

func _build_secondary_branches(axis_data: Dictionary, type_config: Dictionary) -> Array:
	var branch_count: int = int(type_config.get("branch_count", 0))
	if branch_count <= 0:
		return []
	var branches: Array = []
	var axis_origin: Vector2 = axis_data.get("origin", Vector2.ZERO)
	var direction: Vector2 = axis_data.get("direction", Vector2.RIGHT)
	var perpendicular: Vector2 = axis_data.get("perpendicular", Vector2.DOWN)
	var major_span: float = float(axis_data.get("major_span", 1.0))
	var minor_span: float = float(axis_data.get("minor_span", 1.0))
	var offsets: Array = [-0.18, 0.22]
	if branch_count == 1:
		offsets = [0.0]
	for index in range(mini(branch_count, offsets.size())):
		var branch_origin: Vector2 = axis_origin + (direction * major_span * float(offsets[index]))
		var sign: float = -1.0 if index % 2 == 0 else 1.0
		var branch_dir: Vector2 = ((direction * 0.22) + (perpendicular * sign * 0.78)).normalized()
		branches.append({
			"from": branch_origin,
			"to": branch_origin + (branch_dir * maxf(2.0, minor_span * 0.82)),
			"width": maxf(1.2, minor_span * 0.32),
		})
	return branches

func _peak_height(max_distance: int, axis_data: Dictionary, profile_type: String, summit_profile: String) -> float:
	var major_span: float = float(axis_data.get("major_span", 1.0))
	var minor_span: float = float(axis_data.get("minor_span", 1.0))
	var base_height: float = 1.10 + (float(max_distance) * 0.98) + (major_span * 0.12) + (minor_span * 0.09)
	var thickness_boost: float = 1.0
	if max_distance <= 1:
		thickness_boost = 2.40
	elif max_distance == 2:
		thickness_boost = 1.85
	elif max_distance == 3:
		thickness_boost = 1.35
	base_height *= thickness_boost

	match profile_type:
		"ridge":
			base_height *= 1.12
		"broken_cliff":
			base_height *= 1.18
		_:
			base_height *= 1.18

	match summit_profile:
		"plateau":
			base_height *= 1.08
		"broken_top":
			base_height *= 1.04

	base_height *= PEAK_HEIGHT_SCALE

	return clampf(base_height, 2.8, 14.0)

func _build_cell_context(
	cell: Vector2i,
	center: Vector2,
	distance_map: Dictionary,
	max_distance: int,
	axis_data: Dictionary,
	branches: Array,
	type_config: Dictionary,
	region_seed: int,
	is_core: bool,
	is_edge: bool
) -> Dictionary:
	var cell_center := Vector2(float(cell.x) + 0.5, float(cell.y) + 0.5)
	var depth01: float = (float(distance_map.get(cell, 0)) + 0.45) / (float(max_distance) + 1.25)
	depth01 = clampf(depth01, 0.0, 1.0)

	var axis_origin: Vector2 = axis_data.get("origin", center)
	var axis_direction: Vector2 = axis_data.get("direction", Vector2.RIGHT)
	var axis_perpendicular: Vector2 = axis_data.get("perpendicular", Vector2.DOWN)
	var max_perp: float = maxf(0.8, float(axis_data.get("max_perp", 1.0)))
	var along: float = (cell_center - axis_origin).dot(axis_direction)
	var along01: float = inverse_lerp(float(axis_data.get("min_along", -1.0)), float(axis_data.get("max_along", 1.0)), along)
	along01 = clampf(along01, 0.0, 1.0)
	var perp_distance: float = absf((cell_center - axis_origin).dot(axis_perpendicular))
	var primary_ridge: float = 1.0 - clampf(perp_distance / (max_perp + 0.9), 0.0, 1.0)
	primary_ridge = pow(maxf(primary_ridge, 0.0), 1.7)

	var secondary_ridge: float = 0.0
	for branch in branches:
		var branch_from: Vector2 = branch.get("from", cell_center)
		var branch_to: Vector2 = branch.get("to", cell_center)
		var branch_width: float = maxf(0.8, float(branch.get("width", 1.0)))
		var branch_distance: float = _distance_to_segment_2d(cell_center, branch_from, branch_to)
		var branch_value: float = 1.0 - clampf(branch_distance / branch_width, 0.0, 1.0)
		secondary_ridge = maxf(secondary_ridge, pow(branch_value, 1.5))

	var depth_curve: float = pow(depth01, float(type_config.get("depth_curve", 1.32)))
	var smooth01: float = depth_curve * (
		0.70
		+ (primary_ridge * float(type_config.get("ridge_weight", 0.45)))
		+ (secondary_ridge * float(type_config.get("branch_weight", 0.18)))
	)
	smooth01 *= 0.88 + (sin(along01 * PI) * 0.12)
	smooth01 += (_noise_01(cell.x, cell.y, region_seed) - 0.5) * float(type_config.get("body_noise", 0.05))
	if is_core:
		smooth01 += 0.08
	if is_edge:
		smooth01 *= 0.78

	var terrace_phase: float = sin((along01 * TAU * 1.35) + (float(region_seed % 19) * 0.17)) * 0.05
	var terrace_noise: float = (_noise_01(cell.x + 17, cell.y - 9, region_seed * 3 + 11) - 0.5) * float(type_config.get("terrace_noise", 0.12))
	return {
		"depth01": depth01,
		"primary_ridge": clampf(primary_ridge, 0.0, 1.0),
		"secondary_ridge": clampf(secondary_ridge, 0.0, 1.0),
		"along01": along01,
		"smooth01": clampf(smooth01, 0.0, 1.0),
		"terrace_offset": terrace_phase + terrace_noise + (secondary_ridge * 0.05),
	}

func _shape_height01(
	base_height01: float,
	context: Dictionary,
	summit_profile: String,
	type_config: Dictionary,
	cell: Vector2i,
	region_seed: int
) -> float:
	var height01: float = clampf(base_height01, 0.0, 1.0)
	var rock_role: int = int(context.get("rock_role", MapTypes.RockRole.NONE))
	var wall_mask: float = smoothstep(
		float(type_config.get("wall_start", 0.18)),
		float(type_config.get("wall_end", 0.78)),
		height01
	)
	var body_height: float = pow(maxf(height01, 0.0), float(type_config.get("body_curve", 0.92)))
	height01 = lerpf(height01 * float(type_config.get("foot_scale", 0.72)), body_height, wall_mask)

	var ridge: float = maxf(float(context.get("primary_ridge", 0.0)), float(context.get("secondary_ridge", 0.0)) * 0.85)
	var summit_start: float = float(type_config.get("summit_start", 0.78))
	var summit_mask: float = smoothstep(summit_start - 0.08, 0.98, height01)

	match rock_role:
		MapTypes.RockRole.FOOT:
			height01 *= 0.16
		MapTypes.RockRole.TALUS:
			height01 = lerpf(height01 * 0.22, 0.18 + ridge * 0.06, 0.74)
		MapTypes.RockRole.SHELF:
			height01 = maxf(height01, 0.44 + (float(context.get("terrace_plateau", 0.0)) * 0.10) + ridge * 0.05)
		MapTypes.RockRole.WALL:
			height01 = maxf(height01, 0.56 + ridge * 0.10)
		MapTypes.RockRole.SUMMIT:
			height01 = maxf(height01, 0.78 + ridge * 0.05)

	match summit_profile:
		"plateau":
			var plateau_noise: float = (_noise_01(cell.x + 41, cell.y - 19, region_seed * 7 + 23) - 0.5) * 0.05
			var plateau_level: float = 0.80 + (float(context.get("terrace_plateau", 0.0)) * 0.04) + (ridge * 0.03)
			var plateau_target: float = plateau_level + (smoothstep(summit_start, 1.0, height01) * 0.11) + plateau_noise
			height01 = lerpf(height01, clampf(plateau_target, 0.0, 0.98), summit_mask * 0.84)
			height01 += summit_mask * 0.04
		"broken_top":
			var break_noise: float = (_noise_01(cell.x - 27, cell.y + 33, region_seed * 11 + 17) - 0.5) * 0.10
			var broken_target: float = 0.79 + (smoothstep(summit_start, 1.0, height01) * 0.13) + (ridge * 0.05) + break_noise
			height01 = lerpf(height01, clampf(broken_target, 0.0, 1.0), summit_mask * 0.66)
			height01 += summit_mask * ridge * 0.05
		_:
			height01 += summit_mask * (0.05 + ridge * 0.08)
			height01 = lerpf(height01, pow(clampf(height01, 0.0, 1.0), 0.86), summit_mask * 0.42)

	return clampf(height01, 0.0, 1.0)

func _apply_terraces(value: float, terraces: int, softness: float) -> Dictionary:
	var count: int = maxi(1, terraces)
	var scaled: float = clampf(value, 0.0, 0.9999) * float(count)
	var level: float = floor(scaled)
	var local: float = scaled - level
	var step_mix: float = smoothstep(0.5 - softness, 0.5 + softness, local)
	var cliff: float = pow(1.0 - clampf(absf(local - 0.5) / 0.5, 0.0, 1.0), 1.9)
	return {
		"value": (level + step_mix) / float(count),
		"cliff": cliff,
		"plateau": clampf(1.0 - (cliff * 1.1), 0.0, 1.0),
	}

func _local_relief(cell: Vector2i, height_map: Dictionary, cell_set: Dictionary, peak_height: float) -> float:
	var current_height: float = float(height_map.get(cell, 0.0))
	var max_relief: float = 0.0
	for neighbor in GenerationUtilsClass.cardinal_neighbors(cell):
		if not cell_set.has(neighbor):
			max_relief = maxf(max_relief, current_height / maxf(peak_height, 0.001))
			continue
		var neighbor_height: float = float(height_map.get(neighbor, current_height))
		max_relief = maxf(max_relief, absf(current_height - neighbor_height) / maxf(peak_height, 0.001))
	return clampf(max_relief, 0.0, 1.0)

func _build_zone_sample(
	context: Dictionary,
	relief: float,
	profile_type: String,
	summit_profile: String,
	type_config: Dictionary,
	is_edge: bool
) -> Dictionary:
	var height01: float = float(context.get("height01", 0.0))
	var depth01: float = float(context.get("depth01", 0.0))
	var rock_role: int = int(context.get("rock_role", MapTypes.RockRole.NONE))
	var ridge: float = maxf(float(context.get("primary_ridge", 0.0)), float(context.get("secondary_ridge", 0.0)) * 0.85)
	var cliff: float = clampf((relief * 1.55) + (float(context.get("terrace_cliff", 0.0)) * 0.60), 0.0, 1.0)
	var foot_width: float = float(type_config.get("foot_width", 0.58))
	var foot: float = clampf((foot_width - depth01) / maxf(foot_width, 0.001), 0.0, 1.0)
	foot *= 1.0 - (height01 * 0.52)
	var cap: float = smoothstep(float(type_config.get("cap_threshold", 0.74)), 0.98, height01)
	cap *= 0.72 + (float(context.get("terrace_plateau", 0.0)) * 0.30)
	cap *= 1.0 - (cliff * 0.42)
	var ledge: float = float(context.get("terrace_plateau", 0.0)) * (1.0 - cap) * (0.55 + (ridge * 0.22))
	ledge *= 1.0 - (cliff * 0.38)

	match summit_profile:
		"plateau":
			cap = maxf(cap, smoothstep(float(type_config.get("cap_threshold", 0.74)) - 0.08, 0.94, height01) * 0.92)
			ledge *= 1.14
			cliff *= 0.92
		"broken_top":
			cap *= 0.90 + (float(context.get("terrace_plateau", 0.0)) * 0.12)
			ledge *= 1.18
			cliff = clampf(cliff + 0.06, 0.0, 1.0)
		_:
			cap *= 0.84 + (ridge * 0.18)
			cliff = clampf(cliff + (ridge * 0.05), 0.0, 1.0)

	match rock_role:
		MapTypes.RockRole.FOOT:
			foot = 1.0
			cliff *= 0.16
			cap = 0.0
			ledge *= 0.18
		MapTypes.RockRole.TALUS:
			foot = maxf(foot, 0.76)
			cliff *= 0.42
			cap *= 0.18
			ledge *= 0.42
		MapTypes.RockRole.SHELF:
			ledge = maxf(ledge, 0.82)
			cliff = maxf(cliff * 0.68, 0.26)
			cap = maxf(cap * 0.42, 0.12)
			foot *= 0.42
		MapTypes.RockRole.WALL:
			cliff = maxf(cliff, 0.82)
			foot *= 0.26
			cap *= 0.14
			ledge *= 0.36
		MapTypes.RockRole.SUMMIT:
			cap = maxf(cap, 0.92)
			cliff *= 0.54
			ledge = maxf(ledge, 0.34)
			foot *= 0.16

	match profile_type:
		"ridge":
			cap *= 0.86
			cliff = clampf(cliff + (ridge * 0.12), 0.0, 1.0)
		"broken_cliff":
			cap *= 0.58
			cliff = clampf(cliff + 0.14, 0.0, 1.0)
			ledge *= 0.78
		_:
			cap *= 1.05
			ledge *= 1.08

	if is_edge:
		foot = clampf(foot + 0.22, 0.0, 1.0)
		cliff = clampf(cliff + 0.10, 0.0, 1.0)
		cap *= 0.84

	return {
		"height": height01,
		"cap": clampf(cap, 0.0, 1.0),
		"cliff": clampf(cliff, 0.0, 1.0),
		"foot": clampf(foot, 0.0, 1.0),
		"ridge": clampf(ridge, 0.0, 1.0),
		"ledge": clampf(ledge, 0.0, 1.0),
	}

func _build_corner_samples(profile: Dictionary) -> Dictionary:
	var height_map: Dictionary = profile.get("height_map", {})
	var zone_map: Dictionary = profile.get("zone_map", {})
	var cell_set: Dictionary = profile.get("cell_set", {})
	var type_config: Dictionary = profile.get("type_config", {})
	var region_seed: int = int(profile.get("seed", 0))

	var corner_accumulator: Dictionary = {}
	var corner_offset_accumulator: Dictionary = {}
	for raw_cell in height_map.keys():
		var cell: Vector2i = raw_cell
		var height_value: float = float(height_map.get(cell, 0.0))
		var zone: Dictionary = zone_map.get(cell, {})
		for corner in [
			Vector2i(cell.x, cell.y),
			Vector2i(cell.x + 1, cell.y),
			Vector2i(cell.x + 1, cell.y + 1),
			Vector2i(cell.x, cell.y + 1),
		]:
			if not corner_accumulator.has(corner):
				corner_accumulator[corner] = {
					"height_sum": 0.0,
					"cap_sum": 0.0,
					"cliff_sum": 0.0,
					"foot_sum": 0.0,
					"ridge_sum": 0.0,
					"ledge_sum": 0.0,
					"count": 0,
				}
			var accumulator: Dictionary = corner_accumulator[corner]
			accumulator["height_sum"] = float(accumulator.get("height_sum", 0.0)) + height_value
			accumulator["cap_sum"] = float(accumulator.get("cap_sum", 0.0)) + float(zone.get("cap", 0.0))
			accumulator["cliff_sum"] = float(accumulator.get("cliff_sum", 0.0)) + float(zone.get("cliff", 0.0))
			accumulator["foot_sum"] = float(accumulator.get("foot_sum", 0.0)) + float(zone.get("foot", 0.0))
			accumulator["ridge_sum"] = float(accumulator.get("ridge_sum", 0.0)) + float(zone.get("ridge", 0.0))
			accumulator["ledge_sum"] = float(accumulator.get("ledge_sum", 0.0)) + float(zone.get("ledge", 0.0))
			accumulator["count"] = int(accumulator.get("count", 0)) + 1

		for side_name in ["north", "east", "south", "west"]:
			var neighbor: Vector2i = _boundary_neighbor(cell, side_name)
			if cell_set.has(neighbor):
				continue
			var side_dir: Vector2 = _boundary_side_dir(side_name)
			for raw_corner in _side_corners(cell, side_name):
				var corner: Vector2i = raw_corner
				if not corner_offset_accumulator.has(corner):
					corner_offset_accumulator[corner] = {
						"offset": Vector2.ZERO,
						"count": 0,
					}
				var zone_strength: float = clampf(
					(float(zone.get("cliff", 0.0)) * 0.55)
					+ (float(zone.get("foot", 0.0)) * 0.25)
					+ (float(zone.get("ledge", 0.0)) * 0.20),
					0.18,
					1.0
				)
				var coarse_noise: float = 0.72 + ((_noise_01(corner.x, corner.y, region_seed * 5 + 7) - 0.5) * 0.60)
				var entry: Dictionary = corner_offset_accumulator[corner]
				entry["offset"] = Vector2(entry.get("offset", Vector2.ZERO)) + (side_dir * float(type_config.get("silhouette_amp", 0.28)) * zone_strength * coarse_noise)
				entry["count"] = int(entry.get("count", 0)) + 1

	var samples: Dictionary = {}
	for raw_corner in corner_accumulator.keys():
		var corner: Vector2i = raw_corner
		var accumulator: Dictionary = corner_accumulator[corner]
		var count: float = maxf(1.0, float(accumulator.get("count", 1)))
		var sample_height: float = float(accumulator.get("height_sum", 0.0)) / count
		var offset := Vector2.ZERO
		if corner_offset_accumulator.has(corner):
			var entry: Dictionary = corner_offset_accumulator[corner]
			offset = Vector2(entry.get("offset", Vector2.ZERO)) / maxf(1.0, float(entry.get("count", 1)))
			if offset.length_squared() > 0.000001:
				var max_corner_offset: float = WorldGridProjection3DClass.TILE_WORLD_SIZE * 0.14
				var high_alt_dampen: float = lerpf(1.0, 0.58, smoothstep(5.0, 10.0, sample_height))
				var allowed_offset: float = max_corner_offset * high_alt_dampen
				if offset.length() > allowed_offset:
					offset = offset.normalized() * allowed_offset
		samples[corner] = {
			"height": sample_height,
			"cap": float(accumulator.get("cap_sum", 0.0)) / count,
			"cliff": float(accumulator.get("cliff_sum", 0.0)) / count,
			"foot": float(accumulator.get("foot_sum", 0.0)) / count,
			"ridge": float(accumulator.get("ridge_sum", 0.0)) / count,
			"ledge": float(accumulator.get("ledge_sum", 0.0)) / count,
			"offset": offset,
		}
	return samples

func _corner_sample(corner_samples: Dictionary, corner: Vector2i) -> Dictionary:
	if corner_samples.has(corner):
		return corner_samples[corner]
	return {
		"height": 0.0,
		"cap": 0.0,
		"cliff": 0.0,
		"foot": 1.0,
		"ridge": 0.0,
		"ledge": 0.0,
		"offset": Vector2.ZERO,
	}

func _corner_world(corner: Vector2i, sample: Dictionary) -> Vector3:
	var half_tile: float = WorldGridProjection3DClass.TILE_WORLD_SIZE * 0.5
	var offset: Vector2 = sample.get("offset", Vector2.ZERO)
	return Vector3(
		(float(corner.x) * WorldGridProjection3DClass.TILE_WORLD_SIZE) - half_tile + offset.x,
		float(sample.get("height", 0.0)),
		(float(corner.y) * WorldGridProjection3DClass.TILE_WORLD_SIZE) - half_tile + offset.y
	)

func _ground_world(corner: Vector2i, sample: Dictionary) -> Vector3:
	var half_tile: float = WorldGridProjection3DClass.TILE_WORLD_SIZE * 0.5
	var offset: Vector2 = Vector2(sample.get("offset", Vector2.ZERO)) * 0.55
	return Vector3(
		(float(corner.x) * WorldGridProjection3DClass.TILE_WORLD_SIZE) - half_tile + offset.x,
		0.0,
		(float(corner.y) * WorldGridProjection3DClass.TILE_WORLD_SIZE) - half_tile + offset.y
	)

func _vertex_color(sample: Dictionary) -> Color:
	return Color(
		clampf(float(sample.get("cap", 0.0)), 0.0, 1.0),
		clampf(float(sample.get("cliff", 0.0)), 0.0, 1.0),
		clampf(float(sample.get("foot", 0.0)), 0.0, 1.0),
		clampf(float(sample.get("ridge", 0.0)), 0.0, 1.0)
	)

func _ground_sample(sample: Dictionary) -> Dictionary:
	return {
		"height": 0.0,
		"cap": 0.0,
		"cliff": clampf(float(sample.get("cliff", 0.0)) * 0.45, 0.0, 1.0),
		"foot": 1.0,
		"ridge": clampf(float(sample.get("ridge", 0.0)) * 0.22, 0.0, 1.0),
		"ledge": 0.0,
		"offset": Vector2(sample.get("offset", Vector2.ZERO)) * 0.55,
	}

func _face_sample(sample: Dictionary, cliff_boost: float, foot_boost: float, ridge_scale: float = 0.86) -> Dictionary:
	return {
		"cap": clampf(float(sample.get("cap", 0.0)) * 0.18, 0.0, 1.0),
		"cliff": clampf(maxf(float(sample.get("cliff", 0.0)), cliff_boost), 0.0, 1.0),
		"foot": clampf(maxf(float(sample.get("foot", 0.0)), foot_boost), 0.0, 1.0),
		"ridge": clampf(float(sample.get("ridge", 0.0)) * ridge_scale, 0.0, 1.0),
		"ledge": clampf(float(sample.get("ledge", 0.0)) * 0.65, 0.0, 1.0),
		"offset": sample.get("offset", Vector2.ZERO),
	}

func _sample_lerp(sample_a: Dictionary, sample_b: Dictionary, t: float) -> Dictionary:
	return {
		"height": lerpf(float(sample_a.get("height", 0.0)), float(sample_b.get("height", 0.0)), t),
		"cap": lerpf(float(sample_a.get("cap", 0.0)), float(sample_b.get("cap", 0.0)), t),
		"cliff": lerpf(float(sample_a.get("cliff", 0.0)), float(sample_b.get("cliff", 0.0)), t),
		"foot": lerpf(float(sample_a.get("foot", 0.0)), float(sample_b.get("foot", 0.0)), t),
		"ridge": lerpf(float(sample_a.get("ridge", 0.0)), float(sample_b.get("ridge", 0.0)), t),
		"ledge": lerpf(float(sample_a.get("ledge", 0.0)), float(sample_b.get("ledge", 0.0)), t),
		"offset": Vector2.ZERO,
	}

func _cliff_face_block_data(
	top_a: Vector3,
	top_a_sample: Dictionary,
	top_b: Vector3,
	top_b_sample: Dictionary,
	base_a: Vector3,
	base_b: Vector3,
	avg_cliff: float,
	avg_foot: float,
	avg_ledge: float,
	avg_ridge: float,
	u: float,
	v: float,
	phase: float,
	is_shore: bool
) -> Dictionary:
	var top_pos: Vector3 = top_a.lerp(top_b, u)
	var base_pos: Vector3 = base_a.lerp(base_b, u)
	var vertical_drop: float = maxf(0.001, top_pos.y - base_pos.y)
	var height_scale: float = clampf(vertical_drop / 3.8, 0.24, 1.0)
	var edge_fade: float = pow(maxf(sin(u * PI), 0.0), 1.10)
	var seam_lock_top: float = smoothstep(0.04, 0.18, v)
	var seam_lock_bottom: float = 1.0 - smoothstep(0.84, 0.98, v)
	var seam_lock: float = seam_lock_top * seam_lock_bottom
	
	var ledge_steps: float = 4.0 + floor((avg_cliff * 4.0) + (avg_ledge * 3.0))
	var step_phase: float = (v * ledge_steps) + (phase * 0.3)
	var blocky_v: float = floor(step_phase) / ledge_steps
	var step_local: float = step_phase - floor(step_phase)
	var step_mask: float = smoothstep(0.0, 0.15, step_local) * (1.0 - smoothstep(0.75, 1.0, step_local))
	
	var vertical_bands: float = 3.0 + (avg_cliff * 3.0)
	var blocky_u: float = floor(u * vertical_bands + phase * 2.0)
	var ledge_wave: float = sin(blocky_v * 13.0 + blocky_u * 7.0 + phase * TAU) * 0.5 + 0.5
	var ledge_mask: float = maxf(
		pow(ledge_wave, 1.5),
		step_mask * (0.6 + (avg_ledge * 0.4))
	)
	var breakup_wave: float = sin(blocky_u * 4.0 + blocky_v * 5.0 + phase * TAU) * 0.5 + 0.5
	
	var ledge_push: float = CLIFF_LEDGE_DEPTH
	ledge_push *= 0.5 + (avg_cliff * 0.5)
	ledge_push *= 0.6 + (avg_ledge * 0.4)
	ledge_push *= ledge_mask * edge_fade
	ledge_push *= 0.6 + (breakup_wave * CLIFF_BREAKUP_STRENGTH)
	
	var shore_flare: float = 0.0
	if is_shore:
		var upper_band: float = 1.0 - smoothstep(0.05, 0.45, v)
		var overhang: float = smoothstep(0.0, 0.1, v)
		var top_blockiness: float = 0.7 + (sin(blocky_u * 3.0 + phase * 4.0) * 0.5 + 0.5) * 0.3
		shore_flare = SHORE_TOP_FLARE_DEPTH
		shore_flare *= upper_band * overhang * edge_fade * top_blockiness
		shore_flare *= clampf((avg_cliff * 0.8) + 0.4, 0.4, 1.0)
	
	var max_push: float = WorldGridProjection3DClass.TILE_WORLD_SIZE * (0.36 if is_shore else 0.24)
	var push_scale: float = 0.62 if is_shore else 0.52
	var push_amount: float = clampf((ledge_push + shore_flare) * height_scale * seam_lock * push_scale, 0.0, max_push)
	
	var side_sample: Dictionary = _sample_lerp(top_a_sample, top_b_sample, u)
	var face_sample: Dictionary = _face_sample(side_sample, maxf(avg_cliff, 0.26), avg_foot, 0.86 + (avg_ridge * 0.10))
	var ground_sample: Dictionary = _ground_sample(side_sample)
	var ground_mix: float = smoothstep(0.46, 1.0, v)
	var color: Color = _vertex_color(face_sample).lerp(_vertex_color(ground_sample), ground_mix)
	if is_shore:
		color.g = clampf(color.g + ((1.0 - v) * 0.08), 0.0, 1.0)
		color.b = clampf(color.b + (v * 0.06), 0.0, 1.0)
	
	return {
		"push": push_amount,
		"color": color,
	}

func _add_blocky_top_face(
	surface: SurfaceTool,
	nw: Vector3, nw_sample: Dictionary,
	sw: Vector3, sw_sample: Dictionary,
	se: Vector3, se_sample: Dictionary,
	ne: Vector3, ne_sample: Dictionary,
	phase: float
) -> void:
	var segments: int = CLIFF_HORIZONTAL_SEGMENTS
	var pushes: Array = []
	var colors: Array = []
	
	for y in range(segments):
		var row_pushes: Array = []
		var row_colors: Array = []
		for x in range(segments):
			var u: float = (float(x) + 0.5) / float(segments)
			var v: float = (float(y) + 0.5) / float(segments)
			
			var edge_fade_u: float = pow(maxf(sin(u * PI), 0.0), 0.6)
			var edge_fade_v: float = pow(maxf(sin(v * PI), 0.0), 0.6)
			var seam_lock: float = edge_fade_u * edge_fade_v
			
			var blocky_u: float = floor(u * 5.0 + phase * 2.0)
			var blocky_v: float = floor(v * 4.0 + phase * 1.5)
			var bump: float = sin(blocky_u * 13.0 + blocky_v * 7.0 + phase * TAU) * 0.5 + 0.5
			bump = floor(bump * 3.0) / 3.0
			
			var push: float = bump * seam_lock * TOP_BLOCK_PUSH_MULTIPLIER * CLIFF_LEDGE_DEPTH
			row_pushes.append(push)
			
			var c_top = _vertex_color(nw_sample).lerp(_vertex_color(ne_sample), u)
			var c_bot = _vertex_color(sw_sample).lerp(_vertex_color(se_sample), u)
			row_colors.append(c_top.lerp(c_bot, v))
			
		pushes.append(row_pushes)
		colors.append(row_colors)

	for y in range(segments):
		var v0: float = float(y) / float(segments)
		var v1: float = float(y + 1) / float(segments)
		for x in range(segments):
			var u0: float = float(x) / float(segments)
			var u1: float = float(x + 1) / float(segments)
			
			var push: float = pushes[y][x]
			var color: Color = colors[y][x]
			
			var tp_u0: Vector3 = nw.lerp(ne, u0)
			var tp_u1: Vector3 = nw.lerp(ne, u1)
			var bp_u0: Vector3 = sw.lerp(se, u0)
			var bp_u1: Vector3 = sw.lerp(se, u1)
			
			var p_a: Vector3 = tp_u0.lerp(bp_u0, v0) + Vector3.UP * push
			var p_b: Vector3 = tp_u0.lerp(bp_u0, v1) + Vector3.UP * push
			var p_c: Vector3 = tp_u1.lerp(bp_u1, v1) + Vector3.UP * push
			var p_d: Vector3 = tp_u1.lerp(bp_u1, v0) + Vector3.UP * push
			
			_add_quad(surface, p_a, color, p_b, color, p_c, color, p_d, color)
			
			if x > 0 and (push - float(pushes[y][x-1])) > MIN_GEOMETRY_PUSH_DELTA:
				var prev_push: float = pushes[y][x-1]
				var p_prev_a: Vector3 = p_a - Vector3.UP * (push - prev_push)
				var p_prev_b: Vector3 = p_b - Vector3.UP * (push - prev_push)
				_add_quad(surface, p_a, color, p_prev_a, color, p_prev_b, color, p_b, color)
			elif x == 0 and push > MIN_GEOMETRY_PUSH_DELTA:
				var p_prev_a: Vector3 = p_a - Vector3.UP * push
				var p_prev_b: Vector3 = p_b - Vector3.UP * push
				_add_quad(surface, p_a, color, p_prev_a, color, p_prev_b, color, p_b, color)

			if x < segments - 1 and (push - float(pushes[y][x+1])) > MIN_GEOMETRY_PUSH_DELTA:
				var next_push: float = pushes[y][x+1]
				var p_next_d: Vector3 = p_d - Vector3.UP * (push - next_push)
				var p_next_c: Vector3 = p_c - Vector3.UP * (push - next_push)
				_add_quad(surface, p_c, color, p_next_c, color, p_next_d, color, p_d, color)
			elif x == segments - 1 and push > MIN_GEOMETRY_PUSH_DELTA:
				var p_next_d: Vector3 = p_d - Vector3.UP * push
				var p_next_c: Vector3 = p_c - Vector3.UP * push
				_add_quad(surface, p_c, color, p_next_c, color, p_next_d, color, p_d, color)

			if y > 0 and (push - float(pushes[y-1][x])) > MIN_GEOMETRY_PUSH_DELTA:
				var top_push: float = pushes[y-1][x]
				var p_top_a: Vector3 = p_a - Vector3.UP * (push - top_push)
				var p_top_d: Vector3 = p_d - Vector3.UP * (push - top_push)
				_add_quad(surface, p_d, color, p_top_d, color, p_top_a, color, p_a, color)
			elif y == 0 and push > MIN_GEOMETRY_PUSH_DELTA:
				var p_top_a: Vector3 = p_a - Vector3.UP * push
				var p_top_d: Vector3 = p_d - Vector3.UP * push
				_add_quad(surface, p_d, color, p_top_d, color, p_top_a, color, p_a, color)

			if y < segments - 1 and (push - float(pushes[y+1][x])) > MIN_GEOMETRY_PUSH_DELTA:
				var bot_push: float = pushes[y+1][x]
				var p_bot_b: Vector3 = p_b - Vector3.UP * (push - bot_push)
				var p_bot_c: Vector3 = p_c - Vector3.UP * (push - bot_push)
				_add_quad(surface, p_b, color, p_bot_b, color, p_bot_c, color, p_c, color)
			elif y == segments - 1 and push > MIN_GEOMETRY_PUSH_DELTA:
				var p_bot_b: Vector3 = p_b - Vector3.UP * push
				var p_bot_c: Vector3 = p_c - Vector3.UP * push
				_add_quad(surface, p_b, color, p_bot_b, color, p_bot_c, color, p_c, color)

func _add_cliff_face(
	surface: SurfaceTool,
	top_a: Vector3,
	top_a_sample: Dictionary,
	top_b: Vector3,
	top_b_sample: Dictionary,
	base_a: Vector3,
	base_b: Vector3,
	_outward: Vector3,
	is_shore: bool
) -> void:
	var avg_cliff: float = (float(top_a_sample.get("cliff", 0.0)) + float(top_b_sample.get("cliff", 0.0))) * 0.5
	var avg_foot: float = (float(top_a_sample.get("foot", 0.0)) + float(top_b_sample.get("foot", 0.0))) * 0.5
	var avg_ledge: float = (float(top_a_sample.get("ledge", 0.0)) + float(top_b_sample.get("ledge", 0.0))) * 0.5
	var avg_ridge: float = (float(top_a_sample.get("ridge", 0.0)) + float(top_b_sample.get("ridge", 0.0))) * 0.5
	var avg_height: float = ((top_a.y - base_a.y) + (top_b.y - base_b.y)) * 0.5
	if avg_height <= MIN_VISIBLE_HEIGHT:
		return
	
	if avg_height < 0.48:
		_add_quad(
			surface,
			top_a,
			_vertex_color(_face_sample(top_a_sample, maxf(avg_cliff, 0.26), avg_foot)),
			top_b,
			_vertex_color(_face_sample(top_b_sample, maxf(avg_cliff, 0.26), avg_foot)),
			base_b,
			_vertex_color(_ground_sample(top_b_sample)),
			base_a,
			_vertex_color(_ground_sample(top_a_sample))
		)
		return
	
	var outward: Vector3 = _outward.normalized() if _outward.length_squared() > 0.00001 else Vector3.ZERO
	var phase: float = _noise_01(
		int(roundi((top_a.x + top_b.x) * 1.7)),
		int(roundi((top_a.z + top_b.z) * 1.7)),
		int(roundi((top_a.y + top_b.y) * 23.0))
	)
	var vertical_segments: int = CLIFF_VERTICAL_SEGMENTS
	if avg_height < 1.6:
		vertical_segments = maxi(2, CLIFF_VERTICAL_SEGMENTS - 1)
	var horizontal_segments: int = CLIFF_HORIZONTAL_SEGMENTS
	if not is_shore and avg_height < 1.2:
		horizontal_segments = maxi(2, CLIFF_HORIZONTAL_SEGMENTS - 1)
	
	var grid_pushes: Array = []
	var grid_colors: Array = []
	for y_index in range(vertical_segments):
		var row_pushes: Array = []
		var row_colors: Array = []
		for x_index in range(horizontal_segments):
			var u: float = (float(x_index) + 0.5) / float(horizontal_segments)
			var v: float = (float(y_index) + 0.5) / float(vertical_segments)
			var block_data: Dictionary = _cliff_face_block_data(
				top_a, top_a_sample, top_b, top_b_sample, base_a, base_b,
				avg_cliff, avg_foot, avg_ledge, avg_ridge, u, v, phase, is_shore
			)
			row_pushes.append(float(block_data.get("push", 0.0)))
			row_colors.append(Color(block_data.get("color", Color.WHITE)))
		grid_pushes.append(row_pushes)
		grid_colors.append(row_colors)
	
	for y in range(vertical_segments):
		var v0: float = float(y) / float(vertical_segments)
		var v1: float = float(y + 1) / float(vertical_segments)
		for x in range(horizontal_segments):
			var u0: float = float(x) / float(horizontal_segments)
			var u1: float = float(x + 1) / float(horizontal_segments)
			
			var push: float = grid_pushes[y][x]
			var color: Color = grid_colors[y][x]
			
			var tp_u0: Vector3 = top_a.lerp(top_b, u0)
			var tp_u1: Vector3 = top_a.lerp(top_b, u1)
			var bp_u0: Vector3 = base_a.lerp(base_b, u0)
			var bp_u1: Vector3 = base_a.lerp(base_b, u1)
			
			var p_a: Vector3 = tp_u0.lerp(bp_u0, v0) + outward * push
			var p_b: Vector3 = tp_u1.lerp(bp_u1, v0) + outward * push
			var p_c: Vector3 = tp_u1.lerp(bp_u1, v1) + outward * push
			var p_d: Vector3 = tp_u0.lerp(bp_u0, v1) + outward * push
			
			_add_quad(surface, p_a, color, p_b, color, p_c, color, p_d, color)
			
			if x > 0 and (push - float(grid_pushes[y][x-1])) > MIN_GEOMETRY_PUSH_DELTA:
				var prev_push: float = grid_pushes[y][x-1]
				var p_prev_a: Vector3 = p_a - outward * (push - prev_push)
				var p_prev_d: Vector3 = p_d - outward * (push - prev_push)
				_add_quad(surface, p_prev_a, color, p_a, color, p_d, color, p_prev_d, color)
			elif x == 0 and push > MIN_GEOMETRY_PUSH_DELTA:
				var p_prev_a: Vector3 = p_a - outward * push
				var p_prev_d: Vector3 = p_d - outward * push
				_add_quad(surface, p_prev_a, color, p_a, color, p_d, color, p_prev_d, color)
			
			if x < horizontal_segments - 1 and (push - float(grid_pushes[y][x+1])) > MIN_GEOMETRY_PUSH_DELTA:
				var next_push: float = grid_pushes[y][x+1]
				var p_next_b: Vector3 = p_b - outward * (push - next_push)
				var p_next_c: Vector3 = p_c - outward * (push - next_push)
				_add_quad(surface, p_b, color, p_next_b, color, p_next_c, color, p_c, color)
			elif x == horizontal_segments - 1 and push > MIN_GEOMETRY_PUSH_DELTA:
				var p_next_b: Vector3 = p_b - outward * push
				var p_next_c: Vector3 = p_c - outward * push
				_add_quad(surface, p_b, color, p_next_b, color, p_next_c, color, p_c, color)
			
			if y > 0 and (push - float(grid_pushes[y-1][x])) > MIN_GEOMETRY_PUSH_DELTA:
				var top_push: float = grid_pushes[y-1][x]
				var p_top_a: Vector3 = p_a - outward * (push - top_push)
				var p_top_b: Vector3 = p_b - outward * (push - top_push)
				_add_quad(surface, p_top_a, color, p_top_b, color, p_b, color, p_a, color)
			elif y == 0 and push > MIN_GEOMETRY_PUSH_DELTA:
				var p_top_a: Vector3 = p_a - outward * push
				var p_top_b: Vector3 = p_b - outward * push
				_add_quad(surface, p_top_a, color, p_top_b, color, p_b, color, p_a, color)
			
			if y < vertical_segments - 1 and (push - float(grid_pushes[y+1][x])) > MIN_GEOMETRY_PUSH_DELTA:
				var bot_push: float = grid_pushes[y+1][x]
				var p_bot_d: Vector3 = p_d - outward * (push - bot_push)
				var p_bot_c: Vector3 = p_c - outward * (push - bot_push)
				_add_quad(surface, p_d, color, p_c, color, p_bot_c, color, p_bot_d, color)
			elif y == vertical_segments - 1 and push > MIN_GEOMETRY_PUSH_DELTA:
				var p_bot_d: Vector3 = p_d - outward * push
				var p_bot_c: Vector3 = p_c - outward * push
				_add_quad(surface, p_d, color, p_c, color, p_bot_c, color, p_bot_d, color)

func _add_quad(
	surface: SurfaceTool,
	a: Vector3,
	a_color: Color,
	b: Vector3,
	b_color: Color,
	c: Vector3,
	c_color: Color,
	d: Vector3,
	d_color: Color
) -> void:
	_add_triangle(surface, a, a_color, b, b_color, c, c_color)
	_add_triangle(surface, a, a_color, c, c_color, d, d_color)

func _add_triangle(
	surface: SurfaceTool,
	a: Vector3,
	a_color: Color,
	b: Vector3,
	b_color: Color,
	c: Vector3,
	c_color: Color
) -> void:
	if (b - a).cross(c - a).length_squared() <= MIN_TRIANGLE_AREA_SQ:
		return
	surface.set_smooth_group(0)
	surface.set_color(a_color)
	surface.add_vertex(a)
	surface.set_color(b_color)
	surface.add_vertex(b)
	surface.set_color(c_color)
	surface.add_vertex(c)

func _boundary_neighbor(cell: Vector2i, side_name: String) -> Vector2i:
	match side_name:
		"north":
			return cell + Vector2i.UP
		"east":
			return cell + Vector2i.RIGHT
		"south":
			return cell + Vector2i.DOWN
		_:
			return cell + Vector2i.LEFT

func _side_corners(cell: Vector2i, side_name: String) -> Array:
	match side_name:
		"north":
			return [Vector2i(cell.x, cell.y), Vector2i(cell.x + 1, cell.y)]
		"east":
			return [Vector2i(cell.x + 1, cell.y), Vector2i(cell.x + 1, cell.y + 1)]
		"south":
			return [Vector2i(cell.x + 1, cell.y + 1), Vector2i(cell.x, cell.y + 1)]
		_:
			return [Vector2i(cell.x, cell.y + 1), Vector2i(cell.x, cell.y)]

func _build_shore_side_map(cells: Array, cell_set: Dictionary, map_data: MapData) -> Dictionary:
	var shore_sides: Dictionary = {}
	if map_data == null:
		return shore_sides
	for raw_cell in cells:
		var cell: Vector2i = raw_cell
		for side_name in ["north", "east", "south", "west"]:
			var neighbor: Vector2i = _boundary_neighbor(cell, side_name)
			if cell_set.has(neighbor):
				continue
			var neighbor_tile = map_data.get_tile(neighbor.x, neighbor.y)
			if neighbor_tile == null:
				continue
			if neighbor_tile.is_water or neighbor_tile.base_terrain_type == MapTypes.TerrainType.WATER:
				shore_sides[_cell_side_key(cell, side_name)] = true
	return shore_sides

func _cell_side_key(cell: Vector2i, side_name: String) -> String:
	return "%d:%d:%s" % [cell.x, cell.y, side_name]

func _boundary_side_dir(side_name: String) -> Vector2:
	match side_name:
		"north":
			return Vector2(0.0, -1.0)
		"east":
			return Vector2(1.0, 0.0)
		"south":
			return Vector2(0.0, 1.0)
		_:
			return Vector2(-1.0, 0.0)

func _distance_to_segment_2d(point: Vector2, from_point: Vector2, to_point: Vector2) -> float:
	var segment: Vector2 = to_point - from_point
	var length_squared: float = segment.length_squared()
	if length_squared <= 0.00001:
		return point.distance_to(from_point)
	var t: float = clampf((point - from_point).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(from_point + (segment * t))

func _noise_01(x: int, y: int, salt: int) -> float:
	var value: int = GenerationUtilsClass.hash2d(x, y, salt) % 1000
	return float(value) / 999.0
