extends Node3D

const GameConfigData = preload("res://autoload/game_config.gd")
const WorldGridProjection3DClass = preload("res://scripts/presentation/world_grid_projection_3d.gd")
const MapGeneratorClass = preload("res://scripts/core/generation/map_generator.gd")
const MapSerializerClass = preload("res://scripts/core/map/map_serializer.gd")
const MapTestRunnerClass = preload("res://scripts/map_test_runner.gd")

@onready var camera: Camera3D = $Camera3D
@onready var map_renderer: Node3D = $MapRenderer3D
@onready var runtime_panel: DebugRuntimePanel = $CanvasLayer/DebugRuntimePanel
@onready var run_context = get_node("/root/RunContext")
@onready var debug_bus = get_node("/root/DebugBus")

var _generator := MapGeneratorClass.new()
var _serializer := MapSerializerClass.new()
var _test_runner := MapTestRunnerClass.new()
var _map_data: MapData
var _camera_initialized: bool = false
var _last_generation_config: Dictionary = {}

func _ready() -> void:
	_connect_debug_bus()
	_connect_runtime_panel()
	_connect_run_context()
	var default_config: Dictionary = GameConfigData.build_default_generator_config()
	runtime_panel.set_generation_controls(
		int(default_config.get("entry_count", GameConfigData.DEFAULT_ENTRY_COUNT)),
		int(default_config.get("village_tile_count", GameConfigData.DEFAULT_VILLAGE_TILE_COUNT))
	)
	_generate_current_map("initial load")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_update_hover_from_mouse()

	if event.is_action_pressed("regenerate_map"):
		debug_bus.request_regenerate_current()
	elif event.is_action_pressed("randomize_seed"):
		debug_bus.request_randomize_seed()
	elif event.is_action_pressed("debug_toggle_layers"):
		debug_bus.request_overlay_cycle()
	elif event.is_action_pressed("debug_toggle_grid"):
		debug_bus.request_grid_toggle()

func _process(delta: float) -> void:
	_handle_camera_input(delta)

func _handle_camera_input(delta: float) -> void:
	var move_speed: float = 25.0
	var zoom_speed: float = 14.0
	var move := Vector3.ZERO

	if Input.is_action_pressed("camera_pan_up"):
		move.z -= 1.0
	if Input.is_action_pressed("camera_pan_down"):
		move.z += 1.0
	if Input.is_action_pressed("camera_pan_left"):
		move.x -= 1.0
	if Input.is_action_pressed("camera_pan_right"):
		move.x += 1.0

	if move != Vector3.ZERO:
		camera.position += move.normalized() * move_speed * delta

	if Input.is_action_pressed("camera_zoom_in"):
		camera.size = maxf(8.0, camera.size - (zoom_speed * delta))
	if Input.is_action_pressed("camera_zoom_out"):
		camera.size = minf(120.0, camera.size + (zoom_speed * delta))

func apply_seed_and_regenerate(seed: int) -> void:
	run_context.set_seed(seed)
	_generate_current_map("apply seed")

func _connect_debug_bus() -> void:
	debug_bus.regenerate_current_requested.connect(_on_regenerate_current_requested)
	debug_bus.randomize_seed_requested.connect(_on_randomize_seed_requested)
	debug_bus.apply_seed_requested.connect(_on_apply_seed_requested)
	debug_bus.reference_seed_next_requested.connect(_on_reference_seed_next_requested)
	debug_bus.reference_seed_prev_requested.connect(_on_reference_seed_prev_requested)
	debug_bus.grid_toggle_requested.connect(_on_grid_toggle_requested)
	debug_bus.props_toggle_requested.connect(_on_props_toggle_requested)
	debug_bus.overlay_cycle_requested.connect(_on_overlay_cycle_requested)
	debug_bus.export_json_requested.connect(_on_export_json_requested)
	debug_bus.screenshot_requested.connect(_on_screenshot_requested)
	debug_bus.log_requested.connect(_on_log_requested)

func _connect_runtime_panel() -> void:
	runtime_panel.apply_seed_requested.connect(func(seed: int) -> void:
		debug_bus.request_apply_seed(seed)
	)
	runtime_panel.regenerate_current_requested.connect(func() -> void:
		debug_bus.request_regenerate_current()
	)
	runtime_panel.randomize_seed_requested.connect(func() -> void:
		debug_bus.request_randomize_seed()
	)
	runtime_panel.export_json_requested.connect(func() -> void:
		debug_bus.request_export_json()
	)
	runtime_panel.screenshot_requested.connect(func() -> void:
		debug_bus.request_screenshot()
	)
	runtime_panel.log_requested.connect(func() -> void:
		debug_bus.request_log()
	)
	runtime_panel.prev_seed_requested.connect(func() -> void:
		debug_bus.request_reference_seed_prev()
	)
	runtime_panel.next_seed_requested.connect(func() -> void:
		debug_bus.request_reference_seed_next()
	)
	runtime_panel.toggle_grid_requested.connect(func() -> void:
		debug_bus.request_grid_toggle()
	)
	runtime_panel.toggle_props_requested.connect(func() -> void:
		debug_bus.request_props_toggle()
	)
	runtime_panel.cycle_overlay_requested.connect(func() -> void:
		debug_bus.request_overlay_cycle()
	)

