extends Node3D

@onready var world_env = $WorldEnvironment

var env: Environment;
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	env = world_env.environment;
	
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
