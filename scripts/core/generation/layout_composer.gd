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
	var blockers: Array[Dictionary] = _build_blockers(chosen, rng, config)
	var water: Variant = _build_water_profile(chosen, rng)
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

func _build_blockers(family: Dictionary, rng: RandomNumberGenerator, config) -> Array[Dictionary]:
	var blockers: Array[Dictionary] = []
	var motifs: Array = family.get("blocker_motifs", [])
	var shuffled_motifs: Array = motifs.duplicate(true)
	_shuffle(shuffled_motifs, rng)
	if shuffled_motifs.is_empty():
		return blockers
	var blocker_target: int = clampi(config.blocker_count, 1, shuffled_motifs.size())
	for index in range(blocker_target):
		var motif: Dictionary = shuffled_motifs[index].duplicate(true)
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
		motif["region_id"] = 200 + index
		blockers.append(motif)
	return blockers

func _build_water_profile(family: Dictionary, rng: RandomNumberGenerator) -> Variant:
	var profile: Dictionary = family.get("water_profile", {})
	if profile.is_empty():
		return null
	if not bool(profile.get("enabled", true)):
		return null
	var anchor_min: Vector2 = profile.get("anchor_min", Vector2(0.72, 0.18))
	var anchor_max: Vector2 = profile.get("anchor_max", Vector2(0.88, 0.34))
	return {
		"style": String(profile.get("style", "soft_basin")),
		"anchor": _random_vec2(anchor_min, anchor_max, rng),
		"size_bias": _random_float(
			float(profile.get("size_bias_min", 0.85)),
			float(profile.get("size_bias_max", 1.10)),
			rng
		),
		"basins_min": int(profile.get("basins_min", 1)),
		"basins_max": int(profile.get("basins_max", 2)),
		"jitter": float(profile.get("jitter", 0.16)),
	}

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
