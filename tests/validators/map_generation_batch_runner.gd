extends SceneTree

const GameConfigData = preload("res://autoload/game_config.gd")
const MapGeneratorClass = preload("res://scripts/core/generation/map_generator.gd")

const MIN_ACCEPTABLE_SCORE: float = 62.0

func _init() -> void:
	var generator := MapGeneratorClass.new()
	var config: Dictionary = GameConfigData.build_default_generator_config()
	var seeds: Array[int] = _load_reference_seeds()
	var failures: Array[String] = []
	var total_score: float = 0.0
	var lowest_score: float = 100.0

	for seed in seeds:
		var map_data: MapData = generator.generate(seed, config)
		var report: Dictionary = map_data.validation_report
		var score: float = float(report.get("quality_score", 0.0))
		var errors: Array = report.get("errors", [])
		total_score += score
		lowest_score = minf(lowest_score, score)
		print(
			"seed=%d quality=%.1f tier=%s ok=%s composition=%s attempt=%d/%d" % [
				seed,
				score,
				str(report.get("quality_tier", "unknown")),
				str(report.get("ok", false)),
				str(map_data.generation_summary.get("composition_template_id", "unknown")),
				int(map_data.generation_summary.get("attempt_index", 0)) + 1,
				int(map_data.generation_summary.get("attempt_count", 1)),
			]
		)
		if not bool(report.get("ok", false)):
			failures.append("seed=%d report_errors=%s" % [seed, ",".join(errors)])
		elif score < MIN_ACCEPTABLE_SCORE:
			failures.append("seed=%d quality_score_below_threshold(%.1f)" % [seed, score])

	var average_score: float = total_score / maxf(1.0, float(seeds.size()))
	print("reference_seed_count=%d average_quality=%.1f lowest_quality=%.1f" % [seeds.size(), average_score, lowest_score])

	if not failures.is_empty():
		push_error("Map generation batch validation failed")
		for failure in failures:
			push_error(failure)
		quit(1)
		return

	quit(0)

func _load_reference_seeds() -> Array[int]:
	var file_path := "res://tests/seeds/reference_seeds.json"
	if not FileAccess.file_exists(file_path):
		return GameConfigData.REFERENCE_SEEDS.duplicate()
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(file_path))
	if typeof(parsed) != TYPE_DICTIONARY:
		return GameConfigData.REFERENCE_SEEDS.duplicate()
	var output: Array[int] = []
	for value in parsed.get("reference_seeds", []):
		output.append(int(value))
	return output if not output.is_empty() else GameConfigData.REFERENCE_SEEDS.duplicate()
