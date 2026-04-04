extends RefCounted
class_name LayoutComposer

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")

func compose(map_data: MapData, rng: RandomNumberGenerator, config) -> Dictionary:
	var families: Array[Dictionary] = _scenario_families()
	var chosen: Dictionary = families[rng.randi_range(0, families.size() - 1)].duplicate(true)
	var center_offset := _random_vec2(
		chosen.get("center_offset_min", Vector2(-0.06, -0.06)),
		chosen.get("center_offset_max", Vector2(0.06, 0.06)),
		rng
	)
	var center := Vector2(
		(float(map_data.width) * 0.5) + (center_offset.x * float(map_data.width) * 0.20),
		(float(map_data.height) * 0.5) + (center_offset.y * float(map_data.height) * 0.20)
	)
	var entries: Array[Dictionary] = _build_entries(chosen, map_data, rng, config)
	var blocker_report: Dictionary = _build_blockers(chosen, rng, config)
	var blockers: Array[Dictionary] = blocker_report.get("all", [])
	var water: Variant = _build_water_profile(chosen, rng, blockers, entries, map_data)
	var corridor_range: Vector2i = chosen.get("corridor_width_range", Vector2i(3, 5))
	var corridor_width: int = rng.randi_range(
		mini(corridor_range.x, corridor_range.y),
		maxi(corridor_range.x, corridor_range.y)
	)

	return {
		"template_id": String(chosen["id"]),
		"scenario_family_id": String(chosen["id"]),
		"center": center,
		"entries": entries,
		"blockers": blockers,
		"primary_blocker_count": int(blocker_report.get("primary_count", 0)),
		"satellite_blocker_count": int(blocker_report.get("satellite_count", 0)),
		"water": water,
		"corridor_width": corridor_width,
		"corridor_buffer": int(chosen.get("corridor_buffer", 1)),
	}

func _build_entries(family: Dictionary, map_data: MapData, rng: RandomNumberGenerator, config) -> Array[Dictionary]:
	var requested_entries: int = clampi(config.entry_count, 2, 4)
	var profiles: Array = family.get("entry_profiles", [])
	var shuffled: Array = profiles.duplicate(true)
	_shuffle(shuffled, rng)
	var entries: Array[Dictionary] = []
	var used_points := {}
	var fallback_sides: Array[String] = ["north", "east", "south", "west"]
	_shuffle(fallback_sides, rng)
	for index in range(requested_entries):
		var source: Dictionary = {}
		if index < shuffled.size():
			source = shuffled[index].duplicate(true)
		else:
			source = {
				"side": fallback_sides[index % fallback_sides.size()],
				"offset_min": 0.24,
				"offset_max": 0.76,
			}
		var side: String = String(source.get("side", "north"))
		var offset: float = _random_float(
			float(source.get("offset_min", 0.30)),
			float(source.get("offset_max", 0.70)),
			rng
		)
		var point: Vector2i = GenerationUtilsClass.point_on_side(
			side,
			map_data.width,
			map_data.height,
			offset,
			config.approach_padding
		)
		var attempts: int = 0
		while used_points.has(point) and attempts < 8:
			offset = clampf(offset + rng.randf_range(-0.12, 0.12), 0.12, 0.88)
			point = GenerationUtilsClass.point_on_side(
				side,
				map_data.width,
				map_data.height,
				offset,
				config.approach_padding
			)
			attempts += 1
		used_points[point] = true
		entries.append({
			"side": side,
			"offset": offset,
			"point": point,
			"region_id": 100 + index,
		})
	return entries

func _build_blockers(family: Dictionary, rng: RandomNumberGenerator, config) -> Dictionary:
	var primary_specs: Array = _primary_motifs(family)
	var satellite_specs: Array = _satellite_motifs(family, primary_specs)
	var selected_primary: Array[Dictionary] = []
	var selected_satellite: Array[Dictionary] = []
	var all_blockers: Array[Dictionary] = []
	var region_counter: int = 200

	if not primary_specs.is_empty():
		var shuffled_primary: Array = primary_specs.duplicate(true)
		_shuffle(shuffled_primary, rng)
		var primary_target_min: int = clampi(int(family.get("primary_count_min", mini(2, shuffled_primary.size()))), 1, shuffled_primary.size())
		var primary_target_max: int = clampi(int(family.get("primary_count_max", mini(3, shuffled_primary.size()))), primary_target_min, shuffled_primary.size())
		var primary_target: int = clampi(maxi(config.blocker_count, primary_target_min), primary_target_min, primary_target_max)
		for index in range(primary_target):
			var primary := _realize_motif(shuffled_primary[index], rng, region_counter, "primary")
			region_counter += 1
			selected_primary.append(primary)
			all_blockers.append(primary)

	if not satellite_specs.is_empty():
		var sat_min: int = int(family.get("satellite_count_min", 2))
		var sat_max: int = max(sat_min, int(family.get("satellite_count_max", 4)))
		var sat_target: int = rng.randi_range(sat_min, sat_max)
		var satellite_candidates: Array = _satellite_candidates(satellite_specs, selected_primary)
		satellite_candidates.append_array(_balance_satellite_specs(family, selected_primary, satellite_specs, rng))
		_shuffle(satellite_candidates, rng)
		for candidate in satellite_candidates:
			if selected_satellite.size() >= sat_target:
				break
			var motif := _realize_motif(candidate, rng, region_counter, "satellite")
			region_counter += 1
			if _too_close_to_existing(motif, all_blockers, 0.18):
				continue
			selected_satellite.append(motif)
			all_blockers.append(motif)

	return {
		"primary_count": selected_primary.size(),
		"satellite_count": selected_satellite.size(),
		"all": all_blockers,
	}

