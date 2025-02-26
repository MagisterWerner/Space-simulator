extends Node2D

@onready var grid = $Grid
@onready var seed_label = $CanvasLayer/SeedLabel
@onready var message_label = $CanvasLayer/MessageLabel

# References to spawners
@onready var planet_spawner = $PlanetSpawner
@onready var asteroid_spawner = $AsteroidSpawner
@onready var enemy_spawner = $EnemySpawner

# Use a direct node reference instead of preloading
var player = null

# Message display duration in seconds
const MESSAGE_DURATION = 3.0
var message_timer = 0.0

# Store initial planet position for respawning
var initial_planet_position = null
var initial_planet_cell_x = 0
var initial_planet_cell_y = 0

func _ready():
	# Initialize seed label
	update_seed_label()
	
	# Initialize message label and show welcome message
	if message_label:
		message_label.visible = true
		message_label.text = "Welcome to the galaxy!"
		message_timer = MESSAGE_DURATION
	
	# Connect to grid signals
	grid.cell_contents_changed.connect(_on_grid_cell_contents_changed)
	grid.chunks_updated.connect(_on_grid_chunks_updated)
	
	# Connect to planet spawner signals
	planet_spawner.planet_spawned.connect(_on_planet_spawned)
	
	# Ensure grid is fully initialized and ready
	grid.regenerate()
	
	# Wait for frames to ensure initialization is complete
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Create player (this handles deferred placement at a planet)
	create_player()

func _process(delta):
	# Seed control with number keys
	for i in range(10):
		if Input.is_key_pressed(KEY_0 + i):
			print("Changing seed to: ", i)
			grid.set_seed(i)
			update_seed_label()
			
			# Use existing player, just update its position
			create_player()
	
	# Handle message timer for auto-hiding
	if message_timer > 0:
		message_timer -= delta
		if message_timer <= 0:
			hide_message()

# Called when grid cells contents should be generated
func _on_grid_cell_contents_changed(seed_val):
	print("Regenerating world with seed: ", seed_val)
	
	# Initialize planet spawner
	if planet_spawner:
		var success = planet_spawner.initialize(grid, seed_val)
		print("Planet spawner initialized: ", success)
	
	# Initialize asteroid spawner
	if asteroid_spawner:
		var success = asteroid_spawner.initialize(grid, seed_val)
		print("Asteroid spawner initialized: ", success)
	
	# Reset enemies after content change
	if enemy_spawner:
		enemy_spawner.reset_enemies()

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
	seed_label.text = "Current Seed: " + str(grid.seed_value)

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
		grid.current_player_cell_x = initial_planet_cell_x
		grid.current_player_cell_y = initial_planet_cell_y
		grid.update_loaded_chunks(initial_planet_cell_x, initial_planet_cell_y)
		grid.queue_redraw()
		
		# Generate a planet name for the respawn
		var planet_name = generate_planet_name(initial_planet_cell_x, initial_planet_cell_y)
		
		# Show respawn message
		show_message("You have been rescued and returned to planet " + planet_name + ".")
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

func place_player_at_random_planet():
	# Verify player exists
	if player == null:
		print("ERROR: Player is null!")
		return
	
	# Force grid re-render to ensure it's updated
	grid.queue_redraw()
	
	# Get all planet positions from the planet spawner
	var planets = get_planet_positions()
	
	if planets.size() > 0:
		# Choose a random planet using the grid's seed
		var rng = RandomNumberGenerator.new()
		rng.seed = grid.seed_value
		var random_index = rng.randi() % planets.size()
		
		var chosen_planet = planets[random_index]
		
		# Set player position directly
		player.global_position = chosen_planet.position
		
		# Store the initial spawn position for respawning
		initial_planet_position = chosen_planet.position
		initial_planet_cell_x = chosen_planet.grid_x
		initial_planet_cell_y = chosen_planet.grid_y
		
		# Initialize the loaded chunks around the player's starting position
		var cell_x = int(floor(player.global_position.x / grid.cell_size.x))
		var cell_y = int(floor(player.global_position.y / grid.cell_size.y))
		grid.current_player_cell_x = cell_x
		grid.current_player_cell_y = cell_y
		grid.update_loaded_chunks(cell_x, cell_y)
		
		# Generate a planet name based on coordinates
		var planet_name = generate_planet_name(chosen_planet.grid_x, chosen_planet.grid_y)
		
		# Show welcome message
		show_message("Welcome to planet " + planet_name + "!")
		
		print("Player placed at planet " + planet_name + " position: ", chosen_planet.position)
		print("Starting cell: (", cell_x, ",", cell_y, ")")
	else:
		handle_no_planets_found()

# Handle the case when no planets are found
func handle_no_planets_found():
	# Fallback to grid center
	var center = Vector2(
		grid.grid_size.x * grid.cell_size.x / 2,
		grid.grid_size.y * grid.cell_size.y / 2
	)
	player.global_position = center
	
	# Store the initial spawn position for respawning
	initial_planet_position = center
	initial_planet_cell_x = int(floor(center.x / grid.cell_size.x))
	initial_planet_cell_y = int(floor(center.y / grid.cell_size.y))
	
	# Initialize the loaded chunks around the player's center position
	var cell_x = int(floor(center.x / grid.cell_size.x))
	var cell_y = int(floor(center.y / grid.cell_size.y))
	grid.current_player_cell_x = cell_x
	grid.current_player_cell_y = cell_y
	grid.update_loaded_chunks(cell_x, cell_y)
	
	print("WARNING: No planets found. Player placed at grid center: ", center)
	print("Starting cell: (", cell_x, ",", cell_y, ")")
	
	# Show an error message
	show_message("ERROR: No planets found. Placed at grid center.")
	
	# Emergency: Trigger grid regeneration in case something went wrong
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
	rng.seed = grid.seed_value
	var random_index = rng.randi() % planets.size()
	var fallback_position = planets[random_index].position
	player.global_position = fallback_position
	
	# Update initial position for respawning
	initial_planet_position = fallback_position
	initial_planet_cell_x = planets[random_index].grid_x
	initial_planet_cell_y = planets[random_index].grid_y
	
	# Update loaded chunks for the new position
	var cell_x = int(floor(fallback_position.x / grid.cell_size.x))
	var cell_y = int(floor(fallback_position.y / grid.cell_size.y))
	grid.current_player_cell_x = cell_x
	grid.current_player_cell_y = cell_y
	grid.update_loaded_chunks(cell_x, cell_y)
	
	# Generate a planet name for the fallback position
	var planet_name = generate_planet_name(planets[random_index].grid_x, planets[random_index].grid_y)
	
	# Show welcome message
	show_message("Welcome to planet " + planet_name + "!")
	
	print("Player repositioned at planet " + planet_name + " after emergency regeneration")
	print("Updated starting cell: (", cell_x, ",", cell_y, ")")

# Function to generate a planet name based on coordinates
func generate_planet_name(x, y):
	# Simple algorithm to create a unique planet name based on grid coordinates
	var consonants = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"]
	var vowels = ["a", "e", "i", "o", "u"]
	
	# Create a deterministic name based on coordinates and seed
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value + (x * 100) + y
	
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
