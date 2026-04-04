extends RefCounted
class_name BlockerGenerator

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")
const GenerationMaskUtilsClass = preload("res://scripts/core/generation/generation_mask_utils.gd")

func generate(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var keep_corridor_mask: Dictionary = _build_keep_corridor_mask(map_data, composition, config)
	for blocker_spec in composition.get("blockers", []):
		var anchor: Vector2 = blocker_spec.get("anchor", Vector2(0.25, 0.25))
		var world_anchor := Vector2(anchor.x * float(map_data.width - 1), anchor.y * float(map_data.height - 1))
		if world_anchor.distance_to(center) < float(config.min_blocker_distance_from_center):
			continue

		var blocker_type: int = int(blocker_spec.get("kind", MapTypes.BlockerType.FOREST))
		var shape: String = String(blocker_spec.get("shape", "metaball"))
		var core_points: Array[Vector2i] = []
		match shape:
			"spine":
				core_points = _generate_spine_mass(map_data, world_anchor, center, blocker_spec, rng, blocker_type)
			"metaball":
				core_points = _generate_metaball_mass(map_data, world_anchor, center, blocker_spec, rng, blocker_type)
			_:
				core_points = _generate_metaball_mass(map_data, world_anchor, center, blocker_spec, rng, blocker_type)

		core_points = _sanitize_points(map_data, core_points, keep_corridor_mask)
		var preserve_disconnected_clusters: bool = blocker_type == MapTypes.BlockerType.FOREST and bool(blocker_spec.get("allow_disconnected_clusters", false))
		if preserve_disconnected_clusters:
			var min_component_tiles: int = max(6, int(blocker_spec.get("min_component_tiles", 10)))
			core_points = GenerationMaskUtilsClass.extract_components_above_size(core_points, min_component_tiles)
		else:
			core_points = GenerationMaskUtilsClass.extract_largest_component(core_points)
		if core_points.size() < max(24, int(config.min_blocker_area / 6)):
			continue

		var edge_band: int = maxi(0, int(blocker_spec.get("edge_band", 1)))
		var fringe_points: Array[Vector2i] = _build_fringe_points(map_data, core_points, edge_band, keep_corridor_mask)
		var rock_annotations: Dictionary = {}
		if blocker_type == MapTypes.BlockerType.ROCK:
			rock_annotations = _annotate_rock_region(map_data, core_points, fringe_points, blocker_spec)
		var region_id: int = int(blocker_spec.get("region_id", 200))
		var metadata := {
			"blocker_type": blocker_type,
			"shape": shape,
			"core_tiles": core_points.size(),
			"fringe_tiles": fringe_points.size(),
		}
		if blocker_type == MapTypes.BlockerType.ROCK:
			metadata["rock_mass_profile"] = String(rock_annotations.get("mass_profile", blocker_spec.get("rock_mass_profile", "massif")))
			metadata["rock_summit_profile"] = int(rock_annotations.get("summit_profile", blocker_spec.get("rock_summit_profile", MapTypes.RockSummitProfile.PEAK)))
			metadata["terrace_count"] = int(rock_annotations.get("terrace_count", blocker_spec.get("terrace_count", 3)))
		map_data.register_region(
			region_id,
			MapTypes.RegionType.BLOCKER_MASS,
			"blocker_%d" % region_id,
			metadata
		)
		_stamp_core_tiles(map_data, core_points, region_id, blocker_type, rock_annotations)
		_stamp_fringe_tiles(map_data, fringe_points, region_id, blocker_type, rock_annotations)

func _generate_spine_mass(
	map_data: MapData,
	anchor: Vector2,
	center: Vector2,
	spec: Dictionary,
	rng: RandomNumberGenerator,
	blocker_type: int
) -> Array[Vector2i]:
	var segments_min: int = int(spec.get("segments_min", 2))
	var segments_max: int = max(segments_min, int(spec.get("segments_max", 5)))
	var segments: int = rng.randi_range(segments_min, segments_max)
	var length: float = rng.randf_range(
		float(spec.get("length_min", 18.0)),
		float(spec.get("length_max", 36.0))
	) * float(spec.get("size_bias", 1.0))
	var base_width: float = rng.randf_range(
		float(spec.get("thickness_min", 2.6)),
		float(spec.get("thickness_max", 5.4))
	) * float(spec.get("size_bias", 1.0))
	var bend: float = rng.randf_range(
		float(spec.get("bend_min", 0.18)),
		float(spec.get("bend_max", 0.42))
	)
	var center_dir: Vector2 = (center - anchor).normalized()
	if center_dir == Vector2.ZERO:
		center_dir = Vector2.RIGHT
	var heading: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
	heading = heading.slerp(center_dir, clampf(float(spec.get("aggression", 0.55)) * 0.45, 0.0, 0.75))

	var controls: Array[Vector2] = [anchor]
	var current: Vector2 = anchor
	for _step in range(segments):
		heading = heading.rotated(rng.randf_range(-bend, bend))
		var stride: float = (length / float(maxi(segments, 1))) * rng.randf_range(0.72, 1.20)
		current += heading.normalized() * stride
		current = _clamp_world(current, map_data)
		controls.append(current)

	var spine_tiles: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline(controls)
	var selected := {}
	for index in range(spine_tiles.size()):
		var point: Vector2i = spine_tiles[index]
		var t: float = float(index) / maxf(1.0, float(spine_tiles.size() - 1))
		var width: float = base_width * (0.78 + (sin(t * PI) * 0.34) + rng.randf_range(-0.12, 0.12))
		GenerationMaskUtilsClass.stamp_disc(selected, point, width, map_data)

	if blocker_type == MapTypes.BlockerType.ROCK:
		_stamp_rock_spurs(selected, spine_tiles, base_width, map_data, rng, spec)
		_stamp_rock_plateau_pad(selected, spine_tiles, base_width, map_data, rng, spec)

	selected = _roughen_mass(
		selected,
		float(spec.get("jitter", 0.16)),
		map_data,
		int(anchor.x * 17.0 + anchor.y * 23.0),
		blocker_type
	)
	var points: Array[Vector2i] = []
	points.assign(selected.keys())
	return points

func _stamp_rock_spurs(
	selected: Dictionary,
	spine_tiles: Array[Vector2i],
	base_width: float,
	map_data: MapData,
	rng: RandomNumberGenerator,
	spec: Dictionary
) -> void:
	var spur_count: int = max(0, int(spec.get("spur_count", 0)))
	if spur_count <= 0 or spine_tiles.size() < 6:
		return
	for spur_index in range(spur_count):
		var t: float = 0.22 + ((float(spur_index) + 0.5) / float(spur_count + 1)) * 0.58
		t += rng.randf_range(-0.08, 0.08)
		t = clampf(t, 0.14, 0.86)
		var anchor_index: int = clampi(int(round(t * float(spine_tiles.size() - 1))), 1, spine_tiles.size() - 2)
		var anchor_point: Vector2 = Vector2(spine_tiles[anchor_index])
		var tangent: Vector2 = (Vector2(spine_tiles[anchor_index + 1]) - Vector2(spine_tiles[anchor_index - 1])).normalized()
		if tangent == Vector2.ZERO:
			continue
		var normal: Vector2 = Vector2(-tangent.y, tangent.x)
		var sign: float = -1.0 if (spur_index % 2) == 0 else 1.0
		if rng.randf() < 0.35:
			sign *= -1.0
		var spur_dir: Vector2 = ((tangent * rng.randf_range(0.16, 0.34)) + (normal * sign * rng.randf_range(0.72, 0.96))).normalized()
		var spur_length: float = rng.randf_range(3.0, 7.0) + (base_width * rng.randf_range(1.8, 2.8))
		var samples: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([anchor_point, anchor_point + (spur_dir * spur_length)])
		for point in samples:
			GenerationMaskUtilsClass.stamp_disc(selected, point, base_width * rng.randf_range(0.34, 0.52), map_data)

func _stamp_rock_plateau_pad(
	selected: Dictionary,
	spine_tiles: Array[Vector2i],
	base_width: float,
	map_data: MapData,
	rng: RandomNumberGenerator,
	spec: Dictionary
) -> void:
	if String(spec.get("rock_mass_profile", "")) != "massif":
		return
	if spine_tiles.size() < 7 or rng.randf() > float(spec.get("plateau_pad_chance", 0.0)):
		return
	var center_index: int = clampi(int(round(float(spine_tiles.size() - 1) * rng.randf_range(0.42, 0.60))), 2, spine_tiles.size() - 3)
	var radius: float = base_width * rng.randf_range(0.92, 1.24)
	for offset in [-2, -1, 0, 1, 2]:
		var sample_index: int = clampi(center_index + offset, 0, spine_tiles.size() - 1)
		GenerationMaskUtilsClass.stamp_disc(selected, spine_tiles[sample_index], radius * (1.0 - absf(float(offset)) * 0.12), map_data)

func _annotate_rock_region(
	map_data: MapData,
	core_points: Array[Vector2i],
	fringe_points: Array[Vector2i],
	spec: Dictionary
) -> Dictionary:
	var all_lookup := {}
	var core_lookup := {}
	var fringe_lookup := {}
	for point in core_points:
		all_lookup[point] = true
		core_lookup[point] = true
	for point in fringe_points:
		all_lookup[point] = true
		fringe_lookup[point] = true

	var all_points: Array[Vector2i] = []
	all_points.assign(all_lookup.keys())
	var boundary_points: Array[Vector2i] = []
	for point in all_points:
		if fringe_lookup.has(point):
			boundary_points.append(point)
			continue
		for neighbor in GenerationUtilsClass.cardinal_neighbors(point):
			if not all_lookup.has(neighbor):
				boundary_points.append(point)
				break
	if boundary_points.is_empty():
		boundary_points = all_points.duplicate()

	var distance_map: Dictionary = _point_distance_field(all_lookup, boundary_points)
	var max_distance: int = 0
	for value in distance_map.values():
		max_distance = maxi(max_distance, int(value))

	var axis_data: Dictionary = _principal_axis(all_points)
	var mass_profile: String = String(spec.get("rock_mass_profile", ""))
	if mass_profile.is_empty():
		mass_profile = "ridge" if float(axis_data.get("elongation", 1.0)) >= 1.8 else "massif"
	var summit_profile: int = _select_rock_summit_profile(spec, mass_profile)
	var terrace_count: int = max(3, int(spec.get("terrace_count", 3)))
	var role_map: Dictionary = {}
	var height_map: Dictionary = {}
	for point in all_points:
		var role: int = _rock_role_for_point(
			point,
			core_lookup,
			fringe_lookup,
			distance_map,
			max_distance,
			axis_data,
			mass_profile,
			summit_profile,
			terrace_count
		)
		role_map[point] = role
		height_map[point] = _rock_height_class_for_role(role)

	return {
		"mass_profile": mass_profile,
		"summit_profile": summit_profile,
		"terrace_count": terrace_count,
		"role_map": role_map,
		"height_map": height_map,
	}

func _rock_role_for_point(
	point: Vector2i,
	core_lookup: Dictionary,
	fringe_lookup: Dictionary,
	distance_map: Dictionary,
	max_distance: int,
	axis_data: Dictionary,
	mass_profile: String,
	summit_profile: int,
	terrace_count: int
) -> int:
	if fringe_lookup.has(point):
		return MapTypes.RockRole.TALUS if _touches_lookup(point, core_lookup) else MapTypes.RockRole.FOOT

	var depth01: float = (float(distance_map.get(point, 0)) + 0.35) / (float(max_distance) + 1.15)
	depth01 = clampf(depth01, 0.0, 1.0)
	var ridge_factor: float = _axis_ridge_factor(point, axis_data)
	if mass_profile == "ridge":
		depth01 *= 0.78 + (ridge_factor * 0.26)
	else:
		depth01 *= 0.90 + (ridge_factor * 0.10)
	depth01 = clampf(depth01, 0.0, 1.0)

	var noise: float = float(GenerationUtilsClass.hash2d(point.x, point.y, terrace_count * 73 + 19) % 1000) / 999.0
	var terrace_scaled: float = depth01 * float(max(1, terrace_count)) + (noise * 0.42)
	var terrace_phase: float = terrace_scaled - floor(terrace_scaled)
	var shelf_hint: bool = depth01 >= 0.22 and depth01 <= 0.82 and terrace_phase <= 0.26
	var summit_mask: bool = false
	match summit_profile:
		MapTypes.RockSummitProfile.PLATEAU:
			summit_mask = depth01 >= 0.62 and ridge_factor >= 0.28
		MapTypes.RockSummitProfile.BROKEN_TOP:
			summit_mask = depth01 >= 0.68 and (noise >= 0.42 or ridge_factor >= 0.66)
		_:
			var ridge_threshold: float = 0.58 if mass_profile == "ridge" else 0.30
			summit_mask = depth01 >= 0.78 and ridge_factor >= ridge_threshold

	if summit_mask:
		return MapTypes.RockRole.SUMMIT
	if shelf_hint and (mass_profile != "ridge" or ridge_factor >= 0.36):
		return MapTypes.RockRole.SHELF
	if depth01 >= 0.18 or ridge_factor >= 0.52:
		return MapTypes.RockRole.WALL
	return MapTypes.RockRole.TALUS

func _select_rock_summit_profile(spec: Dictionary, mass_profile: String) -> int:
	var requested: int = int(spec.get("rock_summit_profile", MapTypes.RockSummitProfile.NONE))
	if requested != MapTypes.RockSummitProfile.NONE:
		return requested
	return MapTypes.RockSummitProfile.PEAK if mass_profile == "ridge" else MapTypes.RockSummitProfile.BROKEN_TOP

func _rock_height_class_for_role(role: int) -> int:
	match role:
		MapTypes.RockRole.FOOT:
			return MapTypes.HeightClass.LOW
		MapTypes.RockRole.TALUS:
			return MapTypes.HeightClass.MID
		MapTypes.RockRole.SHELF:
			return MapTypes.HeightClass.MID
		MapTypes.RockRole.WALL, MapTypes.RockRole.SUMMIT:
			return MapTypes.HeightClass.HIGH
		_:
			return MapTypes.HeightClass.MID

func _touches_lookup(point: Vector2i, lookup: Dictionary) -> bool:
	for neighbor in GenerationUtilsClass.cardinal_neighbors(point):
		if lookup.has(neighbor):
			return true
	return false

func _point_distance_field(point_lookup: Dictionary, boundary_points: Array[Vector2i]) -> Dictionary:
	var distance_map: Dictionary = {}
	var queue: Array[Vector2i] = []
	for point in boundary_points:
		if distance_map.has(point):
			continue
		distance_map[point] = 0
		queue.append(point)
	var index: int = 0
	while index < queue.size():
		var point: Vector2i = queue[index]
		index += 1
		var current_distance: int = int(distance_map.get(point, 0))
		for neighbor in GenerationUtilsClass.cardinal_neighbors(point):
			if not point_lookup.has(neighbor) or distance_map.has(neighbor):
				continue
			distance_map[neighbor] = current_distance + 1
			queue.append(neighbor)
	return distance_map

func _principal_axis(points: Array[Vector2i]) -> Dictionary:
	if points.is_empty():
		return {}
	var center := Vector2.ZERO
	for point in points:
		center += Vector2(point) + Vector2(0.5, 0.5)
	center /= maxf(1.0, float(points.size()))

	var xx: float = 0.0
	var xy: float = 0.0
	var yy: float = 0.0
	var min_along: float = INF
	var max_along: float = -INF
	for point in points:
		var offset: Vector2 = (Vector2(point) + Vector2(0.5, 0.5)) - center
		xx += offset.x * offset.x
		xy += offset.x * offset.y
		yy += offset.y * offset.y

	var trace: float = xx + yy
	var determinant: float = (xx * yy) - (xy * xy)
	var term: float = sqrt(maxf(0.0, (trace * trace * 0.25) - determinant))
	var lambda: float = (trace * 0.5) + term
	var direction := Vector2(xy, lambda - xx)
	if direction.length_squared() <= 0.0001:
		direction = Vector2.RIGHT
	direction = direction.normalized()
	var perpendicular := Vector2(-direction.y, direction.x)
	var max_perp: float = 0.0
	for point in points:
		var offset: Vector2 = (Vector2(point) + Vector2(0.5, 0.5)) - center
		var along: float = offset.dot(direction)
		min_along = minf(min_along, along)
		max_along = maxf(max_along, along)
		max_perp = maxf(max_perp, absf(offset.dot(perpendicular)))
	return {
		"origin": center,
		"direction": direction,
		"perpendicular": perpendicular,
		"max_perp": max_perp,
		"elongation": (maxf(1.0, max_along - min_along) + 1.0) / (maxf(1.0, max_perp * 2.0) + 1.0),
	}

func _axis_ridge_factor(point: Vector2i, axis_data: Dictionary) -> float:
	if axis_data.is_empty():
		return 1.0
	var center: Vector2 = Vector2(point) + Vector2(0.5, 0.5)
	var origin: Vector2 = axis_data.get("origin", center)
	var perpendicular: Vector2 = axis_data.get("perpendicular", Vector2.DOWN)
	var max_perp: float = maxf(0.8, float(axis_data.get("max_perp", 1.0)))
	var perp_distance: float = absf((center - origin).dot(perpendicular))
	var ridge_value: float = 1.0 - clampf(perp_distance / (max_perp + 0.9), 0.0, 1.0)
	return pow(maxf(ridge_value, 0.0), 1.45)

func _generate_metaball_mass(
	map_data: MapData,
	anchor: Vector2,
	center: Vector2,
	spec: Dictionary,
	rng: RandomNumberGenerator,
	blocker_type: int
) -> Array[Vector2i]:
	var blobs_min: int = int(spec.get("blob_count_min", 2))
	var blobs_max: int = max(blobs_min, int(spec.get("blob_count_max", 5)))
	var nuclei_count: int = rng.randi_range(blobs_min, blobs_max)
	var radius_min: float = float(spec.get("radius_min", 4.0)) * float(spec.get("size_bias", 1.0))
	var radius_max: float = float(spec.get("radius_max", 9.0)) * float(spec.get("size_bias", 1.0))
	var center_bias: float = clampf(float(spec.get("aggression", 0.5)), 0.0, 1.0)
	var cluster_radius: float = lerpf(radius_max * 1.65, radius_max * 1.05, center_bias)

	var nuclei: Array[Dictionary] = []
	for _i in range(nuclei_count):
		var random_dir: Vector2 = Vector2.RIGHT.rotated(rng.randf_range(0.0, TAU))
		var to_center: Vector2 = (center - anchor).normalized()
		if to_center == Vector2.ZERO:
			to_center = random_dir
		var dir: Vector2 = random_dir.slerp(to_center, center_bias * rng.randf_range(0.2, 0.6))
		var distance: float = rng.randf_range(0.0, cluster_radius)
		var nucleus_center: Vector2 = _clamp_world(anchor + dir * distance, map_data)
		var radius: float = rng.randf_range(radius_min, radius_max)
		nuclei.append({
			"center": nucleus_center,
			"radius": radius,
		})

	var selected := {}
	for nucleus in nuclei:
		var nucleus_center: Vector2 = Vector2(nucleus["center"])
		var nucleus_radius: float = float(nucleus["radius"])
		GenerationMaskUtilsClass.stamp_disc(selected, Vector2i(roundi(nucleus_center.x), roundi(nucleus_center.y)), nucleus_radius, map_data)

	var allow_disconnected_clusters: bool = bool(spec.get("allow_disconnected_clusters", false))
	var connect_nuclei_chance: float = clampf(float(spec.get("connect_nuclei_chance", 1.0)), 0.0, 1.0)
	var max_links: int = int(spec.get("max_links", nuclei.size() - 1))
	if max_links < 0:
		max_links = 0
	var links_used: int = 0
	if connect_nuclei_chance > 0.0 and max_links > 0:
		var link_candidates: Array[Dictionary] = []
		for i in range(nuclei.size()):
			for j in range(i + 1, nuclei.size()):
				var first_center: Vector2 = Vector2(nuclei[i]["center"])
				var second_center: Vector2 = Vector2(nuclei[j]["center"])
				link_candidates.append({
					"from": i,
					"to": j,
					"distance": first_center.distance_to(second_center),
				})
		link_candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return float(a.get("distance", 999999.0)) < float(b.get("distance", 999999.0))
		)
		for link in link_candidates:
			if links_used >= max_links:
				break
			if rng.randf() > connect_nuclei_chance:
				continue
			var from_index: int = int(link.get("from", 0))
			var to_index: int = int(link.get("to", 0))
			var from_center: Vector2 = Vector2(nuclei[from_index]["center"])
			var to_center: Vector2 = Vector2(nuclei[to_index]["center"])
			var link_radius: float = minf(float(nuclei[from_index]["radius"]), float(nuclei[to_index]["radius"])) * rng.randf_range(0.38, 0.62)
			var link_line: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([from_center, to_center])
			for point in link_line:
				GenerationMaskUtilsClass.stamp_disc(selected, point, link_radius, map_data)
			links_used += 1
	if not allow_disconnected_clusters and nuclei.size() > 1 and links_used == 0:
		var fallback_from: Vector2 = Vector2(nuclei[0]["center"])
		var fallback_to: Vector2 = Vector2(nuclei[1]["center"])
		var fallback_radius: float = minf(float(nuclei[0]["radius"]), float(nuclei[1]["radius"])) * 0.5
		var fallback_line: Array[Vector2i] = GenerationUtilsClass.rasterize_polyline([fallback_from, fallback_to])
		for point in fallback_line:
			GenerationMaskUtilsClass.stamp_disc(selected, point, fallback_radius, map_data)

	selected = _roughen_mass(
		selected,
		float(spec.get("jitter", 0.24)),
		map_data,
		int(anchor.x * 29.0 + anchor.y * 31.0),
		blocker_type
	)
	var points: Array[Vector2i] = []
	points.assign(selected.keys())
	return points

