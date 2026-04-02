extends Node

signal regenerate_current_requested
signal randomize_seed_requested
signal apply_seed_requested(seed: int)
signal reference_seed_next_requested
signal reference_seed_prev_requested
signal grid_toggle_requested
signal props_toggle_requested
signal overlay_cycle_requested
signal export_json_requested
signal screenshot_requested
signal log_requested

func request_regenerate_current() -> void:
	regenerate_current_requested.emit()

func request_randomize_seed() -> void:
	randomize_seed_requested.emit()

func request_apply_seed(seed: int) -> void:
	apply_seed_requested.emit(seed)

func request_reference_seed_next() -> void:
	reference_seed_next_requested.emit()

func request_reference_seed_prev() -> void:
	reference_seed_prev_requested.emit()

func request_grid_toggle() -> void:
	grid_toggle_requested.emit()

func request_props_toggle() -> void:
	props_toggle_requested.emit()

func request_overlay_cycle() -> void:
	overlay_cycle_requested.emit()

func request_export_json() -> void:
	export_json_requested.emit()

func request_screenshot() -> void:
	screenshot_requested.emit()

func request_log() -> void:
	log_requested.emit()
