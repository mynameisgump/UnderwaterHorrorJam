extends CharacterBody3D

@export var swim_speed: float = 5.0
@export var acceleration: float = 20.0
@export var drag: float = 4.0
@export var buoyancy: float = 0.5
@export var dash_impulse: float = 15.0
@export var dash_cooldown: float = 1.0

const MOUSE_SENS: float = 0.002

var _dash_timer: float = 0.0

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clamp(camera.rotation.x, -PI / 2.2, PI / 2.2)

	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

	if event.is_action_pressed("dash") and _dash_timer <= 0.0:
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

func _physics_process(delta: float) -> void:
	if _dash_timer > 0.0:
		_dash_timer -= delta

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