func _build_keep_corridor_mask(map_data: MapData, composition: Dictionary, config) -> Dictionary:
	var mask := {}
	var center: Vector2 = composition.get("center", Vector2(float(map_data.width) * 0.5, float(map_data.height) * 0.5))
	var center_point := Vector2i(roundi(center.x), roundi(center.y))
	var corridor_width: int = int(composition.get("corridor_width", maxi(config.minimum_path_width + 1, 3)))
	var corridor_buffer: int = int(composition.get("corridor_buffer", 1))
	var corridor_radius: int = maxi(1, int(floor(float(corridor_width) * 0.5)) + corridor_buffer)
	mask = GenerationMaskUtilsClass.build_corridor_mask(
		map_data,
		composition,
		corridor_radius,
		true,
		1,
		2
	)
	GenerationMaskUtilsClass.stamp_mask(mask, center_point, corridor_radius + 2, map_data)
	return mask

func _sanitize_points(map_data: MapData, points: Array[Vector2i], keep_corridor_mask: Dictionary) -> Array[Vector2i]:
	var selected := {}
	for point in points:
		if not map_data.is_in_bounds(point.x, point.y):
			continue
		if keep_corridor_mask.has(point):
			continue
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
			continue
		if tile.is_water:
			continue
		selected[point] = true
	var result: Array[Vector2i] = []
	result.assign(selected.keys())
	return result

