extends RefCounted
class_name MapGenerator

const GameConfigData = preload("res://autoload/game_config.gd")
const MacroShapePass = preload("res://scripts/core/generation/passes/macro_shape_pass.gd")
const RoutesPass = preload("res://scripts/core/generation/passes/routes_pass.gd")
const ObstaclesPass = preload("res://scripts/core/generation/passes/obstacles_pass.gd")
const ResourcesPass = preload("res://scripts/core/generation/passes/resources_pass.gd")
const CleanupPass = preload("res://scripts/core/generation/passes/cleanup_pass.gd")

const MapDataClass = preload("res://scripts/core/map/map_data.gd")
const MapValidatorClass = preload("res://scripts/core/map/map_validator.gd")

var _macro_shape_pass := MacroShapePass.new()
var _routes_pass := RoutesPass.new()
var _obstacles_pass := ObstaclesPass.new()
var _resources_pass := ResourcesPass.new()
var _cleanup_pass := CleanupPass.new()
var _validator := MapValidatorClass.new()

## Builds a new MapData from config and seed.
func generate(seed: int, config: Dictionary) -> MapData:
	var width: int = int(config.get("width", GameConfigData.DEFAULT_MAP_WIDTH))
	var height: int = int(config.get("height", GameConfigData.DEFAULT_MAP_HEIGHT))

	var map_data := MapDataClass.new(width, height)
	map_data.seed = seed
	map_data.generator_version = GameConfigData.GENERATOR_VERSION
	map_data.profile_id = String(config.get("profile_id", "default"))

	var rng := RandomNumberGenerator.new()
	rng.seed = seed

	_macro_shape_pass.apply(map_data, rng, config)
	_routes_pass.apply(map_data, rng, config)
	_obstacles_pass.apply(map_data, rng, config)
	_resources_pass.apply(map_data, rng, config)
	_cleanup_pass.apply(map_data, rng, config)

	map_data.validation_report = _validator.validate(map_data)
	return map_data
