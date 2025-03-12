# scripts/main.gd
# Main scene controller that integrates all game systems
# Updated to ensure deterministic initialization
extends Node2D

@onready var camera = $Camera2D
@onready var space_background = $SpaceBackground
@onready var game_settings = $GameSettings

var screen_size: Vector2
var world_generator = null
var player_start_position: Vector2 = Vector2.ZERO
var player_start_cell: Vector2i = Vector2i(-1, -1)
var initialization_complete = false

func _ready() -> void:
	screen_size = get_viewport_rect().size
	
	# Wait for game settings to initialize if needed
	if game_settings and not game_settings.is_connected("settings_initialized", _on_game_settings_initialized):
		if not game_settings._initialized:
			game_settings.connect("settings_initialized", _on_game_settings_initialized)
			return
	
	# If settings already initialized or not available, initialize directly
	_initialize_game()

func _on_game_settings_initialized() -> void:
	_initialize_game()

func _initialize_game() -> void:
	# Ensure we only initialize once
	if initialization_complete:
		return
	
	initialization_complete = true
	
	# Ensure seed is properly set first
	_initialize_seed()
	
	# Preload sound effects after seed is established
	_preload_audio()
	
	# Initialize world generator
	_initialize_world_generator()
	
	# Initialize background and camera
	_initialize_background_and_camera()
	
	# Start the game using GameManager
	_start_game_manager()

func _initialize_seed() -> void:
	# Make sure SeedManager gets the correct seed from GameSettings
	if has_node("/root/SeedManager") and game_settings:
		# Wait for SeedManager to be initialized if necessary
		# Fix: Check if is_initialized is a property (not a method)
		if "is_initialized" in SeedManager and not SeedManager.is_initialized:
			if SeedManager.has_signal("seed_initialized"):
				SeedManager.connect("seed_initialized", _on_seed_manager_initialized)
				return
		
		# Set the seed in SeedManager - important for world generation
		SeedManager.set_seed(game_settings.get_seed())
		
		if game_settings.debug_mode:
			print("Main: Initialized SeedManager with seed: ", game_settings.get_seed())
	else:
		print("Warning: SeedManager not found or GameSettings not available")

func _on_seed_manager_initialized() -> void:
	# SeedManager is now initialized, continue with the setup
	if game_settings:
		SeedManager.set_seed(game_settings.get_seed())
		
	# Continue initialization
	_preload_audio()
	_initialize_world_generator()
	_initialize_background_and_camera()
	_start_game_manager()

func _preload_audio() -> void:
	# Preload sound effects
	if has_node("/root/AudioManager"):
		AudioManager.preload_sfx("laser", "res://assets/audio/laser.sfxr", 20)  # Pool size of 20
		AudioManager.preload_sfx("explosion_debris", "res://assets/audio/explosion_debris.wav", 10)
		AudioManager.preload_sfx("explosion_fire", "res://assets/audio/explosion_fire.wav", 10)
		AudioManager.preload_sfx("missile", "res://assets/audio/missile.sfxr", 5)
		AudioManager.preload_sfx("thruster", "res://assets/audio/thruster.wav", 5)

func _initialize_world_generator() -> void:
	# Initialize world generator
	world_generator = WorldGenerator.new()
	add_child(world_generator)
	
	# Connect world generation signals
	if world_generator.has_signal("world_generation_completed"):
		world_generator.connect("world_generation_completed", _on_world_generation_completed)
	
	# Generate starter world
	if world_generator.has_method("generate_starter_world"):
		var planet_data = world_generator.generate_starter_world()
		
		# Store the starting planet information for GameManager
		if planet_data and planet_data.has("player_planet_cell") and planet_data.player_planet_cell != Vector2i(-1, -1):
			# Calculate world position
			player_start_cell = planet_data.player_planet_cell
			player_start_position = game_settings.get_cell_world_position(player_start_cell)
			
			if game_settings and game_settings.debug_mode:
				print("Main: Determined player start position at: ", player_start_position)
		else:
			# Fallback to grid center position if no planet was generated
			player_start_position = game_settings.get_player_starting_position()
	else:
		# Fallback if generate_starter_world doesn't exist
		print("WorldGenerator doesn't have generate_starter_world method")
		player_start_position = screen_size / 2

func _initialize_background_and_camera() -> void:
	# Initially position camera at the player start position
	camera.position = player_start_position
	
	# Register camera in group for background to find
	camera.add_to_group("camera")
	
	# Ensure space background is initialized
	if space_background:
		# Try to access initialized property
		var is_bg_initialized = false
		if "initialized" in space_background:
			is_bg_initialized = space_background.initialized
		
		if not is_bg_initialized:
			# Try to set game seed directly
			if "use_game_seed" in space_background:
				space_background.use_game_seed = true
			
			if has_node("/root/SeedManager") and "background_seed" in space_background:
				space_background.background_seed = SeedManager.get_seed()
			
			# Call setup_background if it exists
			if space_background.has_method("setup_background"):
				space_background.setup_background()

func _on_world_generation_completed() -> void:
	if game_settings and game_settings.debug_mode:
		print("Main: World generation completed")

func _start_game_manager() -> void:
	# Check if the GameManager autoload exists in the scene tree
	if has_node("/root/GameManager"):
		var game_manager = get_node("/root/GameManager")
		if game_manager.has_method("start_game"):
			# Configure game manager with our settings
			if game_settings and game_manager.has_method("configure_with_settings"):
				game_manager.configure_with_settings(game_settings)
				
				# Wait for any async operations to complete
				await get_tree().process_frame
			
			# Pass the player start position to GameManager
			if game_manager.has_method("set_player_start_position"):
				game_manager.set_player_start_position(player_start_position, player_start_cell)
			
			# Start the game
			game_manager.start_game()
		else:
			push_error("GameManager autoload found but doesn't have start_game method")
	else:
		if game_settings and game_settings.debug_mode:
			push_warning("GameManager autoload not found - standalone mode enabled")
			print("Available autoloads:")
			for child in get_node("/root").get_children():
				if child != get_tree().current_scene:
					print(" - " + child.name)

func _process(_delta: float) -> void:
	# Follow player with camera
	_update_camera_position()
	
	# Handle window resize events (if they occur)
	var current_size = get_viewport_rect().size
	if current_size != screen_size:
		screen_size = current_size
		if space_background and space_background.has_method("update_viewport_size"):
			space_background.update_viewport_size()

func _update_camera_position() -> void:
	# Get player from GameManager
	if has_node("/root/GameManager"):
		var game_manager = get_node("/root/GameManager")
		if game_manager.player_ship and is_instance_valid(game_manager.player_ship):
			camera.position = game_manager.player_ship.position
		elif player_start_position != Vector2.ZERO:
			# Fallback to start position if no player exists yet
			camera.position = player_start_position
	elif player_start_position != Vector2.ZERO:
		# Fallback to start position if GameManager not found
		camera.position = player_start_position
