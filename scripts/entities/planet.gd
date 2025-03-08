# scripts/main.gd
extends Node2D

# Node references
@onready var player_ship = $PlayerShip
@onready var camera = $Camera2D
@onready var space_background = $SpaceBackground
@onready var world_grid = $WorldGrid
@onready var settings = $GameSettings

# Planet management
var planet_spawners = []
var planets_generated = 0
var planets_loaded = 0
var starting_planet = null
var screen_size: Vector2
var generation_complete = false
var startup_timer = 0.0

# Signals
signal planets_ready
signal grid_ready
signal game_initialized

# Preloaded resources
var planet_spawner_scene = preload("res://scenes/world/planet_spawner.tscn")

func _ready() -> void:
	# Get screen size
	screen_size = get_viewport_rect().size
	
	# Connect to settings changes
	if settings and settings.has_signal("settings_changed"):
		settings.connect("settings_changed", _on_settings_changed)
	
	# Register camera in group for backgrounds and other systems
	camera.add_to_group("camera")
	
	# Start the game initialization sequence
	call_deferred("_start_game_initialization")

func _start_game_initialization() -> void:
	print("Starting game initialization...")
	var loading_indicator = _create_loading_indicator()
	
	# Initialize seed first
	_initialize_seed()
	
	# Setup grid with settings
	_setup_world_grid()
	
	# Allow one frame for autoloads to initialize
	await get_tree().process_frame
	
	# Initialize space background
	if space_background:
		if not space_background.initialized:
			space_background.setup_background()
	
	# Generate planets
	generate_planets()
	
	# Wait for planets to be generated
	await planets_ready
	
	# Position player at starting planet
	_position_player_at_starting_planet()
	
	# Remove loading indicator
	if loading_indicator:
		loading_indicator.queue_free()
	
	# Start the game
	_start_game_via_manager()
	
	# Emit initialization complete signal
	game_initialized.emit()
	
	print("Game initialization complete!")

func _initialize_seed() -> void:
	if has_node("/root/SeedManager"):
		if settings.use_random_seed:
			SeedManager.set_random_seed()
			print("Game initialized with random seed: ", SeedManager.get_seed())
		else:
			SeedManager.set_seed(settings.game_seed)
			print("Game initialized with fixed seed: ", settings.game_seed)

func _setup_world_grid() -> void:
	if world_grid:
		# Configure grid using settings
		world_grid.configure(
			settings.grid_size, 
			settings.cell_size, 
			settings.grid_color, 
			settings.grid_line_width, 
			settings.grid_opacity
		)
		
		# Wait for grid to initialize if it hasn't already
		if not world_grid._initialized:
			await world_grid.grid_initialized
		
		grid_ready.emit()
		
		print("World grid initialized with size: ", settings.grid_size, 
			", cell size: ", settings.cell_size)

func generate_planets() -> void:
	print("Starting planet generation...")
	
	# Clean previous spawners if any
	for spawner in planet_spawners:
		if is_instance_valid(spawner):
			spawner.queue_free()
	
	planet_spawners = []
	planets_generated = 0
	planets_loaded = 0
	starting_planet = null
	
	# Track occupied grid cells using the grid manager directly
	if world_grid:
		world_grid.reset_grid()
	
	# Get planet types in priority order (starting with preferred type)
	var planet_types = settings.get_planet_types_ordered()
	var starting_type = planet_types[0]
	
	# Prepare a list of planets to generate
	var planets_to_generate = []
	
	# Add starting type first
	planets_to_generate.append(starting_type)
	
	# Add all other unique types until we fill our quota
	var type_index = 1
	while planets_to_generate.size() < settings.num_terran_planets and type_index < planet_types.size():
		planets_to_generate.append(planet_types[type_index])
		type_index += 1
	
	# If we still need more planets, add random types from the remainder
	while planets_to_generate.size() < settings.num_terran_planets:
		var random_index = randi() % planet_types.size()
		if random_index != 0:  # Don't duplicate the starting type too much
			planets_to_generate.append(planet_types[random_index])
		else:
			planets_to_generate.append(planet_types[1 % planet_types.size()])
	
	print("Planning to generate ", planets_to_generate.size(), " planets: ", planets_to_generate)
	
	# Generate planets systematically - ensure we get all types represented
	for i in range(planets_to_generate.size()):
		var planet_type = planets_to_generate[i]
		
		# Find a valid grid position
		var grid_pos = _find_valid_grid_position()
		
		if grid_pos.x < 0 or grid_pos.y < 0:
			push_warning("Could not find valid position for planet " + str(i))
			continue
		
		# Mark cells as occupied
		_mark_cells_around_position(grid_pos)
		
		# Create planet spawner
		var spawner = _create_planet_spawner(grid_pos.x, grid_pos.y, planet_type, i == 0)
		planet_spawners.append(spawner)
		
		planets_generated += 1
		
		# Wait briefly between planet generation to avoid stuttering
		if settings.async_planet_generation:
			await get_tree().create_timer(0.1).timeout
	
	# If we spawned at least one planet, wait for all to be loaded
	if planets_generated > 0:
		_wait_for_planets_loaded()
	else:
		push_error("Failed to generate any planets")
		planets_ready.emit()  # Signal even though failed, to avoid hanging

