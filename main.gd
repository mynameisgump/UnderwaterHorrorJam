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
## Minimum separation between mines at the deepest point.
@export var mine_sep_deep: float = 20.0
## Minimum separation between mines near the surface (maze-like).
@export var mine_sep_surface: float = 13.0
## Exponent that biases mine Y placement toward the surface.
## 1.0 = uniform; lower values cluster more mines near the surface.
@export var mine_density_bias: float = 0.2
## Radius around the player within which real Area3D mine nodes are active.
## Mines outside this radius are rendered cheaply via MultiMesh.
@export var cull_radius: float = 50.0

@export_group("Chunk Streaming")
## Horizontal size of each procedural chunk (metres).
@export var chunk_size: float = 60.0
## Distance from the player (XZ) within which chunks stay loaded.
@export var load_radius: float = 100.0
## Target number of mines per chunk column.
@export var mines_per_chunk: int = 300
## Maximum chunks to generate per frame to limit hitches.
@export var chunks_per_frame: int = 2

@export_group("Oxygen Tanks")
## Target oxygen tanks per chunk column.
@export var tanks_per_chunk: int = 2
## Minimum distance a tank must keep from any mine or other tank.
@export var tank_min_clearance: float = 18.0

@export_group("Zones")
@export var zone_size: float = 100.0
## Define colors/energies per zone. Index 0 = surface, each subsequent entry
## corresponds to one zone_size deeper.  Values blend linearly between entries.
@export var zones: Array[ZoneData] = []

# ── MultiMesh (inactive mine rendering) ──────────────────────────────────────
# Inactive mines outside cull_radius are stored as MultiMesh instances —
# a single draw call — instead of individual scene nodes.
# Only mines inside cull_radius are real Area3D nodes with collision + process.

const _MM_GROW_STEP: int = 2000

var _mm_node: MultiMeshInstance3D
var _mm: MultiMesh

# Compact array: slot index -> gen_cell of the mine using that slot.
# Slots 0.._mm_used_count-1 are all live (visible) mine entries.
var _mm_data: Array[Vector3i] = []
var _mm_used_count: int = 0

# ── Mine records ──────────────────────────────────────────────────────────────
# Key:   Vector3i gen_cell
# Value: { pos: Vector3, bob_phase: float, mm_index: int, chunk_key: Vector2i }
#   mm_index >= 0  → mine is a passive MultiMesh instance at that slot
#   mm_index == -1 → mine is an active Area3D node (see _active_mines)
var _mine_data: Dictionary = {}

# Key: Vector3i cull_cell  →  Array[Vector3i] of gen_cells in that cell
var _cull_grid: Dictionary = {}

# Key: Vector2i chunk_key  →  Array[Vector3i] of gen_cells in that chunk
var _loaded_chunks: Dictionary = {}

# Active mine nodes (inside cull_radius)
var _active_mines: Dictionary = {}   # Vector3i gen_cell -> Mine
var _node_to_gencell: Dictionary = {}  # Mine -> Vector3i gen_cell (reverse lookup)

# Conflict-detection grid (unchanged from original)
var _mine_grid: Dictionary = {}  # Vector3i gen_cell -> Vector3 position
var _gen_cell_size: float

var _cull_tick: int = 0
var _stream_tick: int = 0
var _surfaced: bool = false
var _surface_y: float
var _bottom_y: float
var _world_seed: int

func _ready() -> void:
	player.surface_node = wader
	if zones.is_empty():
		_build_default_zones()
	_gen_cell_size = mine_sep_surface
	_surface_y = wader.global_position.y
	_bottom_y = _surface_y - field_depth
	_world_seed = randi()
	_setup_multimesh()
	_place_player_at_depth()
	_stream_chunks(9999)

func _place_player_at_depth() -> void:
	player.global_position = Vector3(0.0, _bottom_y, 0.0)

# ── MultiMesh setup ───────────────────────────────────────────────────────────

