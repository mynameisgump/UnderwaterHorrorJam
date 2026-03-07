extends Area3D
class_name OxygenTank

@export var oxygen_restore: float = 25.0
@export var blink_interval: float = 0.8

@onready var blink_light: OmniLight3D = $BlinkLight
@onready var mesh: MeshInstance3D = $MeshInstance3D

var mesh_mat:StandardMaterial3D;


var _blink_timer: float = 0.0
var _light_on: bool = true

func _ready() -> void:
	mesh_mat = mesh.get_surface_override_material(0);
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	_blink_timer += delta
	if _blink_timer >= blink_interval:
		_blink_timer -= blink_interval
		_light_on = not _light_on
		mesh_mat.emission_enabled = not mesh_mat.emission_enabled;
		blink_light.visible = _light_on

func _on_body_entered(body: Node3D) -> void:
	if body is PlayerController:
		body.add_oxygen(oxygen_restore)
		queue_free()
