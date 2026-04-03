extends RefCounted
class_name LayoutComposer

const GenerationUtilsClass = preload("res://scripts/core/generation/generation_utils.gd")

func compose(map_data: MapData, rng: RandomNumberGenerator, config) -> Dictionary:
	var templates: Array[Dictionary] = [
		{
			"id": "open_flanks",
			"center_offset": Vector2(0.0, 0.0),
			"entries": [
				{"side": "north", "offset": 0.42},
				{"side": "south", "offset": 0.56},
				{"side": "west", "offset": 0.48},
			],
			"blockers": [
				{"kind": MapTypes.BlockerType.FOREST, "anchor": Vector2(0.18, 0.30), "size_bias": 1.05},
				{"kind": MapTypes.BlockerType.ROCK, "anchor": Vector2(0.84, 0.68), "size_bias": 0.95},
			],
			"water": null,
		},
		{
			"id": "waterside_gate",
			"center_offset": Vector2(0.08, -0.04),
			"entries": [
				{"side": "north", "offset": 0.34},
				{"side": "east", "offset": 0.44},
				{"side": "south", "offset": 0.62},
			],
			"blockers": [
				{"kind": MapTypes.BlockerType.FOREST, "anchor": Vector2(0.16, 0.72), "size_bias": 1.00},
			],
			"water": {"anchor": Vector2(0.78, 0.20), "size_bias": 1.15},
		},
		{
			"id": "double_gate",
			"center_offset": Vector2(0.0, 0.05),
			"entries": [
				{"side": "north", "offset": 0.50},
				{"side": "east", "offset": 0.56},
				{"side": "west", "offset": 0.38},
			],
			"blockers": [
				{"kind": MapTypes.BlockerType.ROCK, "anchor": Vector2(0.30, 0.45), "size_bias": 1.10},
				{"kind": MapTypes.BlockerType.FOREST, "anchor": Vector2(0.74, 0.52), "size_bias": 1.05},
			],
			"water": null,
		},
		{
			"id": "asymmetric_corridors",
			"center_offset": Vector2(-0.05, 0.02),
			"entries": [
				{"side": "north", "offset": 0.24},
				{"side": "east", "offset": 0.70},
				{"side": "south", "offset": 0.58},
				{"side": "west", "offset": 0.42},
			],
			"blockers": [
				{"kind": MapTypes.BlockerType.FOREST, "anchor": Vector2(0.22, 0.22), "size_bias": 0.95},
				{"kind": MapTypes.BlockerType.ROCK, "anchor": Vector2(0.76, 0.78), "size_bias": 1.00},
			],
			"water": {"anchor": Vector2(0.84, 0.26), "size_bias": 0.90},
		},
	]

	var chosen: Dictionary = templates[rng.randi_range(0, templates.size() - 1)].duplicate(true)
	var center := Vector2(
		(float(map_data.width) * 0.5) + (chosen["center_offset"].x * float(map_data.width) * 0.18),
		(float(map_data.height) * 0.5) + (chosen["center_offset"].y * float(map_data.height) * 0.18)
	)

	var requested_entries: int = clampi(config.entry_count, 2, mini(4, chosen["entries"].size()))
	var entries: Array[Dictionary] = []
	for index in range(requested_entries):
		var spec: Dictionary = chosen["entries"][index].duplicate(true)
		spec["point"] = GenerationUtilsClass.point_on_side(
			String(spec["side"]),
			map_data.width,
			map_data.height,
			float(spec["offset"]),
			config.approach_padding
		)
		spec["region_id"] = 100 + index
		entries.append(spec)

	var blockers: Array[Dictionary] = []
	var raw_blockers: Array = chosen.get("blockers", [])
	var blocker_target: int = mini(config.blocker_count, raw_blockers.size())
	for index in range(blocker_target):
		var blocker_spec: Dictionary = raw_blockers[index].duplicate(true)
		blocker_spec["region_id"] = 200 + index
		blockers.append(blocker_spec)

	return {
		"template_id": String(chosen["id"]),
		"center": center,
		"entries": entries,
		"blockers": blockers,
		"water": chosen.get("water"),
	}
