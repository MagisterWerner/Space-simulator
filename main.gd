extends Node2D

# Node references
@onready var grid = $Grid
@onready var seed_label = $CanvasLayer/SeedLabel
@onready var message_label = $CanvasLayer/MessageLabel
@onready var enemy_spawner = $EnemySpawner
@onready var planet_spawner = $PlanetSpawner
@onready var asteroid_spawner = $AsteroidSpawner

# Message display constants
const MESSAGE_DURATION = 3.0
var message_timer = 0.0

# Planet and player tracking
var initial_planet_position = null
var initial_planet_cell_x = -1
var initial_planet_cell_y = -1
var player = null

# Key state tracking
var previous_key_states = {}

func _ready():
	# Initialize the grid
	if grid:
		# Update the seed display
		update_seed_label()
		
		# Initialize world in a coordinated sequence
		call_deferred("initialize_world")
	else:
		push_error("ERROR: Grid node not found!")
	
	# Initialize key states
	for i in range(10):
		previous_key_states[KEY_0 + i] = false

# Coordinate the world initialization sequence
func initialize_world():
	# Ensure grid is initialized
	if grid:
		grid.regenerate()
		await get_tree().process_frame
	else:
		push_error("ERROR: Grid not found during initialization!")
		return
	
	# Generate planets
	if planet_spawner:
		planet_spawner.generate_planets()
		await get_tree().process_frame
	else:
		push_error("ERROR: Planet spawner not found during initialization!")
		return
	
	# Generate asteroids
	if asteroid_spawner:
		asteroid_spawner.generate_asteroids()
		await get_tree().process_frame
	else:
		push_error("ERROR: Asteroid spawner not found during initialization!")
		return
	
	# Create or place player
	create_player()
	await get_tree().process_frame
	await get_tree().process_frame  # Add an extra frame to ensure player is fully initialized
	
	# Spawn enemies
	if enemy_spawner:
		enemy_spawner.spawn_enemies()
		await get_tree().process_frame
	
	# Force a grid update to ensure everything is loaded
	if player and grid:
		force_grid_update()

func _process(delta):
	# Handle seed changing via numeric keys
	handle_seed_key_input()
	
	# Handle random seed generation via Enter key
	handle_random_seed_input()
	
	# Manage message display timer
	manage_message_timer(delta)
	
	# Force redraw to ensure planets and asteroids are visible
	queue_redraw()

func _draw():
	# We need this empty _draw function to make sure all renderers get called
	pass

# Handle numeric key seed inputs
func handle_seed_key_input():
	for i in range(10): # 0-9
		var key_code = KEY_0 + i
		var key_pressed = Input.is_physical_key_pressed(key_code)
		
		# Check if key was just pressed
		if key_pressed and not previous_key_states[key_code]:
			if grid:
				grid.set_seed(i)
				update_seed_label()
				create_player()
				if enemy_spawner:
					enemy_spawner.reset_enemies()
		
		# Update previous key state
		previous_key_states[key_code] = key_pressed

# Handle random seed generation
func handle_random_seed_input():
	if Input.is_action_just_pressed("ui_accept"):  # Enter key
		# Generate a new random seed
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		var new_seed = rng.randi_range(1, 9999)
		
		# Update the grid with the new seed
		if grid:
			grid.set_seed(new_seed)
			update_seed_label()
			
			# Update player position
			create_player()
			
			# Reset enemies
			if enemy_spawner:
				enemy_spawner.reset_enemies()
			
			# Show message about seed change
			show_message("Generated new random seed: " + str(new_seed))

# Manage message display timer
func manage_message_timer(delta):
	if message_timer > 0:
		message_timer -= delta
		if message_timer <= 0:
			hide_message()

# Update seed label display
func update_seed_label():
	seed_label.text = "Current Seed: " + str(grid.seed_value)

# Show a temporary message
func show_message(text):
	if message_label:
		message_label.text = text
		message_label.visible = true
		message_timer = MESSAGE_DURATION

# Hide current message
func hide_message():
	if message_label:
		message_label.visible = false
		message_timer = 0.0