func _build_fringe_points(
	map_data: MapData,
	core_points: Array[Vector2i],
	edge_band: int,
	keep_corridor_mask: Dictionary
) -> Array[Vector2i]:
	var core := {}
	for point in core_points:
		core[point] = true
	var fringe := {}
	var frontier: Array[Vector2i] = core_points.duplicate()
	for _layer in range(edge_band):
		var next_frontier: Array[Vector2i] = []
		for point in frontier:
			for neighbor in GenerationUtilsClass.cardinal_neighbors(point):
				if core.has(neighbor) or fringe.has(neighbor):
					continue
				if keep_corridor_mask.has(neighbor):
					continue
				if not map_data.is_in_bounds(neighbor.x, neighbor.y):
					continue
				var tile = map_data.get_tile(neighbor.x, neighbor.y)
				if tile == null:
					continue
				if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
					continue
				if tile.is_water or tile.is_road:
					continue
				fringe[neighbor] = true
				next_frontier.append(neighbor)
		frontier = next_frontier
		if frontier.is_empty():
			break
	var result: Array[Vector2i] = []
	result.assign(fringe.keys())
	return result

func _stamp_core_tiles(map_data: MapData, points: Array[Vector2i], region_id: int, blocker_type: int, rock_annotations: Dictionary = {}) -> void:
	for point in points:
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
			continue
		tile.base_terrain_type = _terrain_for_blocker(blocker_type)
		tile.terrain_type = _terrain_for_blocker(blocker_type)
		tile.blocker_type = blocker_type
		tile.region_id = region_id
		tile.region_type = MapTypes.RegionType.BLOCKER_MASS
		_clear_rock_semantics(tile)
		tile.is_walkable = false
		tile.is_blocked = true
		tile.is_buildable = false
		tile.is_future_wallable = false
		tile.is_water = false
		tile.walk_cost = 999.0
		tile.resource_tag = _resource_for_blocker(blocker_type)
		tile.debug_tags.clear()
		tile.debug_tags.append("major_blocker")
		tile.debug_tags.append("blocker_core")
		tile.debug_tags.append(MapTypes.blocker_name(blocker_type))
		if blocker_type == MapTypes.BlockerType.FOREST:
			tile.debug_tags.append("forest_core")
		elif blocker_type == MapTypes.BlockerType.ROCK:
			tile.debug_tags.append("rock_core")
			_apply_rock_tile_semantics(tile, point, rock_annotations)

