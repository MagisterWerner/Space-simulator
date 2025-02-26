extends Node2D

@onready var grid = $Grid
@onready var seed_label = $CanvasLayer/SeedLabel
@onready var message_label = $CanvasLayer/MessageLabel
<<<<<<< HEAD

# References to spawners
@onready var planet_spawner = $PlanetSpawner
@onready var asteroid_spawner = $AsteroidSpawner
@onready var enemy_spawner = $EnemySpawner
=======
>>>>>>> parent of 3cca589 (Huge enemy update)

# Use a direct node reference instead of preloading
var player = null

# Message display duration in seconds
const MESSAGE_DURATION = 3.0
var message_timer = 0.0

# Store initial planet position for respawning
var initial_planet_position = null
var initial_planet_cell_x = 0
var initial_planet_cell_y = 0

# Debug mode toggle
var debug_mode = false

func _ready():
	# Initialize seed label
	update_seed_label()
	
	# Initialize message label and show welcome message
	if message_label:
		message_label.visible = true
		message_label.text = "Welcome to the galaxy!"
		message_timer = MESSAGE_DURATION
	
	# Connect to grid signals
	if grid:
		grid.cell_contents_changed.connect(_on_grid_cell_contents_changed)
		grid.chunks_updated.connect(_on_grid_chunks_updated)
	
	# Connect to planet spawner signals
	if planet_spawner:
		planet_spawner.planet_spawned.connect(_on_planet_spawned)
	
	# Print important information about system state
	print("Grid size: ", grid.grid_size if grid else "NULL")
	print("Cell size: ", grid.cell_size if grid else "NULL")
	print("Current seed: ", grid.seed_value if grid else "NULL")
	
	# Ensure grid is fully initialized and ready
	if grid:
		grid.regenerate()
	
	# Wait for frames to ensure initialization is complete
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Create player and set up initial state
	call_deferred("_deferred_create_player")
	
	# After player creation, force chunk update with a significant delay
	await get_tree().create_timer(0.5).timeout
	
	# Final forced chunk update after everything is ready
	if player and grid:
		var cell_x = int(floor(player.global_position.x / grid.cell_size.x))
		var cell_y = int(floor(player.global_position.y / grid.cell_size.y))
		print("Final forced chunk update at: (", cell_x, ",", cell_y, ")")
		
		# Force three chunk updates with frame delays
		grid.update_loaded_chunks(cell_x, cell_y)
		await get_tree().process_frame
		grid.update_loaded_chunks(cell_x, cell_y)
		await get_tree().process_frame
		grid.update_loaded_chunks(cell_x, cell_y)
		
		# Force redraw all objects
		grid.queue_redraw()
		if planet_spawner:
			planet_spawner.queue_redraw()
		if asteroid_spawner:
			asteroid_spawner.queue_redraw()
			
		# Ensure player is in normal state (not immobilized)
		if player.has_method("set_immobilized"):
			player.set_immobilized(false)
	
	print("Main scene initialization complete")

func _process(delta):
	# Seed control with number keys
	for i in range(10):
		if Input.is_key_pressed(KEY_0 + i):
			print("Changing seed to: ", i)
			grid.set_seed(i)
			update_seed_label()
			
			# Use existing player, just update its position
<<<<<<< HEAD
			if player:
				call_deferred("force_place_player", true)
			else:
				call_deferred("create_player")
=======
			create_player()
>>>>>>> parent of 3cca589 (Huge enemy update)
	
	# Handle message timer for auto-hiding
	if message_timer > 0:
		message_timer -= delta
		if message_timer <= 0:
			hide_message()

