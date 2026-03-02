extends CharacterBody3D

const SPEED = 4.0
const DRAG = 4.0
const BUOYANCY = 1.5     
const MOUSE_SENS = 0.002

@onready var camera = $Camera3D 

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventMouseMotion:
		rotate_y(-event.relative.x * MOUSE_SENS)
		camera.rotate_x(-event.relative.y * MOUSE_SENS)
		camera.rotation.x = clamp(camera.rotation.x, -PI/2.2, PI/2.2)
	
	if event.is_action_pressed("ui_cancel"):
		Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _physics_process(delta):
	var input_dir = Input.get_vector("move_l", "move_r", "move_f", "move_b")
	
	var wish_dir = (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	
	var vertical = 0.0
	if Input.is_action_pressed("move_u"):   
		vertical = 1.0
	if Input.is_action_pressed("move_d"):   
		vertical = -1.0
	
	wish_dir.y = vertical
	
	if wish_dir.length() > 0:
		velocity = velocity.lerp(wish_dir * SPEED, SPEED * delta)
	
	velocity = velocity.lerp(Vector3.ZERO, DRAG * delta)
	
	#velocity.y += BUOYANCY * delta
	velocity.y = clamp(velocity.y, -SPEED, SPEED)
	
	move_and_slide()
