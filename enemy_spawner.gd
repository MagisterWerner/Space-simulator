extends Node

@export var spawn_percentage = 10  # Percentage of empty cells to spawn enemies in
@export var minimum_enemies = 1    # Minimum number of enemies to spawn

# Reference to the grid
var grid = null

# Reference to the enemy scene
var enemy_scene = preload("res://enemy.tscn")

# Array to track spawned enemies
var spawned_enemies = []

# Called when the node enters the scene tree for the first time
func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for enemy spawning!")
		return
	
	# Wait for a frame to ensure grid is fully initialized
	await get_tree().process_frame
	
	# Spawn enemies in empty cells
	spawn_enemies()
	
	print("Enemy spawner initialized - Total enemies: ", spawned_enemies.size())

# Function to spawn enemies in empty cells
func spawn_enemies():
	# Clear any existing enemies
	for enemy in spawned_enemies:
		if is_instance_valid(enemy):
			enemy.queue_free()
	spawned_enemies.clear()
	
	# Get all empty cells (not boundary, not containing planets or asteroids)
	var empty_cells = []
	for y in range(int(grid.grid_size.y)):
		for x in range(int(grid.grid_size.x)):
			# Skip boundary cells
			if grid.is_boundary_cell(x, y):
				continue
			
			# Check if the cell is empty
			if grid.cell_contents[y][x] == grid.CellContent.EMPTY:
				empty_cells.append(Vector2(x, y))
	
	# Determine how many enemies to spawn based on percentage with a minimum
	var num_enemies = max(minimum_enemies, int(ceil(empty_cells.size() * spawn_percentage / 100.0)))
	num_enemies = min(num_enemies, empty_cells.size())  # Cap at available cells
	
	print("Found ", empty_cells.size(), " empty cells - Spawning ", num_enemies, " enemies")
	
	# Choose random cells for enemies
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value + 12345  # Use grid seed but with offset for enemy spawning
	
	var selected_cells = []
	while selected_cells.size() < num_enemies and empty_cells.size() > 0:
		var index = rng.randi() % empty_cells.size()
		selected_cells.append(empty_cells[index])
		empty_cells.remove_at(index)
	
	# Spawn enemies at the selected cells
	for cell_pos in selected_cells:
		var enemy = enemy_scene.instantiate()
		
		# Set position centered in the cell
		enemy.global_position = Vector2(
			cell_pos.x * grid.cell_size.x + grid.cell_size.x / 2,
			cell_pos.y * grid.cell_size.y + grid.cell_size.y / 2
		)
		
		# Add enemy to the scene
		get_parent().add_child(enemy)
		spawned_enemies.append(enemy)
		
		print("Spawned enemy at cell: (", cell_pos.x, ",", cell_pos.y, ")")
	
	# Initialize enemy visibility based on loaded chunks
	initialize_enemy_visibility()

# Called after enemies are spawned to set initial visibility
func initialize_enemy_visibility():
	# No need to get grid again since we already have it as a class variable
	if not grid:
		return
		
	# Update visibility for each enemy based on whether its cell is loaded
	for enemy in spawned_enemies:
		if is_instance_valid(enemy):
			var enemy_cell_x = int(floor(enemy.global_position.x / grid.cell_size.x))
			var enemy_cell_y = int(floor(enemy.global_position.y / grid.cell_size.y))
			
			# Check if the enemy's cell is currently loaded
			var is_cell_loaded = grid.loaded_cells.has(Vector2(enemy_cell_x, enemy_cell_y))
			
			# Set the enemy's active state
			enemy.update_active_state(is_cell_loaded)

# Reset and respawn enemies (useful for when grid seed changes)
func reset_enemies():
	call_deferred("spawn_enemies")