func _build_water_profile(
	family: Dictionary,
	rng: RandomNumberGenerator,
	blockers: Array[Dictionary],
	entries: Array[Dictionary],
	map_data: MapData
) -> Variant:
	var policy: Dictionary = family.get("water_policy", {})
	var legacy_profile: Dictionary = family.get("water_profile", {})
	if policy.is_empty():
		policy = legacy_profile.duplicate(true)
	if not bool(policy.get("enabled", true)):
		return null
	var sector: int = _pick_water_sector(blockers, entries, rng, map_data.width, map_data.height)
	var sector_ranges: Array[Vector2] = _sector_anchor_ranges(sector)
	var anchor_min: Vector2 = policy.get("anchor_min", sector_ranges[0])
	var anchor_max: Vector2 = policy.get("anchor_max", sector_ranges[1])
	var anchor := _random_vec2(anchor_min, anchor_max, rng)
	var center_pull: float = clampf(float(policy.get("center_pull", 0.08)), 0.0, 0.25)
	anchor = anchor.lerp(Vector2(0.5, 0.5), center_pull * rng.randf_range(0.0, 0.8))
	var anchor_jitter: float = float(policy.get("anchor_jitter", 0.06))
	anchor.x = clampf(anchor.x + rng.randf_range(-anchor_jitter, anchor_jitter), 0.08, 0.92)
	anchor.y = clampf(anchor.y + rng.randf_range(-anchor_jitter, anchor_jitter), 0.08, 0.92)
	var basins_min: int = int(policy.get("basins_min", 1))
	var basins_max: int = max(basins_min, int(policy.get("basins_max", 2)))
	return {
		"style": String(policy.get("style", "meandering_river")),
		"anchor": anchor,
		"sector": sector,
		"size_bias": _random_float(
			float(policy.get("size_bias_min", 0.78)),
			float(policy.get("size_bias_max", 1.08)),
			rng
		),
		"basins_min": basins_min,
		"basins_max": basins_max,
		"jitter": float(policy.get("jitter", 0.16)),
		"channel_width_min": float(policy.get("channel_width_min", 2.6)),
		"channel_width_max": float(policy.get("channel_width_max", 4.8)),
		"near_center_distance_min": float(policy.get("near_center_distance_min", 10.0)),
		"near_center_distance_max": float(policy.get("near_center_distance_max", 18.0)),
		"branch_chance": float(policy.get("branch_chance", 0.0)),
		"flow_side_start": String(policy.get("flow_side_start", "")),
		"flow_side_end": String(policy.get("flow_side_end", "")),
	}

func _primary_motifs(family: Dictionary) -> Array:
	if family.has("primary_motifs"):
		return Array(family.get("primary_motifs", [])).duplicate(true)
	var motifs: Array = family.get("blocker_motifs", [])
	if motifs.is_empty():
		return []
	var target: int = mini(2, motifs.size())
	var primary: Array = []
	for i in range(target):
		primary.append(motifs[i].duplicate(true))
	return primary

func _satellite_motifs(family: Dictionary, primary_motifs: Array) -> Array:
	if family.has("satellite_motifs"):
		return Array(family.get("satellite_motifs", [])).duplicate(true)
	var motifs: Array = family.get("blocker_motifs", [])
	var satellites: Array = []
	for i in range(primary_motifs.size(), motifs.size()):
		satellites.append(motifs[i].duplicate(true))
	if satellites.is_empty():
		satellites = _default_satellite_motifs()
	return satellites

func _default_satellite_motifs() -> Array:
	return [
		{
			"kind": MapTypes.BlockerType.FOREST,
			"shape": "metaball",
			"anchor_min": Vector2(0.12, 0.12),
			"anchor_max": Vector2(0.34, 0.34),
			"blob_count_min": 3,
			"blob_count_max": 5,
			"radius_min": 4.2,
			"radius_max": 7.4,
			"edge_band": 1,
			"size_bias_min": 0.88,
			"size_bias_max": 1.12,
			"aggression_min": 0.32,
			"aggression_max": 0.62,
			"allow_disconnected_clusters": true,
			"connect_nuclei_chance": 0.44,
			"max_links": 3,
			"min_component_tiles": 12,
		},
		{
			"kind": MapTypes.BlockerType.ROCK,
			"shape": "spine",
			"ridge_profile": "thin",
			"anchor_min": Vector2(0.66, 0.14),
			"anchor_max": Vector2(0.88, 0.36),
			"length_min": 18,
			"length_max": 30,
			"thickness_min": 2.2,
			"thickness_max": 4.0,
			"segments_min": 3,
			"segments_max": 4,
			"edge_band": 1,
			"size_bias_min": 0.82,
			"size_bias_max": 1.04,
			"aggression_min": 0.28,
			"aggression_max": 0.58,
		},
		{
			"kind": MapTypes.BlockerType.FOREST,
			"shape": "metaball",
			"anchor_min": Vector2(0.60, 0.62),
			"anchor_max": Vector2(0.90, 0.90),
			"blob_count_min": 3,
			"blob_count_max": 5,
			"radius_min": 4.0,
			"radius_max": 7.6,
			"edge_band": 1,
			"size_bias_min": 0.84,
			"size_bias_max": 1.10,
			"aggression_min": 0.28,
			"aggression_max": 0.60,
			"allow_disconnected_clusters": true,
			"connect_nuclei_chance": 0.40,
			"max_links": 3,
			"min_component_tiles": 12,
		},
		{
			"kind": MapTypes.BlockerType.ROCK,
			"shape": "spine",
			"ridge_profile": "grand",
			"anchor_min": Vector2(0.14, 0.66),
			"anchor_max": Vector2(0.34, 0.88),
			"length_min": 28,
			"length_max": 48,
			"thickness_min": 2.8,
			"thickness_max": 5.2,
			"segments_min": 4,
			"segments_max": 6,
			"edge_band": 1,
			"size_bias_min": 0.92,
			"size_bias_max": 1.12,
			"aggression_min": 0.32,
			"aggression_max": 0.66,
		},
	]