# Respawn player at initial planet
func respawn_player_at_initial_planet():
	if player and initial_planet_position:
		# Properly reset player state through its methods
		if player.has_method("set_immobilized"):
			player.set_immobilized(false)
			
			# Make sure movement component exists before trying to access it
			if player.has_node("MovementComponent") and player.get_node("MovementComponent").has_method("set_speed"):
				player.get_node("MovementComponent").set_speed(300)
			elif player.has_node("MovementComponent"):
				player.get_node("MovementComponent").speed = 300
		
		# Reset position and other player properties that exist on Player class
		player.global_position = initial_planet_position
		player.last_valid_position = initial_planet_position
		
		# Reset all player state variables that might be used in Player class
		if "is_immobilized" in player:
			player.is_immobilized = false
		if "respawn_timer" in player:
			player.respawn_timer = 0.0  
		if "was_in_boundary_cell" in player:
			player.was_in_boundary_cell = false
		if "was_outside_grid" in player:
			player.was_outside_grid = false
		
		# Force grid to completely reset loaded chunks
		grid.current_player_cell_x = -999
		grid.current_player_cell_y = -999
		grid.update_loaded_chunks(initial_planet_cell_x, initial_planet_cell_y)
		grid.queue_redraw()
		
		# Reset grid state
		grid.player_immobilized = false
		grid.was_outside_grid = false
		grid.was_in_boundary_cell = false
		grid.respawn_timer = 0.0
		
		# Force all game elements to update
		if planet_spawner:
			planet_spawner.draw_planets(grid, grid.loaded_cells)
		if asteroid_spawner:
			asteroid_spawner.draw_asteroids(grid, grid.loaded_cells)
		if enemy_spawner:
			enemy_spawner.initialize_enemy_visibility()
		
		# Get and display planet name
		var planet_name = planet_spawner.get_planet_name(initial_planet_cell_x, initial_planet_cell_y)
		show_message("You have been rescued and returned to planet " + planet_name + ".")
		
		# Force another grid update after a brief delay for good measure
		call_deferred("force_grid_update")
	else:
		push_error("ERROR: Cannot respawn player - missing initial planet position!")
		place_player_at_random_planet()

# Place player at a random planet
func place_player_at_random_planet():
	# Verify player exists
	if player == null:
		push_error("ERROR: Player is null!")
		return
	
	# Force grid re-render
	grid.queue_redraw()
	
	# Get planet positions
	var planet_positions = planet_spawner.get_all_planet_positions()
	
	if planet_positions.size() > 0:
		# Choose a random planet using grid seed
		var rng = RandomNumberGenerator.new()
		rng.seed = grid.seed_value
		var random_index = rng.randi() % planet_positions.size()
		
		var chosen_planet = planet_positions[random_index]
		
		# Set player position
		player.global_position = chosen_planet.position
		
		# Store initial spawn position
		initial_planet_position = chosen_planet.position
		initial_planet_cell_x = chosen_planet.grid_x
		initial_planet_cell_y = chosen_planet.grid_y
		
		# Initialize loaded chunks
		var cell_x = int(floor(player.global_position.x / grid.cell_size.x))
		var cell_y = int(floor(player.global_position.y / grid.cell_size.y))
		
		# Force grid to update with this cell as center
		grid.current_player_cell_x = -1  # Force update by setting to different value
		grid.current_player_cell_y = -1
		grid.update_loaded_chunks(cell_x, cell_y)
		
		# Get and display planet name
		var planet_name = planet_spawner.get_planet_name(chosen_planet.grid_x, chosen_planet.grid_y)
		show_message("Welcome to planet " + planet_name + "!")
		
		# Force another update after a brief delay
		await get_tree().create_timer(0.1).timeout
		force_grid_update()
	else:
		# Fallback to grid center
		var center = Vector2(
			grid.grid_size.x * grid.cell_size.x / 2,
			grid.grid_size.y * grid.cell_size.y / 2
		)
		player.global_position = center
		
		# Store initial spawn position
		initial_planet_position = center
		initial_planet_cell_x = int(floor(center.x / grid.cell_size.x))
		initial_planet_cell_y = int(floor(center.y / grid.cell_size.y))
		
		# Initialize loaded chunks
		var cell_x = int(floor(center.x / grid.cell_size.x))
		var cell_y = int(floor(center.y / grid.cell_size.y))
		
		# Force grid to update with this cell as center
		grid.current_player_cell_x = -1  # Force update by setting to different value
		grid.current_player_cell_y = -1
		grid.update_loaded_chunks(cell_x, cell_y)
		
		# Force another update after a brief delay
		await get_tree().create_timer(0.1).timeout
		force_grid_update()

# Create or update player
func create_player():
	# Use existing player or create new one
	if has_node("Player"):
		player = get_node("Player")
		call_deferred("place_player_at_random_planet")
		return
	
	# Create new player instance
	call_deferred("_deferred_create_player")

# Deferred player creation
func _deferred_create_player():
	var player_scene = load("res://player.tscn")
	player = player_scene.instantiate()
	
	# Assign script if needed
	if !player.get_script():
		var player_script = load("res://player.gd")
		player.set_script(player_script)
	
	# Add to scene and position
	add_child(player)
	player.global_position = Vector2(100, 100)
	player.name = "Player"
	
	# Place player
	call_deferred("place_player_at_random_planet")

# Get planet positions
func get_planet_positions():
	if planet_spawner:
		return planet_spawner.get_all_planet_positions()
	else:
		push_error("ERROR: Planet spawner not found!")
		return []
	
# Force a grid update
func force_grid_update():
	if player and grid:
		# Calculate player cell position
		var cell_x = int(floor(player.global_position.x / grid.cell_size.x))
		var cell_y = int(floor(player.global_position.y / grid.cell_size.y))
	 
		# Force update of loaded chunks
		grid.current_player_cell_x = -1  # Force update by setting to different value
		grid.current_player_cell_y = -1
		grid.update_loaded_chunks(cell_x, cell_y)
		 
		# Force a redraw
		grid.queue_redraw()
