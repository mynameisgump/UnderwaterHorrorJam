extends CharacterBody3D
class_name PlayerController

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

@export_group("Depth & Decompression")
## The node representing the water surface (e.g. Wader mesh).
@export var surface_node: Node3D
## Meters per second the acclimated depth shifts toward actual depth.
@export var acclimation_rate: float = 2.0
## How many meters above acclimated depth the player can safely ascend.
@export var safe_ascent_limit: float = 15.0
## How many meters below acclimated depth the player can safely descend.
@export var safe_descent_limit: float = 30.0

signal oxygen_changed(current: float, maximum: float)
signal depth_changed(depth_m: float, acclimated_m: float, safe_ceil_m: float, safe_floor_m: float)
signal bends_risk_changed(at_risk: bool)

const MOUSE_SENS: float = 0.002

var current_oxygen: float
var _dash_timer: float = 0.0
var _acclimated_depth: float = 0.0
var _at_bends_risk: bool = false

@onready var camera: Camera3D = $Camera3D
@onready var oxy_label: Label = $Control/OxyLabel
@onready var depth_meter: DepthMeterUI = $Control/DepthMeter

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	current_oxygen = max_oxygen

## Call this after surface_node has been assigned to seed acclimated depth correctly.
func initialize_depth() -> void:
	_acclimated_depth = get_depth()

## Returns depth in metres below the water surface. Positive = deeper.
func get_depth() -> float:
	if surface_node == null:
		return -global_position.y
	return surface_node.global_position.y - global_position.y

## Shallowest depth the player can safely ascend to right now.
func get_safe_ceiling() -> float:
	return maxf(_acclimated_depth - safe_ascent_limit, 0.0)

## Deepest depth the player can safely descend to right now.
func get_safe_floor() -> float:
	return _acclimated_depth + safe_descent_limit

func _process(_delta: float) -> void:
	_update_ui()

func _update_ui() -> void:
	oxy_label.text = "O2  %.0f%%" % ((current_oxygen / max_oxygen) * 100.0)
	depth_meter.update_depth(
		get_depth(), _acclimated_depth,
		get_safe_ceiling(), get_safe_floor(),
		_at_bends_risk
	)

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

	_update_acclimation(delta)
	_check_bends_risk()

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
	depth_changed.emit(get_depth(), _acclimated_depth, get_safe_ceiling(), get_safe_floor())

## Slowly shifts acclimated depth toward actual depth, simulating nitrogen saturation.
func _update_acclimation(delta: float) -> void:
	var depth := get_depth()
	var diff := depth - _acclimated_depth
	var step := acclimation_rate * delta
	if absf(diff) <= step:
		_acclimated_depth = depth
	else:
		_acclimated_depth += signf(diff) * step

## Emits bends_risk_changed when the player ascends above their safe ceiling.
func _check_bends_risk() -> void:
	var was_at_risk := _at_bends_risk
	_at_bends_risk = get_depth() < get_safe_ceiling()
	if _at_bends_risk != was_at_risk:
		bends_risk_changed.emit(_at_bends_risk)