func _satellite_candidates(satellite_specs: Array, selected_primary: Array[Dictionary]) -> Array:
	var primary_quadrants := {}
	for primary in selected_primary:
		var anchor: Vector2 = primary.get("anchor", Vector2(0.5, 0.5))
		primary_quadrants[_anchor_quadrant(anchor)] = true
	var preferred: Array = []
	var fallback: Array = []
	for spec in satellite_specs:
		var candidate: Dictionary = spec.duplicate(true)
		var min_anchor: Vector2 = candidate.get("anchor_min", Vector2(0.16, 0.16))
		var max_anchor: Vector2 = candidate.get("anchor_max", Vector2(0.84, 0.84))
		var mid_anchor: Vector2 = (min_anchor + max_anchor) * 0.5
		var quadrant: int = _anchor_quadrant(mid_anchor)
		if primary_quadrants.has(quadrant):
			fallback.append(candidate)
		else:
			preferred.append(candidate)
	preferred.append_array(fallback)
	return preferred

func _realize_motif(source: Dictionary, rng: RandomNumberGenerator, region_id: int, motif_role: String) -> Dictionary:
	var motif: Dictionary = source.duplicate(true)
	var anchor_min: Vector2 = motif.get("anchor_min", Vector2(0.20, 0.20))
	var anchor_max: Vector2 = motif.get("anchor_max", Vector2(0.80, 0.80))
	motif["anchor"] = _random_vec2(anchor_min, anchor_max, rng)
	motif["aggression"] = _random_float(
		float(motif.get("aggression_min", 0.35)),
		float(motif.get("aggression_max", 0.75)),
		rng
	)
	motif["size_bias"] = _random_float(
		float(motif.get("size_bias_min", 0.9)),
		float(motif.get("size_bias_max", 1.2)),
		rng
	)
	if int(motif.get("kind", MapTypes.BlockerType.NONE)) == MapTypes.BlockerType.ROCK and String(motif.get("shape", "metaball")) == "spine":
		if String(motif.get("ridge_profile", "")) == "thin":
			_apply_thin_ridge_profile(motif, rng)
		elif String(motif.get("ridge_profile", "")) == "grand":
			_apply_grand_ridge_profile(motif, rng)
		_apply_rock_relief_profile(motif, rng)
	if int(motif.get("kind", MapTypes.BlockerType.NONE)) == MapTypes.BlockerType.FOREST and String(motif.get("shape", "metaball")) == "metaball":
		var allow_disconnected: bool = bool(motif.get("allow_disconnected_clusters", motif_role == "satellite"))
		motif["allow_disconnected_clusters"] = allow_disconnected
		if String(motif.get("forest_profile", "")) == "canopy":
			_apply_canopy_forest_profile(motif, rng)
		if allow_disconnected:
			if not motif.has("connect_nuclei_chance"):
				motif["connect_nuclei_chance"] = _random_float(0.20, 0.40, rng)
			if not motif.has("max_links"):
				motif["max_links"] = 2
			if not motif.has("min_component_tiles"):
				motif["min_component_tiles"] = 10
	motif["region_id"] = region_id
	motif["motif_role"] = motif_role
	return motif

func _apply_thin_ridge_profile(motif: Dictionary, rng: RandomNumberGenerator) -> void:
	motif["length_min"] = maxf(float(motif.get("length_min", 24.0)), 24.0)
	motif["length_max"] = maxf(float(motif.get("length_max", 42.0)), 42.0)
	motif["thickness_min"] = minf(float(motif.get("thickness_min", 1.6)), 1.6)
	motif["thickness_max"] = minf(float(motif.get("thickness_max", 3.0)), 3.0)
	motif["segments_min"] = maxi(int(motif.get("segments_min", 3)), 3)
	motif["segments_max"] = maxi(int(motif.get("segments_max", 5)), 5)
	motif["bend_min"] = minf(float(motif.get("bend_min", 0.10)), 0.10)
	motif["bend_max"] = minf(float(motif.get("bend_max", 0.26)), 0.26)
	if not motif.has("edge_band"):
		motif["edge_band"] = 0 if rng.randf() < 0.45 else 1
	elif int(motif.get("edge_band", 1)) > 0 and rng.randf() < 0.35:
		motif["edge_band"] = 0
	motif["rock_mass_profile"] = "ridge"
	motif["terrace_count_min"] = 3
	motif["terrace_count_max"] = 3
	motif["spur_count_min"] = 1
	motif["spur_count_max"] = 2
	motif["plateau_pad_chance"] = 0.08
	motif["broken_top_chance"] = 0.14
	motif["plateau_chance"] = 0.02

func _apply_grand_ridge_profile(motif: Dictionary, rng: RandomNumberGenerator) -> void:
	motif["length_min"] = maxf(float(motif.get("length_min", 34.0)), 34.0)
	motif["length_max"] = maxf(float(motif.get("length_max", 56.0)), 56.0)
	motif["thickness_min"] = maxf(float(motif.get("thickness_min", 3.2)), 3.2)
	motif["thickness_max"] = maxf(float(motif.get("thickness_max", 6.0)), 6.0)
	motif["segments_min"] = maxi(int(motif.get("segments_min", 4)), 4)
	motif["segments_max"] = maxi(int(motif.get("segments_max", 6)), 6)
	motif["bend_min"] = minf(float(motif.get("bend_min", 0.12)), 0.12)
	motif["bend_max"] = minf(float(motif.get("bend_max", 0.28)), 0.28)
	motif["edge_band"] = maxi(1, int(motif.get("edge_band", 1)))
	if rng.randf() < 0.35:
		motif["size_bias"] = float(motif.get("size_bias", 1.0)) * rng.randf_range(1.05, 1.18)
	motif["rock_mass_profile"] = "massif"
	motif["terrace_count_min"] = 3
	motif["terrace_count_max"] = 4
	motif["spur_count_min"] = 2
	motif["spur_count_max"] = 3
	motif["plateau_pad_chance"] = 0.42
	motif["broken_top_chance"] = 0.34
	motif["plateau_chance"] = 0.30

