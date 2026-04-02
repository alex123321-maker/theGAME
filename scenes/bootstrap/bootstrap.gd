extends Node

@onready var map_view: Node = $MapView
@onready var run_context = get_node("/root/RunContext")

func _ready() -> void:
	run_context.set_seed(run_context.current_seed)
