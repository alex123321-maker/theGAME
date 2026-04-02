extends Node

const GameConfigData = preload("res://autoload/game_config.gd")

signal seed_changed(new_seed: int)
signal overlay_changed(overlay_mode: String)
signal grid_visibility_changed(is_visible: bool)
signal props_visibility_changed(is_visible: bool)
signal reference_seed_changed(index: int, seed: int)

var current_seed: int = 101
var current_profile_id: String = "default"
var current_overlay_mode: String = "none"
var is_grid_visible: bool = true
var is_props_visible: bool = true
var reference_seeds: Array[int] = []
var current_reference_seed_index: int = 0

func _ready() -> void:
	_load_reference_seeds()
	if reference_seeds.is_empty():
		reference_seeds = GameConfigData.REFERENCE_SEEDS.duplicate()
	if not reference_seeds.is_empty():
		var match_index: int = reference_seeds.find(current_seed)
		current_reference_seed_index = max(0, match_index)
		reference_seed_changed.emit(current_reference_seed_index, reference_seeds[current_reference_seed_index])

func set_seed(new_seed: int) -> void:
	current_seed = new_seed
	seed_changed.emit(current_seed)
	_sync_reference_seed_index()

func randomize_seed() -> int:
	var unix_seed: int = int(Time.get_unix_time_from_system())
	set_seed(unix_seed)
	return current_seed

func set_overlay_mode(mode: String) -> void:
	current_overlay_mode = mode
	overlay_changed.emit(current_overlay_mode)

func cycle_overlay_mode() -> void:
	var current_index: int = GameConfigData.OVERLAY_MODES.find(current_overlay_mode)
	if current_index == -1:
		set_overlay_mode(GameConfigData.OVERLAY_MODES[0])
		return

	var next_index: int = (current_index + 1) % GameConfigData.OVERLAY_MODES.size()
	set_overlay_mode(GameConfigData.OVERLAY_MODES[next_index])

func set_grid_visible(value: bool) -> void:
	is_grid_visible = value
	grid_visibility_changed.emit(is_grid_visible)

func toggle_grid_visible() -> void:
	set_grid_visible(not is_grid_visible)

func set_props_visible(value: bool) -> void:
	is_props_visible = value
	props_visibility_changed.emit(is_props_visible)

func toggle_props_visible() -> void:
	set_props_visible(not is_props_visible)

func step_reference_seed(direction: int) -> int:
	if reference_seeds.is_empty():
		return current_seed

	current_reference_seed_index = posmod(current_reference_seed_index + direction, reference_seeds.size())
	var target_seed: int = reference_seeds[current_reference_seed_index]
	reference_seed_changed.emit(current_reference_seed_index, target_seed)
	set_seed(target_seed)
	return target_seed

func _load_reference_seeds() -> void:
	var file_path := "res://tests/seeds/reference_seeds.json"
	if not FileAccess.file_exists(file_path):
		return

	var source := FileAccess.get_file_as_string(file_path)
	var parsed: Variant = JSON.parse_string(source)
	if typeof(parsed) != TYPE_DICTIONARY:
		return

	var raw: Array = parsed.get("reference_seeds", [])
	for value in raw:
		reference_seeds.append(int(value))

func _sync_reference_seed_index() -> void:
	if reference_seeds.is_empty():
		return
	var index: int = reference_seeds.find(current_seed)
	if index != -1:
		current_reference_seed_index = index
	reference_seed_changed.emit(current_reference_seed_index, reference_seeds[current_reference_seed_index])