func _input(event):
	# Toggle debug visualization with F1 key
	if event is InputEventKey and event.pressed and event.keycode == KEY_F1:
		debug_mode = !debug_mode
		
		# Update debug mode for all systems
		grid.debug_mode = debug_mode
		if planet_spawner:
			planet_spawner.debug_mode = debug_mode
		if asteroid_spawner:
			asteroid_spawner.debug_mode = debug_mode
		
		print("Debug mode: ", debug_mode)
		
		# Force redraw
		grid.queue_redraw()
		if planet_spawner:
			planet_spawner.queue_redraw()
		if asteroid_spawner:
			asteroid_spawner.queue_redraw()
			
	# Force chunk reload with F2 key
	if event is InputEventKey and event.pressed and event.keycode == KEY_F2:
		force_reload_chunks()
		print("Chunks forcibly reloaded")

# Function to force reload chunks around player
func force_reload_chunks():
	if player == null:
		print("ERROR: Cannot reload chunks - player is null")
		return
		
	print("Forcing chunk reload around player")
	
	# Calculate current cell coordinates
	var cell_x = int(floor(player.global_position.x / grid.cell_size.x))
	var cell_y = int(floor(player.global_position.y / grid.cell_size.y))
	
	# Force clear loaded cells
	grid.loaded_cells.clear()
	
	# Force update loaded chunks
	grid.update_loaded_chunks(cell_x, cell_y)
	
	# Force redraw all objects
	grid.queue_redraw()
	if planet_spawner:
		planet_spawner.queue_redraw()
	if asteroid_spawner:
		asteroid_spawner.queue_redraw()
		
	# Print loaded cells for debugging
	print("Current player position: ", player.global_position)
	print("Current player cell: (", cell_x, ",", cell_y, ")")
	print("Loaded cells count: ", grid.loaded_cells.size())
	print("Loaded cells: ", grid.loaded_cells.keys())

# Force place player with option to use a specific seed
func force_place_player(clear_cells = false):
	if player == null:
		print("ERROR: Cannot force place player - player is null")
		return
	
	print("Forcing player placement")
	
	# Clear loaded cells if requested
	if clear_cells and grid:
		grid.loaded_cells.clear()
		grid.previous_loaded_cells.clear()
	
	# Force grid re-render
	if grid:
		grid.queue_redraw()
	
	# Get planet positions
	var planets = get_planet_positions()
	
	if planets.size() > 0:
		# Choose a random planet
		var rng = RandomNumberGenerator.new()
		rng.seed = grid.seed_value if grid else 0
		var random_index = rng.randi() % planets.size()
		
		var chosen_planet = planets[random_index]
		
		# Set player position
		player.global_position = chosen_planet.position
		
		# Store initial position
		initial_planet_position = chosen_planet.position
		initial_planet_cell_x = chosen_planet.grid_x
		initial_planet_cell_y = chosen_planet.grid_y
		
		# Calculate cell coordinates
		var cell_x = chosen_planet.grid_x
		var cell_y = chosen_planet.grid_y
		
		print("FORCED player placement at cell: (", cell_x, ",", cell_y, ")")
		
		# Update grid tracking
		if grid:
			grid.current_player_cell_x = cell_x
			grid.current_player_cell_y = cell_y
		
		# Update player cell tracking if method exists
		if player.has_method("update_cell_position"):
			player.update_cell_position(cell_x, cell_y)
		else:
			print("WARNING: Player does not have update_cell_position method")
			# Fallback: set variables directly
			if "previous_cell_x" in player:
				player.previous_cell_x = cell_x
				player.previous_cell_y = cell_y
		
		# Force chunk loading with multiple attempts
		if grid:
			print("Forcing chunk loading at: (", cell_x, ",", cell_y, ")")
			
			# Multiple load attempts with delays
			grid.update_loaded_chunks(cell_x, cell_y)
			await get_tree().process_frame
			grid.update_loaded_chunks(cell_x, cell_y)
			await get_tree().process_frame
			grid.update_loaded_chunks(cell_x, cell_y)
			
			# Force redraw everything
			grid.queue_redraw()
			if planet_spawner:
				planet_spawner.queue_redraw()
			if asteroid_spawner:
				asteroid_spawner.queue_redraw()
			
			# Print loaded cells for debugging
			print("Loaded cells count: ", grid.loaded_cells.size())
			print("Loaded cells: ", grid.loaded_cells.keys())
		
		# Ensure player is not immobilized
		if player.has_method("set_immobilized"):
			player.set_immobilized(false)
		
		# Show welcome message
		var planet_name = generate_planet_name(chosen_planet.grid_x, chosen_planet.grid_y)
		show_message("Welcome to planet " + planet_name + "!")
		
		# Manual visibility update
		call_deferred("_on_grid_chunks_updated", grid.loaded_cells if grid else {})
	else:
		print("ERROR: No planets available for forced placement")
		handle_no_planets_found()