func _connect_run_context() -> void:
	run_context.seed_changed.connect(_on_seed_changed)
	run_context.overlay_changed.connect(_on_overlay_changed)
	run_context.grid_visibility_changed.connect(_on_grid_visibility_changed)
	run_context.props_visibility_changed.connect(_on_props_visibility_changed)
	run_context.reference_seed_changed.connect(_on_reference_seed_changed)

func _on_regenerate_current_requested() -> void:
	_generate_current_map("regenerate current")

func _on_randomize_seed_requested() -> void:
	run_context.randomize_seed()
	_generate_current_map("randomize seed")

func _on_apply_seed_requested(seed: int) -> void:
	run_context.set_seed(seed)
	_generate_current_map("apply seed")

func _on_reference_seed_next_requested() -> void:
	run_context.step_reference_seed(1)
	_generate_current_map("next reference seed")

func _on_reference_seed_prev_requested() -> void:
	run_context.step_reference_seed(-1)
	_generate_current_map("previous reference seed")

func _on_grid_toggle_requested() -> void:
	run_context.toggle_grid_visible()

func _on_props_toggle_requested() -> void:
	run_context.toggle_props_visible()

func _on_overlay_cycle_requested() -> void:
	run_context.cycle_overlay_mode()

func _on_export_json_requested() -> void:
	var exported_path: String = _export_json_file()
	runtime_panel.set_status_message("JSON exported to %s" % exported_path)

func _on_screenshot_requested() -> void:
	var screenshot_path: String = _save_screenshot("manual")
	runtime_panel.set_status_message("Screenshot saved to %s" % screenshot_path)

func _on_log_requested() -> void:
	_print_diagnostics_to_console()
	runtime_panel.set_status_message("Diagnostics logged to console.")

func _on_seed_changed(new_seed: int) -> void:
	runtime_panel.set_current_seed(new_seed)

func _on_overlay_changed(new_overlay_mode: String) -> void:
	map_renderer.set_overlay_mode(new_overlay_mode)
	_update_runtime_panel()

func _on_grid_visibility_changed(is_visible: bool) -> void:
	map_renderer.set_grid_visible(is_visible)
	_update_runtime_panel()

func _on_props_visibility_changed(is_visible: bool) -> void:
	map_renderer.set_props_visible(is_visible)
	_update_runtime_panel()

func _on_reference_seed_changed(index: int, seed: int) -> void:
	var total: int = run_context.reference_seeds.size()
	runtime_panel.set_reference_seed(index, total, seed)

func _generate_current_map(reason: String) -> void:
	_last_generation_config = _build_generation_config()
	_map_data = _generator.generate(run_context.current_seed, _last_generation_config)

	if not _camera_initialized:
		var center_world: Vector3 = WorldGridProjection3DClass.map_center_world(_map_data.width, _map_data.height, 0.0)
		var max_extent: float = float(maxi(_map_data.width, _map_data.height)) * WorldGridProjection3DClass.TILE_WORLD_SIZE
		camera.position = center_world + Vector3(-max_extent * 0.32, max_extent * 0.38, max_extent * 0.32)
		camera.size = max_extent * 0.30
		camera.look_at(center_world, Vector3.UP)
		_camera_initialized = true

	map_renderer.set_map_data(_map_data)
	map_renderer.set_grid_visible(run_context.is_grid_visible)
	map_renderer.set_props_visible(run_context.is_props_visible)
	map_renderer.set_overlay_mode(run_context.current_overlay_mode)
	_update_hover_from_mouse()

	_update_runtime_panel()
	runtime_panel.set_status_message("Map generated (%s)." % reason)

func _update_runtime_panel() -> void:
	if _map_data == null:
		return

	var report: Dictionary = _map_data.validation_report
	var is_ok: bool = bool(report.get("ok", false))
	runtime_panel.set_current_seed(run_context.current_seed)
	runtime_panel.set_generation_controls(
		int(_last_generation_config.get("entry_count", GameConfigData.DEFAULT_ENTRY_COUNT)),
		int(_last_generation_config.get("village_tile_count", GameConfigData.DEFAULT_VILLAGE_TILE_COUNT))
	)
	runtime_panel.set_overlay_grid_props(
		run_context.current_overlay_mode,
		run_context.is_grid_visible,
		run_context.is_props_visible
	)
	runtime_panel.set_validation_summary(is_ok, _format_validation_report(report))