func _apply_rock_relief_profile(motif: Dictionary, rng: RandomNumberGenerator) -> void:
	var terrace_min: int = int(motif.get("terrace_count_min", 3))
	var terrace_max: int = max(terrace_min, int(motif.get("terrace_count_max", terrace_min)))
	motif["terrace_count"] = rng.randi_range(terrace_min, terrace_max)
	var spur_min: int = int(motif.get("spur_count_min", 1))
	var spur_max: int = max(spur_min, int(motif.get("spur_count_max", spur_min)))
	motif["spur_count"] = rng.randi_range(spur_min, spur_max)

	var mass_profile: String = String(motif.get("rock_mass_profile", "massif"))
	var summit_profile: int = MapTypes.RockSummitProfile.PEAK
	if mass_profile == "ridge":
		summit_profile = MapTypes.RockSummitProfile.BROKEN_TOP if rng.randf() < float(motif.get("broken_top_chance", 0.14)) else MapTypes.RockSummitProfile.PEAK
	else:
		var roll: float = rng.randf()
		var plateau_chance: float = float(motif.get("plateau_chance", 0.24))
		var broken_top_chance: float = float(motif.get("broken_top_chance", 0.30))
		if roll < plateau_chance:
			summit_profile = MapTypes.RockSummitProfile.PLATEAU
		elif roll < plateau_chance + broken_top_chance:
			summit_profile = MapTypes.RockSummitProfile.BROKEN_TOP
	motif["rock_summit_profile"] = summit_profile

func _apply_canopy_forest_profile(motif: Dictionary, rng: RandomNumberGenerator) -> void:
	motif["blob_count_min"] = maxi(int(motif.get("blob_count_min", 4)), 4)
	motif["blob_count_max"] = maxi(int(motif.get("blob_count_max", 6)), 6)
	motif["radius_min"] = maxf(float(motif.get("radius_min", 4.8)), 4.8)
	motif["radius_max"] = maxf(float(motif.get("radius_max", 8.8)), 8.8)
	motif["edge_band"] = maxi(2, int(motif.get("edge_band", 2)))
	motif["connect_nuclei_chance"] = maxf(float(motif.get("connect_nuclei_chance", 0.48)), 0.48)
	motif["max_links"] = maxi(int(motif.get("max_links", 3)), 3)
	motif["min_component_tiles"] = maxi(int(motif.get("min_component_tiles", 14)), 14)
	if rng.randf() < 0.4:
		motif["size_bias"] = float(motif.get("size_bias", 1.0)) * rng.randf_range(1.04, 1.16)

func _balance_satellite_specs(
	family: Dictionary,
	selected_primary: Array[Dictionary],
	satellite_specs: Array,
	rng: RandomNumberGenerator
) -> Array:
	var occupied := {}
	for motif in selected_primary:
		var anchor: Vector2 = motif.get("anchor", Vector2(0.5, 0.5))
		occupied[_anchor_quadrant(anchor)] = true
	if occupied.size() >= int(family.get("target_occupied_quadrants", 3)):
		return []
	var supplements: Array = []
	for quadrant in range(4):
		if occupied.has(quadrant):
			continue
		var bounds: Array[Vector2] = _quadrant_anchor_bounds(quadrant)
		if rng.randf() < 0.58:
			supplements.append({
				"kind": MapTypes.BlockerType.FOREST,
				"shape": "metaball",
				"forest_profile": "canopy",
				"anchor_min": bounds[0],
				"anchor_max": bounds[1],
				"blob_count_min": 3,
				"blob_count_max": 5,
				"radius_min": 4.4,
				"radius_max": 8.2,
				"edge_band": 2,
				"allow_disconnected_clusters": true,
				"connect_nuclei_chance": 0.46,
				"max_links": 3,
				"min_component_tiles": 12,
				"size_bias_min": 0.96,
				"size_bias_max": 1.14,
				"aggression_min": 0.30,
				"aggression_max": 0.62,
			})
		else:
			supplements.append({
				"kind": MapTypes.BlockerType.ROCK,
				"shape": "spine",
				"ridge_profile": "grand",
				"anchor_min": bounds[0],
				"anchor_max": bounds[1],
				"length_min": 28,
				"length_max": 48,
				"thickness_min": 2.8,
				"thickness_max": 5.0,
				"segments_min": 4,
				"segments_max": 6,
				"edge_band": 1,
				"size_bias_min": 0.94,
				"size_bias_max": 1.12,
				"aggression_min": 0.28,
				"aggression_max": 0.56,
			})
	var existing_midpoints := {}
	for spec in satellite_specs:
		var mid_anchor: Vector2 = (Vector2(spec.get("anchor_min", Vector2.ZERO)) + Vector2(spec.get("anchor_max", Vector2.ONE))) * 0.5
		existing_midpoints[_anchor_quadrant(mid_anchor)] = true
	var filtered: Array = []
	for supplement in supplements:
		var mid_anchor: Vector2 = (Vector2(supplement.get("anchor_min", Vector2.ZERO)) + Vector2(supplement.get("anchor_max", Vector2.ONE))) * 0.5
		if existing_midpoints.has(_anchor_quadrant(mid_anchor)) and rng.randf() < 0.55:
			continue
		filtered.append(supplement)
	return filtered

func _quadrant_anchor_bounds(quadrant: int) -> Array[Vector2]:
	match quadrant:
		0:
			return [Vector2(0.12, 0.12), Vector2(0.34, 0.34)]
		1:
			return [Vector2(0.66, 0.12), Vector2(0.88, 0.34)]
		2:
			return [Vector2(0.12, 0.66), Vector2(0.34, 0.88)]
		_:
			return [Vector2(0.66, 0.66), Vector2(0.88, 0.88)]

func _too_close_to_existing(candidate: Dictionary, existing: Array[Dictionary], min_distance: float) -> bool:
	var anchor: Vector2 = candidate.get("anchor", Vector2(0.5, 0.5))
	for item in existing:
		var other_anchor: Vector2 = item.get("anchor", Vector2(0.5, 0.5))
		if anchor.distance_to(other_anchor) < min_distance:
			return true
	return false