func _stamp_fringe_tiles(map_data: MapData, points: Array[Vector2i], region_id: int, blocker_type: int, rock_annotations: Dictionary = {}) -> void:
	for point in points:
		var tile = map_data.get_tile(point.x, point.y)
		if tile == null:
			continue
		if tile.region_type == MapTypes.RegionType.CENTER_CLEARING:
			continue
		if tile.is_blocked:
			continue
		tile.region_id = region_id
		tile.region_type = MapTypes.RegionType.BLOCKER_MASS
		tile.is_buildable = false
		tile.is_future_wallable = false
		tile.is_water = false
		_clear_rock_semantics(tile)
		match blocker_type:
			MapTypes.BlockerType.FOREST:
				tile.base_terrain_type = MapTypes.TerrainType.FOREST
				tile.terrain_type = MapTypes.TerrainType.FOREST
				tile.blocker_type = MapTypes.BlockerType.FOREST
				tile.resource_tag = MapTypes.ResourceTag.WOOD
				tile.is_walkable = true
				tile.is_blocked = false
				tile.walk_cost = 2.35
				if not tile.debug_tags.has("forest_fringe"):
					tile.debug_tags.append("forest_fringe")
			MapTypes.BlockerType.ROCK:
				tile.base_terrain_type = MapTypes.TerrainType.GROUND
				tile.terrain_type = MapTypes.TerrainType.GROUND
				tile.blocker_type = MapTypes.BlockerType.NONE
				tile.resource_tag = MapTypes.ResourceTag.STONE
				tile.transition_type = MapTypes.TransitionType.BLOCKER_EDGE
				tile.is_walkable = true
				tile.is_blocked = false
				tile.walk_cost = 4.40
				_apply_rock_tile_semantics(tile, point, rock_annotations)
				if not tile.debug_tags.has("rock_edge"):
					tile.debug_tags.append("rock_edge")
			_:
				tile.base_terrain_type = _terrain_for_blocker(blocker_type)
				tile.terrain_type = _terrain_for_blocker(blocker_type)
				tile.blocker_type = blocker_type
				tile.resource_tag = _resource_for_blocker(blocker_type)
				tile.is_walkable = false
				tile.is_blocked = false
				tile.walk_cost = 6.0
		if not tile.debug_tags.has("obstacle_fringe"):
			tile.debug_tags.append("obstacle_fringe")