func _setup_multimesh() -> void:
	_mm_node = MultiMeshInstance3D.new()
	add_child(_mm_node)

	_mm = MultiMesh.new()
	_mm.transform_format = MultiMesh.TRANSFORM_3D

	# Pre-allocate enough capacity for all mines that can be loaded at once.
	var chunk_radius := int(ceil(load_radius / chunk_size)) + 1
	var max_chunks := (2 * chunk_radius + 1) * (2 * chunk_radius + 1)
	var initial_capacity := max_chunks * mines_per_chunk + _MM_GROW_STEP
	_mm.instance_count = initial_capacity
	_mm.visible_instance_count = 0
	_mm_data.resize(initial_capacity)

	# Sphere mesh matching the mine visual, rendered in one draw call.
	var sphere := SphereMesh.new()
	sphere.radius = 5.0
	sphere.height = 10.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.1, 0.1, 0.16, 1.0)
	mat.metallic = 1.0
	mat.metallic_specular = 0.0
	mat.emission_enabled = true
	mat.emission = Color(0.44705653, 0.22138682, 0.14737937, 1.0)
	mat.emission_energy_multiplier = 0.35
	sphere.material = mat
	_mm.mesh = sphere

	_mm_node.multimesh = _mm

# Allocate a MultiMesh slot for a mine and return its index.
func _mm_alloc(gen_cell: Vector3i, pos: Vector3) -> int:
	var idx := _mm_used_count

	if idx >= _mm.instance_count:
		var new_cap := _mm.instance_count + _MM_GROW_STEP
		_mm.instance_count = new_cap
		_mm_data.resize(new_cap)

	_mm.set_instance_transform(idx, Transform3D(Basis.IDENTITY, pos))
	_mm_data[idx] = gen_cell
	_mm_used_count += 1
	_mm.visible_instance_count = _mm_used_count
	return idx

# Release a MultiMesh slot using a swap-with-last strategy to keep the
# visible range compact and avoid any gaps.
func _mm_release(idx: int) -> void:
	if idx < 0 or idx >= _mm_used_count:
		return

	_mm_used_count -= 1

	if idx != _mm_used_count:
		# Overwrite the released slot with the last live entry.
		var last_cell: Vector3i = _mm_data[_mm_used_count]
		_mm_data[idx] = last_cell
		if _mine_data.has(last_cell):
			var last_pos: Vector3 = _mine_data[last_cell].pos
			_mm.set_instance_transform(idx, Transform3D(Basis.IDENTITY, last_pos))
			_mine_data[last_cell].mm_index = idx

	_mm.visible_instance_count = _mm_used_count

# ── Depth helpers ─────────────────────────────────────────────────────────────

func _height_t(y: float) -> float:
	return clampf((y - _bottom_y) / (_surface_y - _bottom_y), 0.0, 1.0)

func _separation_at_y(y: float) -> float:
	return lerpf(mine_sep_deep, mine_sep_surface, _height_t(y))

# ── Generation grid (small cells, size = mine_sep_surface) ───────────────────

func _gen_cell(pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(pos.x / _gen_cell_size)),
		int(floor(pos.y / _gen_cell_size)),
		int(floor(pos.z / _gen_cell_size))
	)

func _mine_grid_has_conflict(pos: Vector3, sep: float) -> bool:
	var origin := _gen_cell(pos)
	var r := int(ceil(sep / _gen_cell_size))
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var key := Vector3i(origin.x + dx, origin.y + dy, origin.z + dz)
				if _mine_grid.has(key):
					var other_pos: Vector3 = _mine_grid[key]
					var required := maxf(sep, _separation_at_y(other_pos.y))
					if pos.distance_squared_to(other_pos) < required * required:
						return true
	return false

func _mine_grid_has_conflict_radius(pos: Vector3, radius: float) -> bool:
	var origin := _gen_cell(pos)
	var r := int(ceil(radius / _gen_cell_size)) + 1
	var radius_sq := radius * radius
	for dx in range(-r, r + 1):
		for dy in range(-r, r + 1):
			for dz in range(-r, r + 1):
				var key := Vector3i(origin.x + dx, origin.y + dy, origin.z + dz)
				if _mine_grid.has(key):
					if pos.distance_squared_to(_mine_grid[key]) < radius_sq:
						return true
	return false

# ── Cull grid (large cells, size = cull_radius) ──────────────────────────────

func _cull_cell(pos: Vector3) -> Vector3i:
	return Vector3i(
		int(floor(pos.x / cull_radius)),
		int(floor(pos.y / cull_radius)),
		int(floor(pos.z / cull_radius))
	)

