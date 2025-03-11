# scripts/main.gd
# Main scene controller that integrates all game systems
# Properly handles dependency initialization and game startup
extends Node2D

@onready var camera = $Camera2D
@onready var space_background = $SpaceBackground
@onready var game_settings = $GameSettings
@onready var world_grid = $WorldGrid

var screen_size: Vector2
var world_generator = null
var player_start_position: Vector2 = Vector2.ZERO
var player_start_cell: Vector2i = Vector2i(-1, -1)

# Services
var service_locator = null
var game_manager = null
var entity_manager = null
var seed_manager = null
var resource_manager = null

func _ready() -> void:
	print("Main: Starting initialization sequence")
	screen_size = get_viewport_rect().size
	
	# First check for ServiceLocator availability
	if has_node("/root/ServiceLocator"):
		service_locator = get_node("/root/ServiceLocator")
		
		# Connect to the all_services_initialized signal if available
		if service_locator.has_signal("all_services_initialized") and not service_locator.is_connected("all_services_initialized", _on_all_services_initialized):
			service_locator.connect("all_services_initialized", _on_all_services_initialized)
			
			# Check if services are already initialized
			if service_locator.are_all_services_initialized():
				_on_all_services_initialized()
			else:
				print("Main: Waiting for all services to initialize...")
				# Wait for services to initialize
				return
	else:
		push_error("Main: ServiceLocator not found - dependency injection system missing")
		# Fall back to direct initialization without DI
		_initialize_game_direct()
		return
		
	# If we reach here, we're either already initialized or will wait for the signal

# Called when all services have been initialized
func _on_all_services_initialized() -> void:
	print("Main: All services initialized, proceeding with game setup")
	
	# Get references to required services
	_get_service_references()
	
	# Initialize game systems
	_initialize_game()

# Get references to all required services
func _get_service_references() -> void:
	# Safely get each service
	if service_locator.has_service("GameManager"):
		game_manager = service_locator.get_service("GameManager")
	else:
		push_error("Main: GameManager service not available")
	
	if service_locator.has_service("EntityManager"):
		entity_manager = service_locator.get_service("EntityManager")
	else:
		push_error("Main: EntityManager service not available")
	
	if service_locator.has_service("SeedManager"):
		seed_manager = service_locator.get_service("SeedManager")
	else:
		push_error("Main: SeedManager service not available")
	
	if service_locator.has_service("ResourceManager"):
		resource_manager = service_locator.get_service("ResourceManager")
	
	# Debug print available services
	if game_settings and "debug_mode" in game_settings and game_settings.debug_mode:
		print("Main: Service availability status:")
		print("- GameManager: ", game_manager != null)
		print("- EntityManager: ", entity_manager != null)
		print("- SeedManager: ", seed_manager != null)
		print("- ResourceManager: ", resource_manager != null)

# Initialize without dependency injection as fallback
func _initialize_game_direct() -> void:
	print("Main: Initializing game without dependency injection")
	
	# Get direct references to autoloaded nodes
	if has_node("/root/GameManager"):
		game_manager = get_node("/root/GameManager")
	
	if has_node("/root/EntityManager"):
		entity_manager = get_node("/root/EntityManager")
	
	if has_node("/root/SeedManager"):
		seed_manager = get_node("/root/SeedManager")
	
	if has_node("/root/ResourceManager"):
		resource_manager = get_node("/root/ResourceManager")
	
	# Initialize the game with direct references
	_initialize_game()

func _initialize_game() -> void:
	# Preload sound effects if AudioManager is available
	if has_node("/root/AudioManager"):
		var audio_manager = get_node("/root/AudioManager")
		audio_manager.preload_sfx("laser", "res://assets/audio/laser.sfxr", 20)
		audio_manager.preload_sfx("explosion_debris", "res://assets/audio/explosion_debris.wav", 10)
		audio_manager.preload_sfx("explosion_fire", "res://assets/audio/explosion_fire.wav", 10)
		audio_manager.preload_sfx("missile", "res://assets/audio/missile.sfxr", 5)
		audio_manager.preload_sfx("thruster", "res://assets/audio/thruster.wav", 5)

	# Wait for game settings to initialize if needed
	if game_settings and not game_settings._initialized and game_settings.has_signal("settings_initialized"):
		if not game_settings.is_connected("settings_initialized", _on_game_settings_initialized):
			game_settings.settings_initialized.connect(_on_game_settings_initialized)
			print("Main: Waiting for GameSettings to initialize...")
			return
	
	# If settings already initialized or not available, initialize seed manager
	_initialize_seed_manager()

func _on_game_settings_initialized() -> void:
	print("Main: GameSettings initialized")
	_initialize_seed_manager()