func _pick_water_sector(
	blockers: Array[Dictionary],
	entries: Array[Dictionary],
	rng: RandomNumberGenerator,
	map_width: int,
	map_height: int
) -> int:
	var sector_weights: Array[float] = [1.0, 1.0, 1.0, 1.0]
	for blocker in blockers:
		var anchor: Vector2 = blocker.get("anchor", Vector2(0.5, 0.5))
		var sector: int = _anchor_quadrant(anchor)
		sector_weights[sector] -= 0.35
	for entry in entries:
		var point: Vector2i = entry.get("point", Vector2i.ZERO)
		var normalized := Vector2(
			float(point.x) / maxf(1.0, float(map_width - 1)),
			float(point.y) / maxf(1.0, float(map_height - 1))
		)
		var sector: int = _anchor_quadrant(normalized)
		sector_weights[sector] -= 0.15
	var best_sector: int = 0
	var best_weight: float = sector_weights[0]
	for i in range(1, sector_weights.size()):
		if sector_weights[i] > best_weight:
			best_weight = sector_weights[i]
			best_sector = i
	if rng.randf() < 0.22:
		return rng.randi_range(0, 3)
	return best_sector

func _sector_anchor_ranges(sector: int) -> Array[Vector2]:
	match sector:
		0:
			return [Vector2(0.10, 0.10), Vector2(0.38, 0.38)]
		1:
			return [Vector2(0.62, 0.10), Vector2(0.90, 0.38)]
		2:
			return [Vector2(0.10, 0.62), Vector2(0.38, 0.90)]
		_:
			return [Vector2(0.62, 0.62), Vector2(0.90, 0.90)]

func _anchor_quadrant(anchor: Vector2) -> int:
	var right: bool = anchor.x >= 0.5
	var bottom: bool = anchor.y >= 0.5
	if right and not bottom:
		return 1
	if not right and bottom:
		return 2
	if right and bottom:
		return 3
	return 0

func _random_vec2(min_value: Vector2, max_value: Vector2, rng: RandomNumberGenerator) -> Vector2:
	return Vector2(
		_random_float(min_value.x, max_value.x, rng),
		_random_float(min_value.y, max_value.y, rng)
	)

func _random_float(a: float, b: float, rng: RandomNumberGenerator) -> float:
	return rng.randf_range(minf(a, b), maxf(a, b))

