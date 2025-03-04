# enemy_spawner.gd
extends Node

@export var spawn_percentage = 10  # Percentage of empty cells to spawn enemies in
@export var minimum_enemies = 1    # Minimum number of enemies to spawn

var grid = null
var enemy_scene_path = "res://scenes/enemy.tscn"
var spawned_enemies = []

func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for enemy spawning!")
		return
	
	await get_tree().process_frame
	spawn_enemies()

func spawn_enemies():
	# Clear existing enemies
	for enemy in spawned_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	spawned_enemies.clear()
	
	if not ResourceLoader.exists(enemy_scene_path):
		push_error("ERROR: Enemy scene not found at: " + enemy_scene_path)
		return
	
	# Get empty cells
	var empty_cells = []
	for y in range(int(grid.grid_size.y)):
		for x in range(int(grid.grid_size.x)):
			if grid.is_boundary_cell(x, y):
				continue
			
			if grid.cell_contents[y][x] == grid.CellContent.EMPTY:
				empty_cells.append(Vector2(x, y))
	
	# Calculate number of enemies to spawn
	var num_enemies = max(minimum_enemies, int(ceil(empty_cells.size() * spawn_percentage / 100.0)))
	num_enemies = min(num_enemies, empty_cells.size())
	
	# Select random cells
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value + 12345
	
	var selected_cells = []
	while selected_cells.size() < num_enemies and empty_cells.size() > 0:
		var index = rng.randi() % empty_cells.size()
		selected_cells.append(empty_cells[index])
		empty_cells.remove_at(index)
	
	# Load enemy scene
	var enemy_resource = load(enemy_scene_path)
	if not enemy_resource:
		push_error("ERROR: Failed to load enemy scene!")
		return
	
	# Spawn enemies
	for cell_pos in selected_cells:
		var enemy = enemy_resource.instantiate()
		
		if not enemy:
			push_error("ERROR: Failed to instantiate enemy!")
			continue
		
		# Set position
		enemy.global_position = Vector2(
			cell_pos.x * grid.cell_size.x + grid.cell_size.x / 2,
			cell_pos.y * grid.cell_size.y + grid.cell_size.y / 2
		)
		
		# Setup state machine if needed
		_setup_enemy_state_machine(enemy)
		
		get_parent().add_child(enemy)
		spawned_enemies.append(enemy)
	
	initialize_enemy_visibility()

func _setup_enemy_state_machine(enemy):
	if not enemy.has_node("StateMachine"):
		# Create state machine
		var state_machine = Node.new()
		state_machine.name = "StateMachine"
		state_machine.set_script(load("res://scripts/core/state_machine.gd"))
		enemy.add_child(state_machine)
		
		# Create Idle state
		var idle_state = Node.new()
		idle_state.name = "Idle"
		idle_state.set_script(load("res://enemy_state_idle.gd"))
		state_machine.add_child(idle_state)
		
		# Create Follow state
		var follow_state = Node.new()
		follow_state.name = "Follow"
		follow_state.set_script(load("res://enemy_state_follow.gd"))
		state_machine.add_child(follow_state)

func initialize_enemy_visibility():
	if not grid:
		return
		
	for enemy in spawned_enemies:
		if is_instance_valid(enemy):
			var enemy_cell_x = int(floor(enemy.global_position.x / grid.cell_size.x))
			var enemy_cell_y = int(floor(enemy.global_position.y / grid.cell_size.y))
			
			var is_cell_loaded = grid.loaded_cells.has(Vector2(enemy_cell_x, enemy_cell_y))
			
			if enemy.has_method("update_active_state"):
				enemy.update_active_state(is_cell_loaded)
			else:
				enemy.visible = is_cell_loaded
				enemy.process_mode = Node.PROCESS_MODE_INHERIT if is_cell_loaded else Node.PROCESS_MODE_DISABLED

func reset_enemies():
	call_deferred("spawn_enemies")