# Enhanced spawner coordination
func _on_grid_cell_contents_changed(seed_val):
	print("Regenerating world with seed: ", seed_val)
	
	# Clear all existing cell occupancy first
	grid.clear_cell_occupancy()
	
	# Initialize planet spawner first (planets take priority)
	if planet_spawner:
		var planet_success = planet_spawner.initialize(grid, seed_val)
		print("Planet spawner initialized: ", planet_success)
	
	# Initialize asteroid spawner after planets are placed
	if asteroid_spawner:
		var asteroid_success = asteroid_spawner.initialize(grid, seed_val)
		print("Asteroid spawner initialized: ", asteroid_success)
	
	# Reset enemies after content generation is complete
	if enemy_spawner:
		enemy_spawner.reset_enemies()
		
	# Force grid redraw
	grid.queue_redraw()

# Called when chunks are updated (visibility changes)
func _on_grid_chunks_updated(loaded_cells):
	# Update spawners visibility
	if planet_spawner:
		planet_spawner.update_visibility()
	
	if asteroid_spawner:
		asteroid_spawner.update_visibility()

# Called when a planet is spawned
func _on_planet_spawned(position, grid_x, grid_y):
	# Update the grid's cell_contents array for collision/pathfinding
	grid.set_cell_content(grid_x, grid_y, grid.CellContent.PLANET)

func update_seed_label():
	if seed_label:
		seed_label.text = "Current Seed: " + str(grid.seed_value if grid else "Unknown")

# Function to show a temporary message
func show_message(text):
	if message_label:
		message_label.text = text
		message_label.visible = true
		message_timer = MESSAGE_DURATION
		print(text)  # Also output to console

# Function to hide the message
func hide_message():
	if message_label:
		message_label.visible = false

# Function to respawn the player at the initial planet
func respawn_player_at_initial_planet():
	if player and initial_planet_position:
		print("Respawning player at initial planet: ", initial_planet_position)
		
		# Reset player's position
		player.global_position = initial_planet_position
		
		# Force grid chunk update
		if grid:
			grid.current_player_cell_x = initial_planet_cell_x
			grid.current_player_cell_y = initial_planet_cell_y
			grid.update_loaded_chunks(initial_planet_cell_x, initial_planet_cell_y)
			grid.queue_redraw()
		
		# Generate a planet name for the respawn
		var planet_name = generate_planet_name(initial_planet_cell_x, initial_planet_cell_y)
		
		# Show respawn message
		show_message("You have been rescued and returned to planet " + planet_name + ".")
		
		# Ensure player is not immobilized
		if player.has_method("set_immobilized"):
			player.set_immobilized(false)
	else:
		print("ERROR: Cannot respawn player - missing initial planet position!")
		
		# Emergency fallback - just place at a new random planet
		place_player_at_random_planet()

# Function to position the message label relative to player
func position_message_label():
	if player and message_label:
		var viewport_size = get_viewport_rect().size
		var camera_pos = player.get_node("Camera2D").get_screen_center_position()
		
		# Position centered horizontally, and halfway between player and bottom of screen
		message_label.global_position = Vector2(
			camera_pos.x,
			camera_pos.y + viewport_size.y / 4
		)

func get_planet_positions():
	# Use the planet spawner to get all planets
	if planet_spawner:
		return planet_spawner.get_all_planets()
	
	# Fallback empty list if spawner isn't available
	return []

