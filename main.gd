extends Node3D

const OxygenTankScene: PackedScene = preload("res://oxygen_tank.tscn")

@onready var wader: Node3D = $Wader
@onready var player: PlayerController = $Player
@onready var water_mat: ShaderMaterial = $Wader/MeshInstance3D.get_surface_override_material(0) if $Wader/MeshInstance3D.get_surface_override_material(0) else $Wader/MeshInstance3D.mesh.material
@onready var ceiling_light: DirectionalLight3D = $CeilingLight
@onready var floor_light: DirectionalLight3D = $FloorLight
@onready var ground_mesh: MeshInstance3D = $Ground

@export var ior_far := 1.333
@export var ior_close := 0.8
@export var ior_dist_max := 150.0
@export var ior_dist_min := 10.0

@export_group("Zones")
@export var zone_size: float = 100.0
## Define colors/energies per zone. Index 0 = surface, each subsequent entry
## corresponds to one zone_size deeper.  Values blend linearly between entries.
@export var zones: Array[ZoneData] = []

func _ready() -> void:
	player.surface_node = wader
	player.initialize_depth()
	if zones.is_empty():
		_build_default_zones()

func _build_default_zones() -> void:
	var z0 := ZoneData.new()
	z0.color = Color(0.0, 1.0, 1.0)
	z0.energy = 7.0
	z0.volumetric_energy = 10.0

	var z1 := ZoneData.new()
	z1.color = Color(0.0, 0.6, 0.5)
	z1.energy = 5.0
	z1.volumetric_energy = 8.0

	var z2 := ZoneData.new()
	z2.color = Color(0.0, 0.2, 0.5)
	z2.energy = 3.0
	z2.volumetric_energy = 6.0

	var z3 := ZoneData.new()
	z3.color = Color(0.05, 0.02, 0.15)
	z3.energy = 1.5
	z3.volumetric_energy = 4.0

	var z4 := ZoneData.new()
	z4.color = Color(0.08, 0.0, 0.04)
	z4.energy = 0.8
	z4.volumetric_energy = 2.0

	zones = [z0, z1, z2, z3, z4]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("spawn_debug_tank"):
		var tank := OxygenTankScene.instantiate()
		var angle := randf() * TAU
		var dist := randf_range(5.0, 20.0)
		var offset := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		tank.global_position = player.global_position + offset
		add_child(tank)

func _process(_delta: float) -> void:
	var dist_to_surface := wader.global_position.y - player.global_position.y
	var t := clampf((dist_to_surface - ior_dist_min) / (ior_dist_max - ior_dist_min), 0.0, 1.0)
	#water_mat.set_shader_parameter("index_of_refraction", lerpf(ior_close, ior_far, t))
	wader.position.x = player.position.x
	wader.position.z = player.position.z
	_update_zone()
	if player.position.y > 100:
		ground_mesh.visible = false
		

func _update_zone() -> void:
	if zones.size() < 2:
		return

	var depth := maxf(player.get_depth(), 0.0)
	var progress := depth / zone_size
	var idx := int(progress)
	var blend := progress - float(idx)

	idx = clampi(idx, 0, zones.size() - 1)
	var next_idx := mini(idx + 1, zones.size() - 1)
	if idx >= zones.size() - 1:
		blend = 0.0

	var cur: ZoneData = zones[idx]
	var nxt: ZoneData = zones[next_idx]

	var floor_t := clampf(blend * 2.0, 0.0, 1.0)
	var ceiling_t := clampf(blend * 2.0 - 1.0, 0.0, 1.0)

	ceiling_light.light_color = cur.color.lerp(nxt.color, ceiling_t)
	ceiling_light.light_energy = lerpf(cur.energy, nxt.energy, ceiling_t)
	ceiling_light.light_volumetric_fog_energy = lerpf(cur.volumetric_energy, nxt.volumetric_energy, ceiling_t)

	floor_light.light_color = cur.color.lerp(nxt.color, floor_t)
	floor_light.light_energy = lerpf(cur.energy, nxt.energy, floor_t)
	floor_light.light_volumetric_fog_energy = lerpf(cur.volumetric_energy, nxt.volumetric_energy, floor_t)
