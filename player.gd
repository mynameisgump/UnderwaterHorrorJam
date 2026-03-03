extends CharacterBody3D

@export_group("Swimming")
@export var swim_speed: float = 5.0
@export var acceleration: float = 20.0
@export var drag: float = 4.0
@export var buoyancy: float = 0.5

@export_group("Dash")
@export var dash_impulse: float = 15.0
@export var dash_cooldown: float = 1.0
@export var dash_oxygen_cost: float = 15.0

@export_group("Oxygen")
@export var max_oxygen: float = 100.0
@export var oxygen_drain: float = 2.0

@onready var oxy_label: Label = $Control/OxyLabel
@onready var depth_label: Label = $Control/DepthLabel


signal oxygen_changed(current: float, maximum: float)

const MOUSE_SENS: float = 0.002

var current_oxygen: float
var _dash_timer: float = 0.0

@onready var camera: Camera3D = $Camera3D

func _process(delta: float) -> void:
	oxy_label.text = str(current_oxygen);
	depth_label.text = str(global_position.y)

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	current_oxygen = max_oxygen

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clamp(camera.rotation.x, -PI / 2.2, PI / 2.2)

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event.is_action_pressed("dash") and _dash_timer <= 0.0 and current_oxygen >= dash_oxygen_cost:
		_dash()

func _dash() -> void:
	var input_dir: Vector2 = Input.get_vector("move_l", "move_r", "move_f", "move_b")
	var cam_basis: Basis = camera.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	var right: Vector3 = cam_basis.x

	var dash_dir: Vector3 = (forward * -input_dir.y + right * input_dir.x)

	if Input.is_action_pressed("move_u"):
		dash_dir.y += 1.0
	if Input.is_action_pressed("move_d"):
		dash_dir.y -= 1.0

	if dash_dir.length_squared() < 0.01:
		dash_dir = forward

	velocity = dash_dir.normalized() * dash_impulse
	_dash_timer = dash_cooldown
	_consume_oxygen(dash_oxygen_cost)

func _consume_oxygen(amount: float) -> void:
	current_oxygen = maxf(current_oxygen - amount, 0.0)
	oxygen_changed.emit(current_oxygen, max_oxygen)

func _physics_process(delta: float) -> void:
	if _dash_timer > 0.0:
		_dash_timer -= delta

	current_oxygen = maxf(current_oxygen - oxygen_drain * delta, 0.0)
	oxygen_changed.emit(current_oxygen, max_oxygen)

	var input_dir: Vector2 = Input.get_vector("move_l", "move_r", "move_f", "move_b")

	var cam_basis: Basis = camera.global_transform.basis
	var forward: Vector3 = -cam_basis.z
	var right: Vector3 = cam_basis.x

	var wish_dir: Vector3 = (forward * -input_dir.y + right * input_dir.x).normalized()

	if Input.is_action_pressed("move_u"):
		wish_dir.y += 1.0
	if Input.is_action_pressed("move_d"):
		wish_dir.y -= 1.0

	if wish_dir.length() > 1.0:
		wish_dir = wish_dir.normalized()

	velocity += wish_dir * acceleration * delta
	velocity.y += buoyancy * delta
	velocity *= 1.0 - drag * delta

	var speed: float = velocity.length()
	if speed > swim_speed and _dash_timer <= 0.0:
		velocity = velocity.normalized() * swim_speed

	move_and_slide()


func get_depth(delta: float) -> float:
	return global_position.y