func _register_mine_cull(gen_cell: Vector3i, pos: Vector3) -> void:
	var cell := _cull_cell(pos)
	if not _cull_grid.has(cell):
		_cull_grid[cell] = []
	_cull_grid[cell].append(gen_cell)

# ── Chunk streaming ───────────────────────────────────────────────────────────

func _stream_chunks(max_gen: int = chunks_per_frame) -> void:
	var player_pos := player.global_position
	var px := int(floor(player_pos.x / chunk_size))
	var pz := int(floor(player_pos.z / chunk_size))
	var r := int(ceil(load_radius / chunk_size))
	var load_sq := load_radius * load_radius

	var desired: Dictionary = {}
	for cx in range(px - r, px + r + 1):
		for cz in range(pz - r, pz + r + 1):
			var center_x := (cx + 0.5) * chunk_size
			var center_z := (cz + 0.5) * chunk_size
			var dx := center_x - player_pos.x
			var dz := center_z - player_pos.z
			if dx * dx + dz * dz <= load_sq:
				desired[Vector2i(cx, cz)] = true

	var to_unload: Array[Vector2i] = []
	for key: Vector2i in _loaded_chunks:
		if not desired.has(key):
			to_unload.append(key)
	for key in to_unload:
		_unload_chunk(key)

	var generated := 0
	for key: Vector2i in desired:
		if generated >= max_gen:
			break
		if not _loaded_chunks.has(key):
			_generate_chunk(key.x, key.y)
			generated += 1

func _generate_chunk(cx: int, cz: int) -> void:
	var key := Vector2i(cx, cz)
	if _loaded_chunks.has(key):
		return

	var chunk_gen_cells: Array[Vector3i] = []
	_loaded_chunks[key] = chunk_gen_cells

	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(cx, cz)) ^ _world_seed

	var x_min := cx * chunk_size
	var z_min := cz * chunk_size

	var attempts := mines_per_chunk * 5
	var placed := 0
	for _i in attempts:
		if placed >= mines_per_chunk:
			break
		var y := lerpf(_bottom_y + 10.0, _surface_y - 10.0, pow(rng.randf(), mine_density_bias))
		var x := rng.randf_range(x_min, x_min + chunk_size)
		var z := rng.randf_range(z_min, z_min + chunk_size)
		var candidate := Vector3(x, y, z)
		var local_sep := _separation_at_y(y)
		if _mine_grid_has_conflict(candidate, local_sep):
			continue

		var gen_cell := _gen_cell(candidate)
		var bob_phase := rng.randf() * TAU
		_mine_grid[gen_cell] = candidate
		var mm_idx := _mm_alloc(gen_cell, candidate)
		_mine_data[gen_cell] = {
			"pos": candidate,
			"bob_phase": bob_phase,
			"mm_index": mm_idx,
			"chunk_key": key,
		}
		_register_mine_cull(gen_cell, candidate)
		chunk_gen_cells.append(gen_cell)
		placed += 1

func _unload_chunk(key: Vector2i) -> void:
	if not _loaded_chunks.has(key):
		return
	var gen_cells: Array = _loaded_chunks[key]
	for gen_cell: Vector3i in gen_cells:
		_remove_mine(gen_cell)
	_loaded_chunks.erase(key)

# Fully remove a mine — whether it's a passive MultiMesh entry or an active node.
func _remove_mine(gen_cell: Vector3i) -> void:
	if not _mine_data.has(gen_cell):
		return
	var record: Dictionary = _mine_data[gen_cell]

	if _active_mines.has(gen_cell):
		var mine: Mine = _active_mines[gen_cell]
		_active_mines.erase(gen_cell)
		# Erase reverse lookup before queue_free so _on_mine_exiting early-returns.
		_node_to_gencell.erase(mine)
		if is_instance_valid(mine):
			mine.queue_free()
	else:
		_mm_release(record.mm_index)

	var cull_key := _cull_cell(record.pos)
	if _cull_grid.has(cull_key):
		_cull_grid[cull_key].erase(gen_cell)
		if _cull_grid[cull_key].is_empty():
			_cull_grid.erase(cull_key)

	_mine_grid.erase(gen_cell)
	_mine_data.erase(gen_cell)