func _clear_rock_semantics(tile) -> void:
	tile.rock_role = MapTypes.RockRole.NONE
	tile.rock_summit_profile = MapTypes.RockSummitProfile.NONE

func _apply_rock_tile_semantics(tile, point: Vector2i, rock_annotations: Dictionary) -> void:
	var role_map: Dictionary = rock_annotations.get("role_map", {})
	var height_map: Dictionary = rock_annotations.get("height_map", {})
	tile.rock_role = int(role_map.get(point, MapTypes.RockRole.NONE))
	tile.rock_summit_profile = int(rock_annotations.get("summit_profile", MapTypes.RockSummitProfile.NONE))
	tile.height_class = int(height_map.get(point, _rock_height_class_for_role(tile.rock_role)))
	match tile.rock_role:
		MapTypes.RockRole.FOOT:
			if not tile.debug_tags.has("rock_foot"):
				tile.debug_tags.append("rock_foot")
		MapTypes.RockRole.TALUS:
			if not tile.debug_tags.has("rock_talus"):
				tile.debug_tags.append("rock_talus")
		MapTypes.RockRole.SHELF:
			if not tile.debug_tags.has("rock_shelf"):
				tile.debug_tags.append("rock_shelf")
		MapTypes.RockRole.WALL:
			if not tile.debug_tags.has("rock_wall"):
				tile.debug_tags.append("rock_wall")
		MapTypes.RockRole.SUMMIT:
			if not tile.debug_tags.has("rock_summit"):
				tile.debug_tags.append("rock_summit")

