extends MarginContainer
class_name DebugRuntimePanel

const GameConfigData = preload("res://autoload/game_config.gd")

signal apply_seed_requested(seed_value: int)
signal regenerate_current_requested
signal randomize_seed_requested
signal export_json_requested
signal screenshot_requested
signal log_requested
signal prev_seed_requested
signal next_seed_requested
signal toggle_grid_requested
signal toggle_props_requested
signal cycle_overlay_requested
signal panel_collapsed_changed(is_collapsed: bool)

@onready var _seed_input: LineEdit = $Panel/Root/Body/SeedRow/SeedInput
@onready var _entry_count_input: LineEdit = $Panel/Root/Body/LayoutRow/EntryCountInput
@onready var _village_tile_input: LineEdit = $Panel/Root/Body/LayoutRow/VillageTileCountInput
@onready var _current_seed_value: Label = $Panel/Root/Body/GridA/CurrentSeedValue
@onready var _overlay_value: Label = $Panel/Root/Body/GridA/OverlayValue
@onready var _grid_value: Label = $Panel/Root/Body/GridA/GridValue
@onready var _props_value: Label = $Panel/Root/Body/GridA/PropsValue
@onready var _validation_value: Label = $Panel/Root/Body/GridA/ValidationValue
@onready var _reference_value: Label = $Panel/Root/Body/GridA/ReferenceValue
@onready var _status_value: Label = $Panel/Root/Body/StatusValue
@onready var _details_value: RichTextLabel = $Panel/Root/Body/DetailsValue
@onready var _body: VBoxContainer = $Panel/Root/Body
@onready var _collapse_button: Button = $Panel/Root/Header/CollapseButton

var _collapsed: bool = false

func _ready() -> void:
	$Panel/Root/Body/SeedRow/ApplySeedButton.pressed.connect(_on_apply_seed_pressed)
	$Panel/Root/Body/ActionRowA/RegenerateButton.pressed.connect(func() -> void: regenerate_current_requested.emit())
	$Panel/Root/Body/ActionRowA/RandomizeButton.pressed.connect(func() -> void: randomize_seed_requested.emit())
	$Panel/Root/Body/ActionRowB/ExportJsonButton.pressed.connect(func() -> void: export_json_requested.emit())
	$Panel/Root/Body/ActionRowB/ScreenshotButton.pressed.connect(func() -> void: screenshot_requested.emit())
	$Panel/Root/Body/ActionRowB/LogButton.pressed.connect(func() -> void: log_requested.emit())
	$Panel/Root/Body/ActionRowA/PrevSeedButton.pressed.connect(func() -> void: prev_seed_requested.emit())
	$Panel/Root/Body/ActionRowA/NextSeedButton.pressed.connect(func() -> void: next_seed_requested.emit())
	$Panel/Root/Body/ActionRowC/ToggleGridButton.pressed.connect(func() -> void: toggle_grid_requested.emit())
	$Panel/Root/Body/ActionRowC/TogglePropsButton.pressed.connect(func() -> void: toggle_props_requested.emit())
	$Panel/Root/Body/ActionRowC/CycleOverlayButton.pressed.connect(func() -> void: cycle_overlay_requested.emit())
	_collapse_button.pressed.connect(_on_collapse_pressed)
	_seed_input.text_submitted.connect(_on_seed_submitted)

func set_current_seed(seed: int) -> void:
	_current_seed_value.text = str(seed)
	if not _seed_input.has_focus():
		_seed_input.text = str(seed)

func set_generation_controls(entry_count: int, village_tile_count: int) -> void:
	if not _entry_count_input.has_focus():
		_entry_count_input.text = str(entry_count)
	if not _village_tile_input.has_focus():
		_village_tile_input.text = str(village_tile_count)

func set_overlay_grid_props(overlay_mode: String, grid_visible: bool, props_visible: bool) -> void:
	_overlay_value.text = overlay_mode
	_grid_value.text = "on" if grid_visible else "off"
	_props_value.text = "on" if props_visible else "off"

func set_validation_summary(ok: bool, details: String) -> void:
	_validation_value.text = "OK" if ok else "FAIL"
	_details_value.text = details

func set_reference_seed(index: int, total: int, seed: int) -> void:
	_reference_value.text = "%d/%d (seed=%d)" % [index + 1, max(1, total), seed]

func set_status_message(message: String) -> void:
	_status_value.text = message

func get_requested_entry_count() -> int:
	var raw_text: String = _entry_count_input.text.strip_edges()
	var parsed: int = GameConfigData.DEFAULT_ENTRY_COUNT if raw_text.is_empty() else raw_text.to_int()
	return clampi(
		parsed,
		GameConfigData.MIN_ENTRY_COUNT,
		GameConfigData.MAX_ENTRY_COUNT
	)

func get_requested_village_tile_count() -> int:
	var raw_text: String = _village_tile_input.text.strip_edges()
	var parsed: int = GameConfigData.DEFAULT_VILLAGE_TILE_COUNT if raw_text.is_empty() else raw_text.to_int()
	return clampi(
		parsed,
		GameConfigData.MIN_VILLAGE_TILE_COUNT,
		GameConfigData.MAX_VILLAGE_TILE_COUNT
	)

func _on_apply_seed_pressed() -> void:
	var parsed: int = _seed_input.text.to_int()
	apply_seed_requested.emit(parsed)

func _on_seed_submitted(text: String) -> void:
	apply_seed_requested.emit(text.to_int())

func _on_collapse_pressed() -> void:
	_collapsed = not _collapsed
	_body.visible = not _collapsed
	_collapse_button.text = "Expand" if _collapsed else "Collapse"
	panel_collapsed_changed.emit(_collapsed)
