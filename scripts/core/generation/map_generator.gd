extends RefCounted
class_name MapGenerator

const GameConfigData = preload("res://autoload/game_config.gd")
const MapDataClass = preload("res://scripts/core/map/map_data.gd")
const MapGenerationConfigClass = preload("res://scripts/core/generation/map_generation_config.gd")
const LayoutComposerClass = preload("res://scripts/core/generation/layout_composer.gd")
const RegionGeneratorClass = preload("res://scripts/core/generation/region_generator.gd")
const BlockerGeneratorClass = preload("res://scripts/core/generation/blocker_generator.gd")
const WaterGeneratorClass = preload("res://scripts/core/generation/water_generator.gd")
const VoidFillerGeneratorClass = preload("res://scripts/core/generation/void_filler_generator.gd")
const RoadGeneratorClass = preload("res://scripts/core/generation/road_generator.gd")
const TransitionResolverClass = preload("res://scripts/core/generation/transition_resolver.gd")
const MapValidatorClass = preload("res://scripts/core/map/map_validator.gd")

var _layout_composer := LayoutComposerClass.new()
var _region_generator := RegionGeneratorClass.new()
var _blocker_generator := BlockerGeneratorClass.new()
var _water_generator := WaterGeneratorClass.new()
var _void_filler_generator := VoidFillerGeneratorClass.new()
var _road_generator := RoadGeneratorClass.new()
var _transition_resolver := TransitionResolverClass.new()
var _validator := MapValidatorClass.new()

func generate(seed: int, config: Dictionary) -> MapData:
	var generation_config = MapGenerationConfigClass.new()
	generation_config.apply_from_dict(config)
	var best_map: MapData = null
	var best_report: Dictionary = {}
	var best_score: float = -1.0
	for attempt_index in range(generation_config.generation_attempts):
		var map_data: MapData = _generate_attempt(seed, generation_config, attempt_index)
		map_data.validation_report = _validator.validate(map_data, generation_config)
		map_data.generation_summary = _build_generation_summary(map_data, map_data.validation_report, generation_config, attempt_index)
		var score: float = float(map_data.validation_report.get("quality_score", 0.0))
		if _is_better_attempt(map_data.validation_report, best_report, score, best_score):
			best_map = map_data
			best_report = map_data.validation_report
			best_score = score
		if bool(map_data.validation_report.get("ok", false)) and score >= generation_config.target_quality_score:
			break
	return best_map if best_map != null else _generate_attempt(seed, generation_config, 0)

func _generate_attempt(seed: int, generation_config, attempt_index: int) -> MapData:
	var map_data := MapDataClass.new(generation_config.width, generation_config.height)
	map_data.seed = seed
	map_data.generator_version = GameConfigData.GENERATOR_VERSION
	map_data.profile_id = generation_config.profile_id

	var rng := RandomNumberGenerator.new()
	rng.seed = _attempt_seed(seed, attempt_index)
	var composition: Dictionary = _generate_layout_composition(map_data, rng, generation_config)
	_generate_entries(map_data, composition)
	_generate_regions(map_data, rng, generation_config, composition)
	_generate_clearing(map_data, rng, generation_config, composition)
	_generate_major_blockers(map_data, rng, generation_config, composition)
	_generate_water_body(map_data, rng, generation_config, composition)
	_generate_void_fillers(map_data, rng, generation_config, composition)
	_generate_roads(map_data, rng, generation_config, composition)
	_resolve_surface_transitions(map_data)
	_build_buildable_mask(map_data)
	map_data.rebuild_layers_from_tiles()
	return map_data

func _generate_layout_composition(map_data: MapData, rng: RandomNumberGenerator, config) -> Dictionary:
	return _layout_composer.compose(map_data, rng, config)

func _generate_regions(map_data: MapData, _rng: RandomNumberGenerator, _config, composition: Dictionary) -> void:
	_region_generator.initialize_ground(map_data, composition)
	_region_generator.stamp_approach_regions(map_data, composition)

