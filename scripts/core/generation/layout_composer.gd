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
		var primary_target: int = clampi(config.blocker_count, 1, mini(2, shuffled_primary.size()))
		for index in range(primary_target):
			var primary := _realize_motif(shuffled_primary[index], rng, region_counter, "primary")
			region_counter += 1
			selected_primary.append(primary)
			all_blockers.append(primary)

	if not satellite_specs.is_empty():
		var sat_min: int = int(family.get("satellite_count_min", 1))
		var sat_max: int = max(sat_min, int(family.get("satellite_count_max", 3)))
		var sat_target: int = rng.randi_range(sat_min, sat_max)
		var satellite_candidates: Array = _satellite_candidates(satellite_specs, selected_primary)
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
	var anchor_min: Vector2 = sector_ranges[0]
	var anchor_max: Vector2 = sector_ranges[1]
	var anchor := _random_vec2(anchor_min, anchor_max, rng)
	var center_pull: float = clampf(float(policy.get("center_pull", 0.08)), 0.0, 0.25)
	anchor = anchor.lerp(Vector2(0.5, 0.5), center_pull * rng.randf_range(0.0, 0.8))
	var anchor_jitter: float = float(policy.get("anchor_jitter", 0.06))
	anchor.x = clampf(anchor.x + rng.randf_range(-anchor_jitter, anchor_jitter), 0.08, 0.92)
	anchor.y = clampf(anchor.y + rng.randf_range(-anchor_jitter, anchor_jitter), 0.08, 0.92)
	var basins_min: int = int(policy.get("basins_min", 1))
	var basins_max: int = max(basins_min, int(policy.get("basins_max", 2)))
	return {
		"style": String(policy.get("style", "soft_basin")),
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
			"blob_count_min": 2,
			"blob_count_max": 3,
			"radius_min": 3.0,
			"radius_max": 5.8,
			"edge_band": 1,
			"size_bias_min": 0.80,
			"size_bias_max": 0.98,
			"aggression_min": 0.28,
			"aggression_max": 0.58,
			"allow_disconnected_clusters": true,
			"connect_nuclei_chance": 0.32,
			"max_links": 2,
			"min_component_tiles": 9,
		},
		{
			"kind": MapTypes.BlockerType.ROCK,
			"shape": "spine",
			"ridge_profile": "thin",
			"anchor_min": Vector2(0.66, 0.14),
			"anchor_max": Vector2(0.88, 0.36),
			"length_min": 10,
			"length_max": 20,
			"thickness_min": 1.8,
			"thickness_max": 3.4,
			"segments_min": 2,
			"segments_max": 3,
			"edge_band": 1,
			"size_bias_min": 0.74,
			"size_bias_max": 0.94,
			"aggression_min": 0.24,
			"aggression_max": 0.54,
		},
		{
			"kind": MapTypes.BlockerType.FOREST,
			"shape": "metaball",
			"anchor_min": Vector2(0.60, 0.62),
			"anchor_max": Vector2(0.90, 0.90),
			"blob_count_min": 2,
			"blob_count_max": 4,
			"radius_min": 2.8,
			"radius_max": 6.0,
			"edge_band": 1,
			"size_bias_min": 0.76,
			"size_bias_max": 1.02,
			"aggression_min": 0.24,
			"aggression_max": 0.56,
			"allow_disconnected_clusters": true,
			"connect_nuclei_chance": 0.28,
			"max_links": 2,
			"min_component_tiles": 10,
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
	if int(motif.get("kind", MapTypes.BlockerType.NONE)) == MapTypes.BlockerType.FOREST and String(motif.get("shape", "metaball")) == "metaball":
		var allow_disconnected: bool = bool(motif.get("allow_disconnected_clusters", motif_role == "satellite"))
		motif["allow_disconnected_clusters"] = allow_disconnected
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
					"anchor_min": Vector2(0.70, 0.60),
					"anchor_max": Vector2(0.88, 0.82),
					"blob_count_min": 2,
					"blob_count_max": 5,
					"radius_min": 4.5,
					"radius_max": 9.5,
					"jitter": 0.24,
					"edge_band": 2,
				},
			],
		},
			{
				"id": "split_ridges",
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
						"ridge_profile": "thin",
						"anchor_min": Vector2(0.22, 0.24),
						"anchor_max": Vector2(0.40, 0.42),
						"length_min": 18,
						"length_max": 32,
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
						"ridge_profile": "thin",
						"anchor_min": Vector2(0.62, 0.56),
						"anchor_max": Vector2(0.84, 0.74),
						"length_min": 18,
						"length_max": 34,
						"thickness_min": 2.4,
					"thickness_max": 4.8,
					"bend_min": 0.12,
					"bend_max": 0.28,
					"segments_min": 2,
						"segments_max": 4,
						"edge_band": 1,
					},
				],
			},
		{
			"id": "ridge_plus_flank",
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
					"anchor_min": Vector2(0.34, 0.18),
					"anchor_max": Vector2(0.56, 0.34),
					"length_min": 30,
					"length_max": 44,
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
					"anchor_min": Vector2(0.12, 0.66),
					"anchor_max": Vector2(0.28, 0.84),
					"blob_count_min": 2,
					"blob_count_max": 4,
					"radius_min": 4.0,
					"radius_max": 7.5,
					"jitter": 0.20,
					"edge_band": 2,
				},
			],
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
					"anchor_min": Vector2(0.14, 0.58),
					"anchor_max": Vector2(0.34, 0.82),
					"blob_count_min": 3,
					"blob_count_max": 5,
					"radius_min": 4.2,
					"radius_max": 8.8,
					"jitter": 0.26,
					"edge_band": 2,
				},
				{
					"kind": MapTypes.BlockerType.ROCK,
					"shape": "spine",
					"anchor_min": Vector2(0.62, 0.34),
					"anchor_max": Vector2(0.82, 0.52),
					"length_min": 18,
					"length_max": 32,
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
				"style": "soft_basin",
				"anchor_min": Vector2(0.78, 0.16),
				"anchor_max": Vector2(0.90, 0.32),
				"size_bias_min": 0.80,
				"size_bias_max": 1.00,
				"basins_min": 1,
				"basins_max": 1,
				"jitter": 0.12,
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
					"anchor_min": Vector2(0.58, 0.18),
					"anchor_max": Vector2(0.78, 0.36),
					"length_min": 20,
					"length_max": 36,
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
					"anchor_min": Vector2(0.20, 0.68),
					"anchor_max": Vector2(0.42, 0.84),
					"blob_count_min": 2,
					"blob_count_max": 5,
					"radius_min": 4.0,
					"radius_max": 8.4,
					"jitter": 0.24,
					"edge_band": 2,
				},
			],
		},
		{
			"id": "channeled_approach",
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
					"anchor_min": Vector2(0.26, 0.46),
					"anchor_max": Vector2(0.40, 0.70),
					"length_min": 24,
					"length_max": 38,
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
				"style": "soft_basin",
				"anchor_min": Vector2(0.74, 0.62),
				"anchor_max": Vector2(0.90, 0.84),
				"size_bias_min": 0.72,
				"size_bias_max": 0.94,
				"basins_min": 1,
				"basins_max": 2,
				"jitter": 0.14,
			},
		},
	]
