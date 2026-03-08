extends Node3D

const OxygenTankScene: PackedScene = preload("res://oxygen_tank.tscn")
const MineScene: PackedScene = preload("res://mine.tscn")

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

@export_group("Minefield")
## Total depth of the minefield in metres. Player starts at the bottom.
@export var field_depth: float = 500.0
## Horizontal radius of the mine column.
@export var field_radius: float = 80.0
## Total number of mines to generate.
@export var mine_count: int = 600
## Minimum world-space distance between any two mine centres.
@export var mine_min_separation: float = 14.0
## Radius around the player within which mines are active (process + physics).
@export var cull_radius: float = 120.0

@export_group("Oxygen Tanks")
## Total number of oxygen tanks to scatter through the field.
@export var tank_count: int = 25
## Minimum distance a tank must keep from any mine or other tank.
@export var tank_min_clearance: float = 18.0

@export_group("Zones")
@export var zone_size: float = 100.0
## Define colors/energies per zone. Index 0 = surface, each subsequent entry
## corresponds to one zone_size deeper.  Values blend linearly between entries.
@export var zones: Array[ZoneData] = []

# Direct references to all mines — avoids group allocation each frame.
var _mine_refs: Array[Mine] = []
# Spatial hash for O(1) proximity checks during generation. Cell key = Vector3i.
var _mine_grid: Dictionary = {}
# Throttle cull pass to every 6 frames.
var _cull_tick: int = 0
var _surfaced: bool = false

func _ready() -> void:
	player.surface_node = wader
	if zones.is_empty():
		_build_default_zones()
	_place_player_at_depth()
	_generate_minefield()

func _place_player_at_depth() -> void:
	player.global_position = Vector3(0.0, wader.global_position.y - field_depth, 0.0)

# ── Minefield Generation ──────────────────────────────────────────────────────

func _cell(pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(pos.x / mine_min_separation)),
		int(floor(pos.y / mine_min_separation)),
		int(floor(pos.z / mine_min_separation))
	)

func _mine_grid_has_conflict(pos: Vector3) -> bool:
	var origin := _cell(pos)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				if _mine_grid.has(Vector3i(origin.x + dx, origin.y + dy, origin.z + dz)):
					return true
	return false

func _generate_minefield() -> void:
	var surface_y := wader.global_position.y
	var bottom_y := surface_y - field_depth
	var max_attempts := mine_count * 10

	# Scatter mines throughout the full water column.
	for _i in max_attempts:
		if _mine_refs.size() >= mine_count:
			break
		var angle := randf() * TAU
		var dist := randf_range(0.0, field_radius)
		var candidate := Vector3(
			cos(angle) * dist,
			randf_range(bottom_y + 10.0, surface_y - 10.0),
			sin(angle) * dist
		)
		if _mine_grid_has_conflict(candidate):
			continue
		_mine_grid[_cell(candidate)] = true
		_spawn_mine_at(candidate)

	# Scatter oxygen tanks, keeping clear of mines.
	var tank_grid: Dictionary = {}
	var tank_attempts := tank_count * 10
	var tanks_placed := 0
	for _i in tank_attempts:
		if tanks_placed >= tank_count:
			break
		var angle := randf() * TAU
		var dist := randf_range(0.0, field_radius)
		var candidate := Vector3(
			cos(angle) * dist,
			randf_range(bottom_y + 10.0, surface_y - 10.0),
			sin(angle) * dist
		)
		# Check against mines using the mine grid.
		if _mine_grid_has_conflict_radius(candidate, tank_min_clearance):
			continue
		# Check against other tanks.
		var tank_cell := Vector3i(
			int(floor(candidate.x / tank_min_clearance)),
			int(floor(candidate.y / tank_min_clearance)),
			int(floor(candidate.z / tank_min_clearance))
		)
		if _tank_grid_has_conflict(tank_grid, tank_cell):
			continue
		tank_grid[tank_cell] = true
		var tank := OxygenTankScene.instantiate()
		tank.position = candidate
		tank.add_to_group("oxygen_tanks")
		add_child(tank)
		tanks_placed += 1

func _mine_grid_has_conflict_radius(pos: Vector3, radius: float) -> bool:
	# Check mine grid using the mine_min_separation cell size.
	var mine_origin := _cell(pos)
	var r := int(ceil(radius / mine_min_separation)) + 1
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				if _mine_grid.has(Vector3i(mine_origin.x + dx, mine_origin.y + dy, mine_origin.z + dz)):
					return true
	return false

func _tank_grid_has_conflict(grid: Dictionary, cell: Vector3i) -> bool:
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				if grid.has(Vector3i(cell.x + dx, cell.y + dy, cell.z + dz)):
					return true
	return false

func _spawn_mine_at(pos: Vector3) -> void:
	var mine: Mine = MineScene.instantiate()
	mine.position = pos
	mine.set_active(false)
	add_child(mine)
	_mine_refs.append(mine)
	mine.tree_exiting.connect(_on_mine_exiting.bind(mine))

func _on_mine_exiting(mine: Mine) -> void:
	_mine_refs.erase(mine)
	_mine_grid.erase(_cell(mine.position))

# ── Culling ───────────────────────────────────────────────────────────────────

func _cull_mines() -> void:
	var player_pos := player.global_position
	var cull_sq := cull_radius * cull_radius
	for mine in _mine_refs:
		if is_instance_valid(mine):
			mine.set_active(mine.global_position.distance_squared_to(player_pos) <= cull_sq)

# ── Debug input ───────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("spawn_debug_tank"):
		var tank := OxygenTankScene.instantiate()
		var angle := randf() * TAU
		var dist := randf_range(5.0, 20.0)
		var offset := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		tank.global_position = player.global_position + offset
		add_child(tank)

# ── Per-frame ─────────────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	wader.position.x = player.position.x
	wader.position.z = player.position.z
	_update_zone()
	if player.position.y > 100:
		ground_mesh.visible = false

	_cull_tick = (_cull_tick + 1) % 6
	if _cull_tick == 0:
		_cull_mines()

	_check_surfaced()

func _check_surfaced() -> void:
	if _surfaced:
		return
	if player.global_position.y >= wader.global_position.y - 5.0:
		_surfaced = true
		_on_player_surfaced()

func _on_player_surfaced() -> void:
	print("YOU SURFACED — YOU WIN")

# ── Zone lighting ─────────────────────────────────────────────────────────────

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
