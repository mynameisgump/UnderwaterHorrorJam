extends Area3D
class_name Mine

@export var oxygen_damage: float = 70.0
@export var arm_delay: float = 2.0
@export var bob_speed: float = 0.65
@export var bob_amplitude: float = 1.8
@export var pulse_speed: float = 1.4

var _armed: bool = false
var _exploded: bool = false
var _arm_timer: float = 0.0
var _bob_time: float = 0.0
var _base_y: float = 0.0

@onready var mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var light: OmniLight3D = $OmniLight3D

func _ready() -> void:
	add_to_group("mines")
	body_entered.connect(_on_body_entered)
	_bob_time = randf() * TAU
	_base_y = position.y
	_arm_timer = arm_delay

func _process(delta: float) -> void:
	if _exploded:
		return

	if _arm_timer > 0.0:
		_arm_timer -= delta
		if _arm_timer <= 0.0:
			_armed = true

	_bob_time += delta
	position.y = _base_y + sin(_bob_time * bob_speed) * bob_amplitude

	if light and _armed:
		var pulse := sin(_bob_time * pulse_speed) * 0.5 + 0.5
		light.light_energy = 0.4 + pulse * 2.0

func _on_body_entered(body: Node3D) -> void:
	if _exploded or not _armed:
		return
	if body is PlayerController:
		_detonate(body as PlayerController)

func _detonate(player: PlayerController) -> void:
	_exploded = true
	set_deferred("monitoring", false)

	if mesh_instance:
		mesh_instance.visible = false
	if light:
		light.light_color = Color(1.0, 0.55, 0.05)
		light.light_energy = 25.0

	player.damage_oxygen(oxygen_damage)

	await get_tree().create_timer(0.3).timeout
	queue_free()
