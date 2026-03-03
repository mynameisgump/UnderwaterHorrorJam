extends Node3D

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var wader: Node3D = $Wader
@onready var player: Node3D = $Player
@onready var water_mat: ShaderMaterial = $Wader/MeshInstance3D.get_surface_override_material(0) if $Wader/MeshInstance3D.get_surface_override_material(0) else $Wader/MeshInstance3D.mesh.material

@export var ior_far := 1.333
@export var ior_close := 0.8
@export var ior_dist_max := 150.0
@export var ior_dist_min := 10.0

var env: Environment
var fog_mat: ShaderMaterial

func _ready() -> void:
	env = world_env.environment
	env.volumetric_fog_density = 0.0

	var surface_y := wader.global_position.y
	var fog_shader := load("res://fog.gdshader") as Shader
	fog_mat = ShaderMaterial.new()
	fog_mat.shader = fog_shader
	fog_mat.set_shader_parameter("surface_y", surface_y)
	fog_mat.set_shader_parameter("max_depth", surface_y)
	fog_mat.set_shader_parameter("fog_color", Color(0.02, 0.08, 0.15, 1.0))

	var fog_volume := FogVolume.new()
	fog_volume.size = Vector3(1000, surface_y + 100, 1000)
	fog_volume.position = Vector3(0, surface_y / 2.0, 0)
	fog_volume.material = fog_mat
	add_child(fog_volume)

func _process(_delta: float) -> void:
	fog_mat.set_shader_parameter("player_pos", player.global_position)

	var dist_to_surface := wader.global_position.y - player.global_position.y
	var t = clamp((dist_to_surface - ior_dist_min) / (ior_dist_max - ior_dist_min), 0.0, 1.0)
	water_mat.set_shader_parameter("index_of_refraction", lerpf(ior_close, ior_far, t))