func create_player():
	# If there's already a player, just update its position rather than creating a new one
	if has_node("Player"):
		player = get_node("Player")
		print("Using existing player instance")
		call_deferred("place_player_at_random_planet")
		return
	
	# Only create a new player if one doesn't exist
	call_deferred("_deferred_create_player")

# Deferred player creation to ensure proper scene tree updates
func _deferred_create_player():
	var player_scene = load("res://player.tscn")
	player = player_scene.instantiate()
	
	# Assign script to the player if it doesn't have one already
	if !player.get_script():
		var player_script = load("res://player_refactored.gd")
		player.set_script(player_script)
	
	# Add to scene tree
	add_child(player)
	
	# Initialize at a safe default position first
	player.global_position = Vector2(100, 100)
	
	# Make player directly available in the scene tree
	player.name = "Player"
	
	print("Player created at initial position: ", player.global_position)
	
	# Call the placement function after a short delay
	call_deferred("place_player_at_random_planet")

# Enhanced planet placement with better error handling
func place_player_at_random_planet():
	# Verify player exists
	if player == null:
		print("ERROR: Player is null!")
		return
	
	# Force grid re-render to ensure it's updated
	if grid:
		grid.queue_redraw()
	
	# Get all planet positions from the planet spawner
	var planets = get_planet_positions()
	
	if planets.size() > 0:
		# Choose a random planet using the grid's seed
		var rng = RandomNumberGenerator.new()
		rng.seed = grid.seed_value if grid else 0
		var random_index = rng.randi() % planets.size()
		
		var chosen_planet = planets[random_index]
		
		# Set player position directly
		player.global_position = chosen_planet.position
		
		# Store the initial spawn position for respawning
		initial_planet_position = chosen_planet.position
		initial_planet_cell_x = chosen_planet.grid_x
		initial_planet_cell_y = chosen_planet.grid_y
		
		# Calculate cell coordinates from player position
		var cell_x = int(floor(player.global_position.x / grid.cell_size.x))
		var cell_y = int(floor(player.global_position.y / grid.cell_size.y))
		
		# Explicitly print the calculated cell coordinates for debugging
		print("CALCULATED player cell coordinates: (", cell_x, ",", cell_y, ")")
		
		# Force update the player cell position in grid
		if grid:
			grid.current_player_cell_x = cell_x
			grid.current_player_cell_y = cell_y
		
		# Initialize the player's cell tracking variables
		if player.has_method("update_cell_position"):
			player.update_cell_position(cell_x, cell_y)
		else:
			# Fallback: set variables directly if method doesn't exist
			if "previous_cell_x" in player:
				player.previous_cell_x = cell_x
				player.previous_cell_y = cell_y
		
		# Force update loaded chunks and ensure it's processed
		var chunks_updated = false
		if grid:
			chunks_updated = grid.update_loaded_chunks(cell_x, cell_y)
			print("Chunks updated successfully: ", chunks_updated)
			print("Current loaded cells: ", grid.loaded_cells.size())
		
		# Additional safety - force redraw all objects
		if grid:
			grid.queue_redraw()
		if planet_spawner:
			planet_spawner.queue_redraw()
		if asteroid_spawner:
			asteroid_spawner.queue_redraw()
		
		# Generate a planet name based on coordinates
		var planet_name = generate_planet_name(chosen_planet.grid_x, chosen_planet.grid_y)
		
		# Show welcome message
		show_message("Welcome to planet " + planet_name + "!")
		
		print("Player placed at planet " + planet_name + " position: ", chosen_planet.position)
		print("Starting cell: (", cell_x, ",", cell_y, ")")
		
		# Ensure player is not immobilized
		if player.has_method("set_immobilized"):
			player.set_immobilized(false)
		
		# Manually trigger the chunks_updated signal to ensure visibility updates
		call_deferred("_on_grid_chunks_updated", grid.loaded_cells if grid else {})
		
		# Add a one-frame delay and force another chunk update to be safe
		await get_tree().process_frame
		if grid:
			grid.update_loaded_chunks(cell_x, cell_y)
	else:
		handle_no_planets_found()