# Wait for all planets to complete loading
func _wait_for_planets_loaded() -> void:
	# If we're using threading, we need to wait for all planets to be loaded
	if settings.use_threading:
		# Set up a timer to check periodically
		while planets_loaded < planets_generated:
			await get_tree().create_timer(0.1).timeout
		
		print("All planets loaded successfully")
		planets_ready.emit()
	else:
		# For non-threaded mode, emit immediately
		print("Planets generated in synchronous mode")
		planets_ready.emit()

func _find_valid_grid_position() -> Vector2i:
	# Get all possible grid cells
	var all_cells = world_grid.get_all_valid_cells()
	
	# Randomly shuffle cells for better distribution
	all_cells.shuffle()
	
	# Check cells one by one to find unoccupied one
	for cell in all_cells:
		if not world_grid.is_cell_occupied(cell):
			return cell
	
	# Return invalid position if none found
	return Vector2i(-1, -1)

func _mark_cells_around_position(grid_pos: Vector2i) -> void:
	if not world_grid:
		return
	
	# Mark this cell as occupied
	world_grid.register_cell(grid_pos, "planet")
	
	# Mark surrounding cells based on min_distance
	for dx in range(-settings.min_planet_distance, settings.min_planet_distance + 1):
		for dy in range(-settings.min_planet_distance, settings.min_planet_distance + 1):
			var nx = grid_pos.x + dx
			var ny = grid_pos.y + dy
			var neighbor_pos = Vector2i(nx, ny)
			
			if world_grid.is_valid_cell(neighbor_pos) and not world_grid.is_cell_occupied(neighbor_pos):
				world_grid.register_cell(neighbor_pos, "exclusion")

func _create_planet_spawner(grid_x: int, grid_y: int, planet_type: String, is_starting_planet: bool = false) -> Node:
	var spawner = planet_spawner_scene.instantiate()
	add_child(spawner)
	
	# Configure spawner
	spawner.set_grid_position(grid_x, grid_y)
	spawner.use_threading = settings.use_threading
	spawner.use_texture_cache = settings.preload_textures
	
	# Connect to signals
	if is_starting_planet:
		spawner.connect("planet_spawned", _on_starting_planet_spawned)
	
	# Connect to generation completion signal
	spawner.connect("generation_completed", _on_planet_generation_completed)
	
	# Spawn planet of requested type
	spawner.spawn_terran_planet(planet_type)
	
	print("Created planet spawner for type ", planet_type, " at grid position ", grid_x, ",", grid_y)
	
	return spawner

func _on_starting_planet_spawned(planet_instance) -> void:
	starting_planet = planet_instance
	print("Starting planet spawned: ", planet_instance.planet_name if planet_instance else "None")

func _on_planet_generation_completed() -> void:
	planets_loaded += 1
	print("Planet ", planets_loaded, "/", planets_generated, " completed generation")

func _position_player_at_starting_planet() -> void:
	# Use starting planet position if available
	if starting_planet and is_instance_valid(starting_planet):
		player_ship.global_position = starting_planet.global_position
		camera.global_position = player_ship.global_position
		print("Positioned player at starting planet: ", starting_planet.planet_name)
	else:
		# Default to center of grid if no starting planet
		var grid_center = Vector2(
			world_grid.position.x + world_grid._grid_total_size.x / 2, 
			world_grid.position.y + world_grid._grid_total_size.y / 2
		)
		player_ship.global_position = grid_center
		camera.global_position = grid_center
		print("WARNING: Starting planet not found, positioned player at grid center")

func _start_game_via_manager() -> void:
	if has_node("/root/GameManager"):
		var game_manager = get_node("/root/GameManager")
		if game_manager.has_method("start_game"):
			game_manager.start_game()
			
			# If game manager needs the player ship, make sure it's set
			if game_manager.player_ship == null and is_instance_valid(player_ship):
				game_manager.player_ship = player_ship
			
			print("Game started via GameManager")
		else:
			push_error("GameManager found but doesn't have start_game method")
	else:
		push_warning("GameManager autoload not found, running in standalone mode")

func _on_settings_changed() -> void:
	# Update the world grid if it exists
	if world_grid:
		world_grid.configure(
			settings.grid_size, 
			settings.cell_size, 
			settings.grid_color, 
			settings.grid_line_width, 
			settings.grid_opacity
		)
	
	print("Game settings changed, grid updated")

func _process(delta: float) -> void:
	# Follow player with camera
	if has_node("/root/GameManager") and GameManager.player_ship and is_instance_valid(GameManager.player_ship):
		camera.global_position = GameManager.player_ship.global_position
	else:
		camera.global_position = player_ship.global_position
	
	# Handle window resize events
	var current_size = get_viewport_rect().size
	if current_size != screen_size:
		screen_size = current_size
		if space_background:
			space_background.update_viewport_size()

func _create_loading_indicator() -> Control:
	var indicator = Control.new()
	indicator.name = "LoadingIndicator"
	indicator.z_index = 100
	add_child(indicator)
	
	var panel = Panel.new()
	panel.anchor_right = 1.0
	panel.anchor_bottom = 1.0
	indicator.add_child(panel)
	
	var label = Label.new()
	label.text = "Generating planets..."
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.anchor_right = 1.0
	label.anchor_bottom = 1.0
	label.position.y = 20
	panel.add_child(label)
	
	return indicator