func _generate_clearing(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	_region_generator.generate_clearing(map_data, rng, config, composition)
	_region_generator.stamp_approach_regions(map_data, composition)

func _generate_major_blockers(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	_blocker_generator.generate(map_data, rng, config, composition)

func _generate_water_body(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	_water_generator.generate(map_data, rng, config, composition)

func _generate_void_fillers(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	_void_filler_generator.generate(map_data, rng, config, composition)

func _generate_entries(map_data: MapData, composition: Dictionary) -> void:
	for entry_spec in composition.get("entries", []):
		var entry_point: Vector2i = entry_spec.get("point", Vector2i.ZERO)
		if not map_data.entry_points.has(entry_point):
			map_data.entry_points.append(entry_point)

func _generate_roads(map_data: MapData, rng: RandomNumberGenerator, config, composition: Dictionary) -> void:
	map_data.roads.clear()
	_road_generator.generate(map_data, rng, config, composition)

func _resolve_surface_transitions(map_data: MapData) -> void:
	_transition_resolver.resolve(map_data)

func _build_buildable_mask(map_data: MapData) -> void:
	_transition_resolver.build_buildable_mask(map_data)

func _build_generation_summary(
	map_data: MapData,
	report: Dictionary,
	config,
	attempt_index: int
) -> Dictionary:
	var blocker_regions: int = 0
	var soft_filler_regions: int = 0
	var water_regions: int = 0
	for region in map_data.regions:
		var region_type: int = int(region.get("type", MapTypes.RegionType.NONE))
		if region_type == MapTypes.RegionType.BLOCKER_MASS:
			if bool(region.get("metadata", {}).get("soft", false)):
				soft_filler_regions += 1
			else:
				blocker_regions += 1
		elif region_type == MapTypes.RegionType.WATER_REGION:
			water_regions += 1
	var road_length_tiles: int = 0
	for road in map_data.roads:
		road_length_tiles += Array(road.get("tiles", [])).size()
	return {
		"seed": map_data.seed,
		"attempt_index": attempt_index,
		"attempt_seed": _attempt_seed(map_data.seed, attempt_index),
		"attempt_count": config.generation_attempts,
		"composition_template_id": map_data.composition_template_id,
		"entry_count": map_data.entry_points.size(),
		"clearing_area": map_data.central_zone_tiles.size(),
		"blocker_region_count": blocker_regions,
		"soft_filler_region_count": soft_filler_regions,
		"has_water": water_regions > 0,
		"road_length_tiles": road_length_tiles,
		"validation_ok": bool(report.get("ok", false)),
		"validation_warning_count": Array(report.get("warnings", [])).size(),
		"quality_score": float(report.get("quality_score", 0.0)),
		"quality_tier": String(report.get("quality_tier", "unknown")),
	}

func _attempt_seed(seed: int, attempt_index: int) -> int:
	return absi(int((seed * 92821) ^ (attempt_index * 68917) ^ 177451))

func _is_better_attempt(candidate_report: Dictionary, best_report: Dictionary, candidate_score: float, best_score: float) -> bool:
	if best_report.is_empty():
		return true
	var candidate_ok: bool = bool(candidate_report.get("ok", false))
	var best_ok: bool = bool(best_report.get("ok", false))
	if candidate_ok != best_ok:
		return candidate_ok
	if not is_equal_approx(candidate_score, best_score):
		return candidate_score > best_score
	var candidate_errors: int = Array(candidate_report.get("errors", [])).size()
	var best_errors: int = Array(best_report.get("errors", [])).size()
	if candidate_errors != best_errors:
		return candidate_errors < best_errors
	var candidate_warnings: int = Array(candidate_report.get("warnings", [])).size()
	var best_warnings: int = Array(best_report.get("warnings", [])).size()
	if candidate_warnings != best_warnings:
		return candidate_warnings < best_warnings
	var candidate_buildable: float = float(candidate_report.get("metrics", {}).get("buildable_in_center_pct", 0.0))
	var best_buildable: float = float(best_report.get("metrics", {}).get("buildable_in_center_pct", 0.0))
	return candidate_buildable > best_buildable