func _format_validation_report(report: Dictionary) -> String:
	var metrics: Dictionary = report.get("metrics", {})
	var errors: Array = report.get("errors", [])
	var warnings: Array = report.get("warnings", [])
	var stages: Array = report.get("stages", [])
	var summary: Dictionary = _map_data.generation_summary if _map_data != null else {}
	var lines: Array[String] = []
	lines.append("profile_id=%s" % run_context.current_profile_id)
	lines.append("generator_version=%d" % GameConfigData.GENERATOR_VERSION)
	lines.append("composition=%s" % String(summary.get("composition_template_id", _map_data.composition_template_id if _map_data != null else "unknown")))
	lines.append("requested_entries=%d" % int(_last_generation_config.get("entry_count", 0)))
	lines.append("entry_points=%d" % int(metrics.get("entry_count", 0)))
	lines.append("requested_center_area=%d" % int(_last_generation_config.get("village_tile_count", 0)))
	lines.append("center_tiles=%d" % int(metrics.get("central_zone_tile_count", 0)))
	lines.append("connected_center_tiles=%d" % int(metrics.get("connected_center_tiles", 0)))
	lines.append("reachable_entries=%d" % int(metrics.get("reachable_entries", 0)))
	lines.append("road_tiles=%d" % int(metrics.get("road_tile_count", 0)))
	lines.append("bridge_tiles=%d" % int(metrics.get("bridge_tile_count", 0)))
	lines.append("water_tiles=%d" % int(metrics.get("water_tile_count", 0)))
	lines.append("blocker_tiles=%d" % int(metrics.get("blocker_tile_count", 0)))
	lines.append("buildable_tiles=%d" % int(metrics.get("buildable_tiles", 0)))
	lines.append("buildable_in_center_pct=%.1f" % float(metrics.get("buildable_in_center_pct", 0.0)))
	if errors.is_empty():
		lines.append("errors: none")
	else:
		for item in errors:
			lines.append("error: %s" % String(item))
	if warnings.is_empty():
		lines.append("warnings: none")
	else:
		for item in warnings:
			lines.append("warning: %s" % String(item))
	for stage in stages:
		lines.append(
			"stage[%s]=%s%s" % [
				String(stage.get("stage", "unknown")),
				"ok" if bool(stage.get("ok", false)) else "fail",
				"" if String(stage.get("reason", "")).is_empty() else " (%s)" % String(stage.get("reason", "")),
			]
		)
	return "\n".join(lines)

func _export_json_file() -> String:
	var json_text: String = export_current_map_json()
	var base_dir := "user://exports"
	DirAccess.make_dir_recursive_absolute(base_dir)
	var path := "%s/map_seed_%d.json" % [base_dir, run_context.current_seed]
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(json_text)
	return ProjectSettings.globalize_path(path)

func _save_screenshot(tag: String) -> String:
	var base_dir := "user://screenshots"
	DirAccess.make_dir_recursive_absolute(base_dir)
	var path := "%s/map_seed_%d_%s.png" % [base_dir, run_context.current_seed, tag]
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png(path)
	return ProjectSettings.globalize_path(path)

func _print_diagnostics_to_console() -> void:
	if _map_data == null:
		return
	print("=== MAP DIAGNOSTICS ===")
	print("seed=", _map_data.seed, " profile=", _map_data.profile_id, " version=", _map_data.generator_version)
	print("summary=", JSON.stringify(_map_data.generation_summary, "\t"))
	print(JSON.stringify(_map_data.validation_report, "\t"))
	if run_context.reference_seeds.size() >= 10:
		var output_dir := "user://screenshots/reference"
		var paths: Array[String] = await _test_runner.run_batch_screenshots(self, run_context.reference_seeds, output_dir)
		print("reference batch screenshots=", paths.size())

func _update_hover_from_mouse() -> void:
	if _map_data == null:
		return
	var mouse_position: Vector2 = get_viewport().get_mouse_position()
	var from: Vector3 = camera.project_ray_origin(mouse_position)
	var direction: Vector3 = camera.project_ray_normal(mouse_position)
	if absf(direction.y) <= 0.00001:
		map_renderer.set_hover_tile(Vector2i.ZERO, false)
		return
	var t: float = -from.y / direction.y
	if t < 0.0:
		map_renderer.set_hover_tile(Vector2i.ZERO, false)
		return
	var hit: Vector3 = from + (direction * t)
	var logical: Vector2i = map_renderer.get_logical_from_world(hit)
	var is_valid: bool = _map_data.is_in_bounds(logical.x, logical.y)
	map_renderer.set_hover_tile(logical, is_valid)

func export_current_map_json() -> String:
	if _map_data == null:
		return ""
	return _serializer.to_json_text(_map_data)

func _build_generation_config() -> Dictionary:
	var config := GameConfigData.build_default_generator_config()
	config["profile_id"] = run_context.current_profile_id
	config["entry_count"] = runtime_panel.get_requested_entry_count()
	config["village_tile_count"] = runtime_panel.get_requested_village_tile_count()
	return config