# Handle the case when no planets are found
func handle_no_planets_found():
	# Fallback to grid center
	var center = Vector2(
		grid.grid_size.x * grid.cell_size.x / 2 if grid else 512,
		grid.grid_size.y * grid.cell_size.y / 2 if grid else 512
	)
	
	if player:
		player.global_position = center
	
	# Store the initial spawn position for respawning
	initial_planet_position = center
	initial_planet_cell_x = int(floor(center.x / (grid.cell_size.x if grid else 64)))
	initial_planet_cell_y = int(floor(center.y / (grid.cell_size.y if grid else 64)))
	
	# Initialize the loaded chunks around the player's center position
	var cell_x = initial_planet_cell_x
	var cell_y = initial_planet_cell_y
	
	if grid:
		grid.current_player_cell_x = cell_x
		grid.current_player_cell_y = cell_y
		grid.update_loaded_chunks(cell_x, cell_y)
	
	print("WARNING: No planets found. Player placed at grid center: ", center)
	print("Starting cell: (", cell_x, ",", cell_y, ")")
	
	# Show an error message
	show_message("ERROR: No planets found. Placed at grid center.")
	
	# Emergency: Trigger grid regeneration in case something went wrong
	if grid:
		grid.regenerate()
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Try again with newly generated grid
	var new_planets = get_planet_positions()
	if new_planets.size() > 0:
		emergency_planet_placement(new_planets)

# Handle emergency planet placement
func emergency_planet_placement(planets):
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value if grid else 0
	var random_index = rng.randi() % planets.size()
	var fallback_position = planets[random_index].position
	
	if player:
		player.global_position = fallback_position
	
	# Update initial position for respawning
	initial_planet_position = fallback_position
	initial_planet_cell_x = planets[random_index].grid_x
	initial_planet_cell_y = planets[random_index].grid_y
	
	# Update loaded chunks for the new position
	var cell_x = initial_planet_cell_x
	var cell_y = initial_planet_cell_y
	
	if grid:
		grid.current_player_cell_x = cell_x
		grid.current_player_cell_y = cell_y
		grid.update_loaded_chunks(cell_x, cell_y)
	
	# Generate a planet name for the fallback position
	var planet_name = generate_planet_name(planets[random_index].grid_x, planets[random_index].grid_y)
	
	# Show welcome message
	show_message("Welcome to planet " + planet_name + "!")
	
	print("Player repositioned at planet " + planet_name + " after emergency regeneration")
	print("Updated starting cell: (", cell_x, ",", cell_y, ")")
	
	# Ensure player is not immobilized
	if player and player.has_method("set_immobilized"):
		player.set_immobilized(false)

# Function to generate a planet name based on coordinates
func generate_planet_name(x, y):
	# Simple algorithm to create a unique planet name based on grid coordinates
	var consonants = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"]
	var vowels = ["a", "e", "i", "o", "u"]
	
	# Create a deterministic name based on coordinates and seed
	var rng = RandomNumberGenerator.new()
	rng.seed = (grid.seed_value if grid else 0) + (x * 100) + y
	
	var planet_name = ""

	# First syllable
	planet_name += consonants[rng.randi() % consonants.size()].to_upper()
	planet_name += vowels[rng.randi() % vowels.size()]

	# Second syllable
	planet_name += consonants[rng.randi() % consonants.size()]
	planet_name += vowels[rng.randi() % vowels.size()]

	# Add a number or hyphen followed by additional characters based on coordinates
	if rng.randi() % 2 == 0:
		# Add hyphen and letters
		planet_name += "-"
		planet_name += consonants[rng.randi() % consonants.size()].to_upper()
		planet_name += vowels[rng.randi() % vowels.size()]
	else:
		# Add numbers
		planet_name += " " + str((x + y) % 9 + 1)

	return planet_name
