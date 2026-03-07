extends Node3D

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var wader: Node3D = $Wader
@onready var player: PlayerController = $Player
@onready var water_mat: ShaderMaterial = $Wader/MeshInstance3D.get_surface_override_material(0) if $Wader/MeshInstance3D.get_surface_override_material(0) else $Wader/MeshInstance3D.mesh.material

@export var ior_far := 1.333
@export var ior_close := 0.8
@export var ior_dist_max := 150.0
@export var ior_dist_min := 10.0

func _ready() -> void:
	player.surface_node = wader
	player.initialize_depth()

func _process(_delta: float) -> void:
	var dist_to_surface := wader.global_position.y - player.global_position.y
	var t = clamp((dist_to_surface - ior_dist_min) / (ior_dist_max - ior_dist_min), 0.0, 1.0)
	water_mat.set_shader_parameter("index_of_refraction", lerpf(ior_close, ior_far, t))
