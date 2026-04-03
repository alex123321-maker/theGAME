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
	var map_data := MapDataClass.new(generation_config.width, generation_config.height)
	map_data.seed = seed
	map_data.generator_version = GameConfigData.GENERATOR_VERSION
	map_data.profile_id = generation_config.profile_id

	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var composition: Dictionary = _generate_layout_composition(map_data, rng, generation_config)
	_generate_regions(map_data, rng, generation_config, composition)
	_generate_clearing(map_data, rng, generation_config, composition)
	_generate_major_blockers(map_data, rng, generation_config, composition)
	_generate_water_body(map_data, rng, generation_config, composition)
	_generate_void_fillers(map_data, rng, generation_config, composition)
	_generate_entries(map_data, composition)
	_generate_roads(map_data, rng, generation_config, composition)
	_resolve_surface_transitions(map_data)
	_build_buildable_mask(map_data)
	map_data.rebuild_layers_from_tiles()
	map_data.validation_report = _validator.validate(map_data)
	map_data.generation_summary = _build_generation_summary(map_data)
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
	map_data.entry_points.clear()
	map_data.roads.clear()
	_road_generator.generate(map_data, rng, config, composition)

func _resolve_surface_transitions(map_data: MapData) -> void:
	_transition_resolver.resolve(map_data)

func _build_buildable_mask(map_data: MapData) -> void:
	_transition_resolver.build_buildable_mask(map_data)

func _build_generation_summary(map_data: MapData) -> Dictionary:
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
		"composition_template_id": map_data.composition_template_id,
		"entry_count": map_data.entry_points.size(),
		"clearing_area": map_data.central_zone_tiles.size(),
		"blocker_region_count": blocker_regions,
		"soft_filler_region_count": soft_filler_regions,
		"has_water": water_regions > 0,
		"road_length_tiles": road_length_tiles,
		"validation_ok": bool(map_data.validation_report.get("ok", false)),
		"validation_warning_count": Array(map_data.validation_report.get("warnings", [])).size(),
	}
