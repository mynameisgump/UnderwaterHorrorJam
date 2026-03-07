extends Node3D

@onready var wader: Node3D = $Wader
@onready var player: PlayerController = $Player
@onready var water_mat: ShaderMaterial = $Wader/MeshInstance3D.get_surface_override_material(0) if $Wader/MeshInstance3D.get_surface_override_material(0) else $Wader/MeshInstance3D.mesh.material
@onready var ceiling_light: DirectionalLight3D = $CeilingLight
@onready var floor_light: DirectionalLight3D = $FloorLight

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
		print("Making")
		_build_default_zones()

func _build_default_zones() -> void:
	var z0 := ZoneData.new()
	z0.ceiling_light_color = Color(0.0, 1.0, 1.0)
	z0.ceiling_light_energy = 7.0
	z0.ceiling_volumetric_energy = 5.4
	z0.floor_light_color = Color(0.0, 1.0, 0.39)
	z0.floor_light_energy = 7.0
	z0.floor_volumetric_energy = 16.0

	var z1 := ZoneData.new()
	z1.ceiling_light_color = Color(0.0, 0.55, 0.75)
	z1.ceiling_light_energy = 5.0
	z1.ceiling_volumetric_energy = 4.0
	z1.floor_light_color = Color(0.0, 0.45, 0.3)
	z1.floor_light_energy = 5.0
	z1.floor_volumetric_energy = 12.0

	var z2 := ZoneData.new()
	z2.ceiling_light_color = Color(0.0, 0.25, 0.45)
	z2.ceiling_light_energy = 3.0
	z2.ceiling_volumetric_energy = 2.5
	z2.floor_light_color = Color(0.0, 0.2, 0.2)
	z2.floor_light_energy = 3.0
	z2.floor_volumetric_energy = 8.0

	var z3 := ZoneData.new()
	z3.ceiling_light_color = Color(0.02, 0.06, 0.18)
	z3.ceiling_light_energy = 1.5
	z3.ceiling_volumetric_energy = 1.2
	z3.floor_light_color = Color(0.06, 0.0, 0.12)
	z3.floor_light_energy = 2.0
	z3.floor_volumetric_energy = 5.0

	var z4 := ZoneData.new()
	z4.ceiling_light_color = Color(0.01, 0.01, 0.06)
	z4.ceiling_light_energy = 0.5
	z4.ceiling_volumetric_energy = 0.5
	z4.floor_light_color = Color(0.12, 0.0, 0.06)
	z4.floor_light_energy = 1.5
	z4.floor_volumetric_energy = 3.0

	zones = [z0, z1, z2, z3, z4]

func _process(_delta: float) -> void:
	var dist_to_surface := wader.global_position.y - player.global_position.y
	var t := clampf((dist_to_surface - ior_dist_min) / (ior_dist_max - ior_dist_min), 0.0, 1.0)
	water_mat.set_shader_parameter("index_of_refraction", lerpf(ior_close, ior_far, t))
	_update_zone()

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

	ceiling_light.light_color = cur.ceiling_light_color.lerp(nxt.ceiling_light_color, blend)
	ceiling_light.light_energy = lerpf(cur.ceiling_light_energy, nxt.ceiling_light_energy, blend)
	ceiling_light.light_volumetric_fog_energy = lerpf(cur.ceiling_volumetric_energy, nxt.ceiling_volumetric_energy, blend)

	floor_light.light_color = cur.floor_light_color.lerp(nxt.floor_light_color, blend)
	floor_light.light_energy = lerpf(cur.floor_light_energy, nxt.floor_light_energy, blend)
	floor_light.light_volumetric_fog_energy = lerpf(cur.floor_volumetric_energy, nxt.floor_volumetric_energy, blend)