func _terrain_for_blocker(blocker_type: int) -> int:
	match blocker_type:
		MapTypes.BlockerType.FOREST:
			return MapTypes.TerrainType.FOREST
		MapTypes.BlockerType.ROCK:
			return MapTypes.TerrainType.ROCK
		MapTypes.BlockerType.RAVINE:
			return MapTypes.TerrainType.RAVINE
		_:
			return MapTypes.TerrainType.BLOCKER

func _resource_for_blocker(blocker_type: int) -> int:
	match blocker_type:
		MapTypes.BlockerType.FOREST:
			return MapTypes.ResourceTag.WOOD
		MapTypes.BlockerType.ROCK, MapTypes.BlockerType.RAVINE:
			return MapTypes.ResourceTag.STONE
		_:
			return MapTypes.ResourceTag.NONE

func _roughen_mass(selected: Dictionary, jitter: float, map_data: MapData, salt: int, blocker_type: int) -> Dictionary:
	if selected.is_empty():
		return selected
	var result: Dictionary = selected.duplicate(true)
	for key in selected.keys():
		var point: Vector2i = key
		var boundary_neighbors: int = 0
		for neighbor in GenerationUtilsClass.cardinal_neighbors(point):
			if not result.has(neighbor):
				boundary_neighbors += 1
		if boundary_neighbors <= 0:
			continue
		var noise: float = float(GenerationUtilsClass.hash2d(point.x, point.y, salt) % 1000) / 1000.0
		if noise < jitter * 0.52:
			result.erase(point)
	var points: Array[Vector2i] = []
	points.assign(result.keys())
	var keep_min_neighbors: int = 2
	var grow_min_neighbors: int = 2
	match blocker_type:
		MapTypes.BlockerType.ROCK:
			keep_min_neighbors = 1
			grow_min_neighbors = 4
		MapTypes.BlockerType.RAVINE:
			keep_min_neighbors = 1
			grow_min_neighbors = 2
	var smoothed: Array[Vector2i] = GenerationUtilsClass.smooth_points(map_data, points, keep_min_neighbors, grow_min_neighbors)
	var output := {}
	for point in smoothed:
		output[point] = true
	return output

func _clamp_world(point: Vector2, map_data: MapData) -> Vector2:
	return Vector2(
		clampf(point.x, 1.0, float(map_data.width - 2)),
		clampf(point.y, 1.0, float(map_data.height - 2))
	)