# ── Activation / deactivation ─────────────────────────────────────────────────

# Swap a MultiMesh entry for a real Area3D node when it enters cull range.
func _activate_mine(gen_cell: Vector3i) -> void:
	if not _mine_data.has(gen_cell) or _active_mines.has(gen_cell):
		return

	var record: Dictionary = _mine_data[gen_cell]

	# Remove from MultiMesh; its slot is released back into the compact array.
	_mm_release(record.mm_index)
	record.mm_index = -1

	var mine: Mine = MineScene.instantiate()
	mine.position = record.pos
	mine.set_active(false)
	add_child(mine)
	# Override the random bob phase from _ready() with our seeded value so mines
	# that re-enter the cull radius don't visibly "reset" their bob cycle.
	mine._bob_time = record.bob_phase
	mine.set_active(true)

	_active_mines[gen_cell] = mine
	_node_to_gencell[mine] = gen_cell
	mine.tree_exiting.connect(_on_mine_exiting.bind(mine))

# Swap a real node back to a passive MultiMesh entry when it leaves cull range.
func _deactivate_mine(gen_cell: Vector3i) -> void:
	if not _active_mines.has(gen_cell):
		return

	var mine: Mine = _active_mines[gen_cell]
	var record: Dictionary = _mine_data[gen_cell]

	_active_mines.erase(gen_cell)
	# Erase reverse lookup before queue_free so _on_mine_exiting early-returns.
	_node_to_gencell.erase(mine)

	if is_instance_valid(mine):
		# Save current bob phase so the mine picks up visually where it left off
		# when it eventually re-enters the cull radius.
		record.bob_phase = mine._bob_time
		mine.queue_free()

	var mm_idx := _mm_alloc(gen_cell, record.pos)
	record.mm_index = mm_idx

# ── Culling ───────────────────────────────────────────────────────────────────

func _cull_mines() -> void:
	var player_pos := player.global_position
	var cull_sq := cull_radius * cull_radius

	# Deactivate mines that have drifted out of range.
	var to_deactivate: Array[Vector3i] = []
	for gen_cell: Vector3i in _active_mines:
		if not _mine_data.has(gen_cell):
			to_deactivate.append(gen_cell)
			continue
		if (_mine_data[gen_cell].pos as Vector3).distance_squared_to(player_pos) > cull_sq:
			to_deactivate.append(gen_cell)
	for gen_cell in to_deactivate:
		_deactivate_mine(gen_cell)

	# Activate mines in neighbouring cull cells that are now in range.
	var center := _cull_cell(player_pos)
	for dx in range(-1, 2):
		for dy in range(-1, 2):
			for dz in range(-1, 2):
				var cell_key := Vector3i(center.x + dx, center.y + dy, center.z + dz)
				if not _cull_grid.has(cell_key):
					continue
				for gen_cell: Vector3i in _cull_grid[cell_key]:
					if _active_mines.has(gen_cell) or not _mine_data.has(gen_cell):
						continue
					if (_mine_data[gen_cell].pos as Vector3).distance_squared_to(player_pos) <= cull_sq:
						_activate_mine(gen_cell)

# Called when a Mine node exits the tree (e.g. after exploding and queue_free-ing itself).
func _on_mine_exiting(mine: Mine) -> void:
	if not _node_to_gencell.has(mine):
		return

	var gen_cell: Vector3i = _node_to_gencell[mine]
	_active_mines.erase(gen_cell)
	_node_to_gencell.erase(mine)

	if not _mine_data.has(gen_cell):
		return
	var record: Dictionary = _mine_data[gen_cell]

	# Mine exploded: just tear it down entirely, no MultiMesh restore.
	var cull_key := _cull_cell(record.pos)
	if _cull_grid.has(cull_key):
		_cull_grid[cull_key].erase(gen_cell)
		if _cull_grid[cull_key].is_empty():
			_cull_grid.erase(cull_key)

	_mine_grid.erase(gen_cell)
	_mine_data.erase(gen_cell)

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

	_stream_tick = (_stream_tick + 1) % 12
	if _stream_tick == 0:
		_stream_chunks()

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