func _initialize_seed_manager() -> void:
	# Make sure SeedManager gets the correct seed from GameSettings
	if seed_manager and game_settings:
		# Wait for SeedManager to be initialized if necessary
		if not seed_manager._seed_initialized and seed_manager.has_signal("seed_initialized"):
			if not seed_manager.is_connected("seed_initialized", _on_seed_manager_initialized):
				seed_manager.seed_initialized.connect(_on_seed_manager_initialized)
				print("Main: Waiting for SeedManager to initialize...")
				return
			
		# Set the seed in SeedManager
		seed_manager.set_seed(game_settings.get_seed())
		
		if "debug_mode" in game_settings and game_settings.debug_mode:
			print("Main: Set SeedManager seed to: ", game_settings.get_seed())
	
	# Continue with world generation
	_initialize_world_generator()

func _on_seed_manager_initialized() -> void:
	print("Main: SeedManager initialized")
	if game_settings:
		seed_manager.set_seed(game_settings.get_seed())
	_initialize_world_generator()

func _initialize_world_generator() -> void:
	# Initialize world generator
	world_generator = WorldGenerator.new()
	add_child(world_generator)
	
	# Connect world generation signals
	if world_generator.has_signal("world_generation_completed"):
		world_generator.world_generation_completed.connect(_on_world_generation_completed)
	
	# Generate starter world
	if world_generator.has_method("generate_starter_world"):
		var planet_data = world_generator.generate_starter_world()
		
		# Store the starting planet information for GameManager
		if planet_data and "player_planet_cell" in planet_data and planet_data.player_planet_cell != Vector2i(-1, -1):
			# Calculate world position
			player_start_cell = planet_data.player_planet_cell
			player_start_position = game_settings.get_cell_world_position(player_start_cell)
			
			if game_settings and "debug_mode" in game_settings and game_settings.debug_mode:
				print("Main: Determined player start position at: ", player_start_position)
		else:
			# Fallback to grid center position if no planet was generated
			player_start_position = game_settings.get_player_starting_position()
	else:
		# Fallback if generate_starter_world doesn't exist
		print("Main: WorldGenerator doesn't have generate_starter_world method")
		player_start_position = screen_size / 2
	
	# Initially position camera at the player start position
	camera.position = player_start_position
	
	# Register camera in group for background to find
	camera.add_to_group("camera")
	
	# Ensure space background is initialized
	if space_background and not space_background.initialized:
		# If the background uses the game seed, wait until it's properly initialized
		if "use_game_seed" in space_background and space_background.use_game_seed and seed_manager:
			space_background.background_seed = seed_manager.get_seed()
		
		space_background.setup_background()
	
	# Start the game using GameManager
	_start_game_manager()

func _on_world_generation_completed() -> void:
	if game_settings and "debug_mode" in game_settings and game_settings.debug_mode:
		print("Main: World generation completed")

func _start_game_manager() -> void:
	# Critical check: Make sure EntityManager and GameManager are available
	if not entity_manager:
		push_error("Main: EntityManager not available! Cannot start the game.")
		if game_settings and "debug_mode" in game_settings and game_settings.debug_mode:
			print("Main: Available autoloads:")
			for child in get_node("/root").get_children():
				if child != get_tree().current_scene:
					print(" - " + child.name)
					
			# Try to manually initialize EntityManager if it exists
			if has_node("/root/EntityManager"):
				entity_manager = get_node("/root/EntityManager")
				if entity_manager.has_method("initialize_service"):
					print("Main: Manually initializing EntityManager...")
					entity_manager.initialize_service()
				else:
					print("Main: EntityManager exists but cannot be initialized")
			else:
				print("Main: EntityManager node does not exist in the scene tree")
		return
	
	if not game_manager:
		push_error("Main: GameManager not available! Cannot start the game.")
		return
		
	# Double-check initialization status
	if service_locator:
		if not service_locator.is_service_initialized("EntityManager"):
			push_error("Main: EntityManager service not fully initialized!")
			return
			
		if not service_locator.is_service_initialized("GameManager"):
			push_error("Main: GameManager service not fully initialized!")
			return
	
	# Configure game manager with our settings
	if game_settings and game_manager.has_method("configure_with_settings"):
		game_manager.configure_with_settings(game_settings)
		
		# Wait for any async operations to complete
		await get_tree().process_frame
	
	# Pass the player start position to GameManager
	if game_manager.has_method("set_player_start_position"):
		game_manager.set_player_start_position(player_start_position, player_start_cell)
	
	# Start the game
	print("Main: Starting game via GameManager...")
	game_manager.start_game()

func _process(delta: float) -> void:
	# Follow player with camera
	_update_camera_position()
	
	# Handle window resize events (if they occur)
	var current_size = get_viewport_rect().size
	if current_size != screen_size:
		screen_size = current_size
		if space_background:
			space_background.update_viewport_size()

func _update_camera_position() -> void:
	# Try to get player ship either via GameManager or directly
	var player_ship = null
	
	if game_manager and is_instance_valid(game_manager.player_ship):
		player_ship = game_manager.player_ship
	elif entity_manager:
		# Get player directly from EntityManager if needed
		var player = entity_manager.get_nearest_entity(Vector2.ZERO, "player")
		if is_instance_valid(player):
			player_ship = player
	
	# Update camera position if player found
	if player_ship:
		camera.position = player_ship.position
	elif player_start_position != Vector2.ZERO:
		# Fallback to start position if no player exists yet
		camera.position = player_start_position