func _shuffle(array: Array, rng: RandomNumberGenerator) -> void:
	for i in range(array.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = array[i]
		array[i] = array[j]
		array[j] = tmp

func _scenario_families() -> Array[Dictionary]:
	return [
		{
			"id": "crescent_guard",
			"primary_count_max": 3,
			"center_offset_min": Vector2(-0.08, -0.06),
			"center_offset_max": Vector2(0.06, 0.06),
			"entry_profiles": [
				{"side": "north", "offset_min": 0.24, "offset_max": 0.46},
				{"side": "south", "offset_min": 0.54, "offset_max": 0.76},
				{"side": "west", "offset_min": 0.34, "offset_max": 0.62},
			],
			"corridor_width_range": Vector2i(3, 5),
			"blocker_motifs": [
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"anchor_min": Vector2(0.14, 0.22),
					"anchor_max": Vector2(0.32, 0.48),
					"length_min": 24,
					"length_max": 40,
					"thickness_min": 2.8,
					"thickness_max": 5.4,
					"bend_min": 0.20,
					"bend_max": 0.42,
					"segments_min": 3,
					"segments_max": 5,
					"edge_band": 1,
				},
				{
					"kind": MapTypes.BlockerType.FOREST,
					"shape": "metaball",
					"forest_profile": "canopy",
					"anchor_min": Vector2(0.70, 0.60),
					"anchor_max": Vector2(0.88, 0.82),
					"blob_count_min": 4,
					"blob_count_max": 6,
					"radius_min": 4.8,
					"radius_max": 9.8,
					"jitter": 0.24,
					"edge_band": 2,
				},
			],
			"water_policy": {
				"enabled": true,
				"style": "river_with_basin",
				"channel_width_min": 2.8,
				"channel_width_max": 4.8,
				"size_bias_min": 0.88,
				"size_bias_max": 1.08,
				"branch_chance": 0.18,
			},
		},
			{
				"id": "split_ridges",
				"primary_count_min": 2,
				"primary_count_max": 3,
				"center_offset_min": Vector2(-0.05, -0.04),
				"center_offset_max": Vector2(0.05, 0.04),
				"entry_profiles": [
					{"side": "north", "offset_min": 0.40, "offset_max": 0.62},
					{"side": "east", "offset_min": 0.34, "offset_max": 0.58},
					{"side": "west", "offset_min": 0.40, "offset_max": 0.66},
				],
				"corridor_width_range": Vector2i(3, 4),
				"blocker_motifs": [
					{
						"kind": MapTypes.BlockerType.ROCK,
						"shape": "spine",
						"ridge_profile": "grand",
						"anchor_min": Vector2(0.22, 0.24),
						"anchor_max": Vector2(0.40, 0.42),
						"length_min": 30,
						"length_max": 48,
						"thickness_min": 2.6,
						"thickness_max": 4.6,
					"bend_min": 0.16,
					"bend_max": 0.34,
					"segments_min": 2,
						"segments_max": 4,
						"edge_band": 1,
					},
					{
						"kind": MapTypes.BlockerType.ROCK,
						"shape": "spine",
						"ridge_profile": "grand",
						"anchor_min": Vector2(0.62, 0.56),
						"anchor_max": Vector2(0.84, 0.74),
						"length_min": 28,
						"length_max": 46,
						"thickness_min": 2.4,
					"thickness_max": 4.8,
					"bend_min": 0.12,
					"bend_max": 0.28,
					"segments_min": 2,
						"segments_max": 4,
						"edge_band": 1,
					},
					{
						"kind": MapTypes.BlockerType.FOREST,
						"shape": "metaball",
						"forest_profile": "canopy",
						"anchor_min": Vector2(0.36, 0.68),
						"anchor_max": Vector2(0.58, 0.86),
						"blob_count_min": 3,
						"blob_count_max": 5,
						"radius_min": 4.2,
						"radius_max": 7.8,
						"jitter": 0.22,
						"edge_band": 2,
					},
				],
				"water_policy": {
					"enabled": true,
					"style": "meandering_river",
					"channel_width_min": 2.6,
					"channel_width_max": 4.2,
					"size_bias_min": 0.82,
					"size_bias_max": 1.02,
				},
			},
		{
			"id": "ridge_plus_flank",
			"primary_count_max": 3,
			"center_offset_min": Vector2(-0.10, -0.06),
			"center_offset_max": Vector2(0.00, 0.07),
			"entry_profiles": [
				{"side": "north", "offset_min": 0.20, "offset_max": 0.42},
				{"side": "south", "offset_min": 0.56, "offset_max": 0.76},
				{"side": "east", "offset_min": 0.46, "offset_max": 0.70},
			],
			"corridor_width_range": Vector2i(3, 5),
			"blocker_motifs": [
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"ridge_profile": "grand",
					"anchor_min": Vector2(0.34, 0.18),
					"anchor_max": Vector2(0.56, 0.34),
					"length_min": 34,
					"length_max": 52,
					"thickness_min": 3.2,
					"thickness_max": 6.2,
					"bend_min": 0.22,
					"bend_max": 0.46,
					"segments_min": 3,
					"segments_max": 5,
					"edge_band": 1,
				},
				{
					"kind": MapTypes.BlockerType.FOREST,
					"shape": "metaball",
					"forest_profile": "canopy",
					"anchor_min": Vector2(0.12, 0.66),
					"anchor_max": Vector2(0.28, 0.84),
					"blob_count_min": 4,
					"blob_count_max": 6,
					"radius_min": 4.6,
					"radius_max": 8.4,
					"jitter": 0.20,
					"edge_band": 2,
				},
			],
			"water_policy": {
				"enabled": true,
				"style": "meandering_river",
				"channel_width_min": 2.6,
				"channel_width_max": 4.4,
				"size_bias_min": 0.82,
				"size_bias_max": 1.02,
			},
		},
		{
			"id": "broken_ring",
			"center_offset_min": Vector2(-0.02, -0.02),
			"center_offset_max": Vector2(0.02, 0.02),
			"entry_profiles": [
				{"side": "north", "offset_min": 0.32, "offset_max": 0.58},
				{"side": "east", "offset_min": 0.34, "offset_max": 0.66},
				{"side": "south", "offset_min": 0.36, "offset_max": 0.64},
				{"side": "west", "offset_min": 0.34, "offset_max": 0.62},
			],
			"corridor_width_range": Vector2i(2, 4),
			"blocker_motifs": [
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"anchor_min": Vector2(0.20, 0.18),
					"anchor_max": Vector2(0.32, 0.30),
					"length_min": 14,
					"length_max": 28,
					"thickness_min": 2.2,
					"thickness_max": 4.0,
					"bend_min": 0.20,
					"bend_max": 0.40,
					"segments_min": 2,
					"segments_max": 4,
					"edge_band": 1,
				},
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"anchor_min": Vector2(0.66, 0.22),
					"anchor_max": Vector2(0.82, 0.34),
					"length_min": 14,
					"length_max": 28,
					"thickness_min": 2.2,
					"thickness_max": 4.2,
					"bend_min": 0.20,
					"bend_max": 0.40,
					"segments_min": 2,
					"segments_max": 4,
					"edge_band": 1,
				},
				{
					"kind": MapTypes.BlockerType.FOREST,
					"shape": "metaball",
					"anchor_min": Vector2(0.36, 0.66),
					"anchor_max": Vector2(0.66, 0.84),
					"blob_count_min": 2,
					"blob_count_max": 5,
					"radius_min": 3.8,
					"radius_max": 7.2,
					"jitter": 0.22,
					"edge_band": 2,
				},
			],
		},
		{
			"id": "forest_pocket",
			"primary_count_max": 3,
			"center_offset_min": Vector2(0.02, -0.08),
			"center_offset_max": Vector2(0.12, 0.02),
			"entry_profiles": [
				{"side": "west", "offset_min": 0.30, "offset_max": 0.54},
				{"side": "south", "offset_min": 0.50, "offset_max": 0.74},
				{"side": "north", "offset_min": 0.42, "offset_max": 0.68},
			],
			"corridor_width_range": Vector2i(3, 5),
			"blocker_motifs": [
				{
					"kind": MapTypes.BlockerType.FOREST,
					"shape": "metaball",
					"forest_profile": "canopy",
					"anchor_min": Vector2(0.14, 0.58),
					"anchor_max": Vector2(0.34, 0.82),
					"blob_count_min": 4,
					"blob_count_max": 6,
					"radius_min": 4.8,
					"radius_max": 9.2,
					"jitter": 0.26,
					"edge_band": 2,
				},
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"ridge_profile": "grand",
					"anchor_min": Vector2(0.62, 0.34),
					"anchor_max": Vector2(0.82, 0.52),
					"length_min": 28,
					"length_max": 44,
					"thickness_min": 2.4,
					"thickness_max": 4.8,
					"bend_min": 0.16,
					"bend_max": 0.34,
					"segments_min": 2,
					"segments_max": 4,
					"edge_band": 1,
				},
			],
			"water_profile": {
				"enabled": true,
				"style": "river_with_basin",
				"anchor_min": Vector2(0.78, 0.16),
				"anchor_max": Vector2(0.90, 0.32),
				"size_bias_min": 0.88,
				"size_bias_max": 1.08,
				"basins_min": 1,
				"basins_max": 1,
				"jitter": 0.12,
				"channel_width_min": 2.8,
				"channel_width_max": 4.6,
				"branch_chance": 0.12,
			},
		},
		{
			"id": "rock_arc_open_flank",
			"center_offset_min": Vector2(-0.04, 0.02),
			"center_offset_max": Vector2(0.08, 0.10),
			"entry_profiles": [
				{"side": "north", "offset_min": 0.22, "offset_max": 0.42},
				{"side": "east", "offset_min": 0.54, "offset_max": 0.76},
				{"side": "west", "offset_min": 0.36, "offset_max": 0.58},
			],
			"corridor_width_range": Vector2i(3, 4),
			"blocker_motifs": [
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"anchor_min": Vector2(0.44, 0.62),
					"anchor_max": Vector2(0.66, 0.80),
					"length_min": 24,
					"length_max": 42,
					"thickness_min": 3.0,
					"thickness_max": 5.6,
					"bend_min": 0.24,
					"bend_max": 0.52,
					"segments_min": 3,
					"segments_max": 5,
					"edge_band": 1,
				},
				{
					"kind": MapTypes.BlockerType.FOREST,
					"shape": "metaball",
					"anchor_min": Vector2(0.16, 0.20),
					"anchor_max": Vector2(0.30, 0.38),
					"blob_count_min": 2,
					"blob_count_max": 4,
					"radius_min": 3.8,
					"radius_max": 7.0,
					"jitter": 0.20,
					"edge_band": 2,
				},
			],
		},
		{
			"id": "double_pinch",
			"center_offset_min": Vector2(-0.06, -0.02),
			"center_offset_max": Vector2(0.06, 0.04),
			"entry_profiles": [
				{"side": "north", "offset_min": 0.30, "offset_max": 0.52},
				{"side": "south", "offset_min": 0.44, "offset_max": 0.68},
				{"side": "east", "offset_min": 0.34, "offset_max": 0.56},
				{"side": "west", "offset_min": 0.42, "offset_max": 0.68},
			],
			"corridor_width_range": Vector2i(2, 4),
			"blocker_motifs": [
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"anchor_min": Vector2(0.34, 0.28),
					"anchor_max": Vector2(0.50, 0.42),
					"length_min": 16,
					"length_max": 28,
					"thickness_min": 2.5,
					"thickness_max": 4.5,
					"bend_min": 0.18,
					"bend_max": 0.36,
					"segments_min": 2,
					"segments_max": 4,
					"edge_band": 1,
				},
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"anchor_min": Vector2(0.56, 0.54),
					"anchor_max": Vector2(0.72, 0.70),
					"length_min": 16,
					"length_max": 28,
					"thickness_min": 2.5,
					"thickness_max": 4.5,
					"bend_min": 0.18,
					"bend_max": 0.36,
					"segments_min": 2,
					"segments_max": 4,
					"edge_band": 1,
				},
			],
		},
		{
			"id": "staggered_barriers",
			"center_offset_min": Vector2(-0.08, -0.05),
			"center_offset_max": Vector2(0.08, 0.05),
			"entry_profiles": [
				{"side": "north", "offset_min": 0.26, "offset_max": 0.48},
				{"side": "east", "offset_min": 0.40, "offset_max": 0.64},
				{"side": "south", "offset_min": 0.52, "offset_max": 0.74},
			],
			"corridor_width_range": Vector2i(3, 5),
			"blocker_motifs": [
				{
					"kind": MapTypes.BlockerType.FOREST,
					"shape": "metaball",
					"anchor_min": Vector2(0.20, 0.20),
					"anchor_max": Vector2(0.36, 0.36),
					"blob_count_min": 2,
					"blob_count_max": 4,
					"radius_min": 3.6,
					"radius_max": 7.2,
					"jitter": 0.22,
					"edge_band": 2,
				},
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"anchor_min": Vector2(0.54, 0.36),
					"anchor_max": Vector2(0.72, 0.52),
					"length_min": 14,
					"length_max": 30,
					"thickness_min": 2.2,
					"thickness_max": 4.8,
					"bend_min": 0.14,
					"bend_max": 0.34,
					"segments_min": 2,
					"segments_max": 4,
					"edge_band": 1,
				},
				{
					"kind": MapTypes.BlockerType.FOREST,
					"shape": "metaball",
					"anchor_min": Vector2(0.66, 0.66),
					"anchor_max": Vector2(0.84, 0.84),
					"blob_count_min": 2,
					"blob_count_max": 4,
					"radius_min": 3.6,
					"radius_max": 7.6,
					"jitter": 0.24,
					"edge_band": 2,
				},
			],
		},
		{
			"id": "offset_gate",
			"primary_count_max": 3,
			"center_offset_min": Vector2(-0.12, -0.02),
			"center_offset_max": Vector2(-0.02, 0.10),
			"entry_profiles": [
				{"side": "east", "offset_min": 0.28, "offset_max": 0.48},
				{"side": "south", "offset_min": 0.48, "offset_max": 0.72},
				{"side": "west", "offset_min": 0.32, "offset_max": 0.58},
			],
			"corridor_width_range": Vector2i(3, 5),
			"blocker_motifs": [
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"ridge_profile": "grand",
					"anchor_min": Vector2(0.58, 0.18),
					"anchor_max": Vector2(0.78, 0.36),
					"length_min": 30,
					"length_max": 50,
					"thickness_min": 2.8,
					"thickness_max": 5.2,
					"bend_min": 0.18,
					"bend_max": 0.40,
					"segments_min": 3,
					"segments_max": 5,
					"edge_band": 1,
				},
				{
					"kind": MapTypes.BlockerType.FOREST,
					"shape": "metaball",
					"forest_profile": "canopy",
					"anchor_min": Vector2(0.20, 0.68),
					"anchor_max": Vector2(0.42, 0.84),
					"blob_count_min": 4,
					"blob_count_max": 6,
					"radius_min": 4.6,
					"radius_max": 9.0,
					"jitter": 0.24,
					"edge_band": 2,
				},
			],
			"water_policy": {
				"enabled": true,
				"style": "meandering_river",
				"channel_width_min": 2.4,
				"channel_width_max": 4.0,
				"size_bias_min": 0.78,
				"size_bias_max": 0.96,
			},
		},
		{
			"id": "channeled_approach",
			"primary_count_max": 3,
			"center_offset_min": Vector2(0.04, -0.10),
			"center_offset_max": Vector2(0.12, 0.02),
			"entry_profiles": [
				{"side": "north", "offset_min": 0.36, "offset_max": 0.60},
				{"side": "east", "offset_min": 0.52, "offset_max": 0.74},
				{"side": "south", "offset_min": 0.30, "offset_max": 0.54},
			],
			"corridor_width_range": Vector2i(2, 4),
			"corridor_buffer": 2,
			"blocker_motifs": [
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"ridge_profile": "grand",
					"anchor_min": Vector2(0.26, 0.46),
					"anchor_max": Vector2(0.40, 0.70),
					"length_min": 30,
					"length_max": 48,
					"thickness_min": 2.8,
					"thickness_max": 5.0,
					"bend_min": 0.20,
					"bend_max": 0.46,
					"segments_min": 3,
					"segments_max": 5,
					"edge_band": 1,
				},
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"anchor_min": Vector2(0.66, 0.24),
					"anchor_max": Vector2(0.84, 0.46),
					"length_min": 18,
					"length_max": 32,
					"thickness_min": 2.4,
					"thickness_max": 4.6,
					"bend_min": 0.18,
					"bend_max": 0.34,
					"segments_min": 2,
					"segments_max": 4,
					"edge_band": 1,
				},
			],
			"water_profile": {
				"enabled": true,
				"style": "river_with_basin",
				"anchor_min": Vector2(0.74, 0.62),
				"anchor_max": Vector2(0.90, 0.84),
				"size_bias_min": 0.82,
				"size_bias_max": 1.02,
				"basins_min": 1,
				"basins_max": 2,
				"jitter": 0.14,
				"channel_width_min": 2.6,
				"channel_width_max": 4.4,
				"branch_chance": 0.18,
			},
		},
		{
			"id": "river_spine_crossing",
			"primary_count_min": 3,
			"primary_count_max": 3,
			"satellite_count_min": 2,
			"satellite_count_max": 4,
			"center_offset_min": Vector2(-0.04, -0.04),
			"center_offset_max": Vector2(0.08, 0.06),
			"entry_profiles": [
				{"side": "north", "offset_min": 0.26, "offset_max": 0.48},
				{"side": "east", "offset_min": 0.48, "offset_max": 0.72},
				{"side": "south", "offset_min": 0.42, "offset_max": 0.68},
			],
			"corridor_width_range": Vector2i(3, 5),
			"blocker_motifs": [
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"ridge_profile": "grand",
					"anchor_min": Vector2(0.14, 0.20),
					"anchor_max": Vector2(0.26, 0.36),
					"length_min": 36,
					"length_max": 56,
					"thickness_min": 3.2,
					"thickness_max": 5.8,
					"segments_min": 4,
					"segments_max": 6,
					"edge_band": 1,
				},
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"ridge_profile": "grand",
					"anchor_min": Vector2(0.68, 0.58),
					"anchor_max": Vector2(0.82, 0.76),
					"length_min": 30,
					"length_max": 50,
					"thickness_min": 2.8,
					"thickness_max": 5.2,
					"segments_min": 4,
					"segments_max": 6,
					"edge_band": 1,
				},
				{
					"kind": MapTypes.BlockerType.FOREST,
					"shape": "metaball",
					"forest_profile": "canopy",
					"anchor_min": Vector2(0.18, 0.62),
					"anchor_max": Vector2(0.36, 0.84),
					"blob_count_min": 4,
					"blob_count_max": 6,
					"radius_min": 4.8,
					"radius_max": 9.0,
					"jitter": 0.22,
					"edge_band": 2,
				},
			],
			"water_policy": {
				"enabled": true,
				"style": "river_with_basin",
				"channel_width_min": 2.8,
				"channel_width_max": 4.8,
				"size_bias_min": 0.92,
				"size_bias_max": 1.12,
				"branch_chance": 0.22,
			},
		},
		{
			"id": "deep_woodland_valley",
			"primary_count_min": 3,
			"primary_count_max": 3,
			"satellite_count_min": 2,
			"satellite_count_max": 4,
			"center_offset_min": Vector2(-0.10, 0.00),
			"center_offset_max": Vector2(0.02, 0.10),
			"entry_profiles": [
				{"side": "west", "offset_min": 0.28, "offset_max": 0.48},
				{"side": "north", "offset_min": 0.44, "offset_max": 0.68},
				{"side": "south", "offset_min": 0.48, "offset_max": 0.74},
			],
			"corridor_width_range": Vector2i(3, 5),
			"blocker_motifs": [
				{
					"kind": MapTypes.BlockerType.FOREST,
					"shape": "metaball",
					"forest_profile": "canopy",
					"anchor_min": Vector2(0.16, 0.18),
					"anchor_max": Vector2(0.34, 0.36),
					"blob_count_min": 4,
					"blob_count_max": 6,
					"radius_min": 4.6,
					"radius_max": 8.8,
					"jitter": 0.24,
					"edge_band": 2,
				},
				{
					"kind": MapTypes.BlockerType.FOREST,
					"shape": "metaball",
					"forest_profile": "canopy",
					"anchor_min": Vector2(0.62, 0.58),
					"anchor_max": Vector2(0.84, 0.82),
					"blob_count_min": 4,
					"blob_count_max": 6,
					"radius_min": 4.8,
					"radius_max": 9.2,
					"jitter": 0.24,
					"edge_band": 2,
				},
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"ridge_profile": "grand",
					"anchor_min": Vector2(0.52, 0.16),
					"anchor_max": Vector2(0.74, 0.28),
					"length_min": 30,
					"length_max": 48,
					"thickness_min": 2.8,
					"thickness_max": 5.2,
					"segments_min": 4,
					"segments_max": 6,
					"edge_band": 1,
				},
			],
			"water_policy": {
				"enabled": true,
				"style": "meandering_river",
				"channel_width_min": 2.6,
				"channel_width_max": 4.2,
				"size_bias_min": 0.88,
				"size_bias_max": 1.06,
				"branch_chance": 0.14,
			},
		},
	]
