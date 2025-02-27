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
		print("ERROR: Grid node not found!")
	
	# Initialize key states
	for i in range(10):
		previous_key_states[KEY_0 + i] = false

# Coordinate the world initialization sequence
func initialize_world():
	print("=== Starting coordinated world initialization ===")
	
	# Ensure grid is initialized
	if grid:
		print("Step 1: Ensuring grid is initialized")
		grid.regenerate()
		await get_tree().process_frame
	else:
		print("ERROR: Grid not found during initialization!")
		return
	
	# Generate planets
	if planet_spawner:
		print("Step 2: Initializing planets")
		planet_spawner.generate_planets()
		await get_tree().process_frame
	else:
		print("ERROR: Planet spawner not found during initialization!")
		return
	
	# Generate asteroids
	if asteroid_spawner:
		print("Step 3: Initializing asteroids")
		asteroid_spawner.generate_asteroids()
		await get_tree().process_frame
	else:
		print("ERROR: Asteroid spawner not found during initialization!")
		return
	
	# Create or place player
	print("Step 4: Creating or placing player")
	create_player()
	await get_tree().process_frame
	
	# Spawn enemies
	if enemy_spawner:
		print("Step 5: Spawning enemies")
		enemy_spawner.spawn_enemies()
	else:
		print("WARNING: Enemy spawner not found during initialization!")
	
	print("=== World initialization complete ===")

func _process(delta):
	# Handle seed changing via numeric keys
	handle_seed_key_input()
	
	# Handle random seed generation via Shift key
	handle_random_seed_input()
	
	# Manage message display timer
	manage_message_timer(delta)

# Handle numeric key seed inputs
func handle_seed_key_input():
	for i in range(10): # 0-9
		var key_code = KEY_0 + i
		var key_pressed = Input.is_physical_key_pressed(key_code)
		
		# Check if key was just pressed
		if key_pressed and not previous_key_states[key_code]:
			if grid:
				print("Setting seed to: ", i)
				grid.set_seed(i)
				update_seed_label()
				create_player()
				if enemy_spawner:
					enemy_spawner.reset_enemies()
		
		# Update previous key state
		previous_key_states[key_code] = key_pressed

# Handle random seed generation
# Handle random seed generation
func handle_random_seed_input():
	if Input.is_action_just_pressed("ui_accept"):  # Changed to Enter key
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
		print(text)  # Also output to console

# Hide current message
func hide_message():
	if message_label:
		message_label.visible = false
		message_timer = 0.0

# Respawn player at initial planet
func respawn_player_at_initial_planet():
	if player and initial_planet_position:
		print("Respawning player at initial planet: ", initial_planet_position)
		
		# Reset player state completely
		if player.has_method("set_immobilized"):
			player.set_immobilized(false)
			player.movement_speed = 300
			player.is_immobilized = false
			player.respawn_timer = 0.0
			player.was_in_boundary_cell = false
			player.was_outside_grid = false
		
		# Reset player position
		player.global_position = initial_planet_position
		player.last_valid_position = initial_planet_position
		
		# Update grid chunks
		grid.current_player_cell_x = initial_planet_cell_x
		grid.current_player_cell_y = initial_planet_cell_y
		grid.update_loaded_chunks(initial_planet_cell_x, initial_planet_cell_y)
		grid.queue_redraw()
		
		# Reset grid state
		grid.player_immobilized = false
		grid.was_outside_grid = false
		grid.was_in_boundary_cell = false
		grid.respawn_timer = 0.0
		
		# Get and display planet name
		var planet_name = planet_spawner.get_planet_name(initial_planet_cell_x, initial_planet_cell_y)
		show_message("You have been rescued and returned to planet " + planet_name + ".")
	else:
		print("ERROR: Cannot respawn player - missing initial planet position!")
		place_player_at_random_planet()

# Place player at a random planet
func place_player_at_random_planet():
	# Verify player exists
	if player == null:
		print("ERROR: Player is null!")
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
		grid.current_player_cell_x = cell_x
		grid.current_player_cell_y = cell_y
		grid.update_loaded_chunks(cell_x, cell_y)
		
		# Get and display planet name
		var planet_name = planet_spawner.get_planet_name(chosen_planet.grid_x, chosen_planet.grid_y)
		show_message("Welcome to planet " + planet_name + "!")
		
		print("Player placed at planet " + planet_name + " position: ", chosen_planet.position)
		print("Starting cell: (", cell_x, ",", cell_y, ")")
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
		grid.current_player_cell_x = cell_x
		grid.current_player_cell_y = cell_y
		grid.update_loaded_chunks(cell_x, cell_y)
		
		print("WARNING: No planets found. Player placed at grid center: ", center)
		print("Starting cell: (", cell_x, ",", cell_y, ")")

# Create or update player
func create_player():
	# Use existing player or create new one
	if has_node("Player"):
		player = get_node("Player")
		print("Using existing player instance")
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
	
	print("Player created at initial position: ", player.global_position)
	
	# Place player
	call_deferred("place_player_at_random_planet")

# Get planet positions
func get_planet_positions():
	if planet_spawner:
		return planet_spawner.get_all_planet_positions()
	else:
		print("ERROR: Planet spawner not found!")
		return []
