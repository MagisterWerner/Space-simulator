# scripts/main.gd
# Main scene controller that integrates all game systems
# Updated to let GameManager handle player creation and positioning
extends Node2D

@onready var camera = $Camera2D
@onready var space_background = $SpaceBackground
@onready var game_settings = $GameSettings

var screen_size: Vector2
var world_generator = null
var player_start_position: Vector2 = Vector2.ZERO
var player_start_cell: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	screen_size = get_viewport_rect().size
	# In your main game scene or initialization code
	AudioManager.preload_sfx("laser", "res://assets/audio/laser.sfxr", 20)  # Pool size of 20
	AudioManager.preload_sfx("explosion_debris", "res://assets/audio/explosion_debris.wav", 10)
	AudioManager.preload_sfx("explosion_fire", "res://assets/audio/explosion_fire.wav", 10)
	AudioManager.preload_sfx("missile", "res://assets/audio/missile.sfxr", 5)
	AudioManager.preload_sfx("thruster", "res://assets/audio/thruster.wav", 5)

	# Wait for game settings to initialize if needed
	if game_settings and not game_settings.is_connected("settings_initialized", _on_game_settings_initialized):
		if not game_settings._initialized:
			game_settings.settings_initialized.connect(_on_game_settings_initialized)
			return
	
	# If settings already initialized or not available, initialize directly
	_initialize_game()

func _on_game_settings_initialized() -> void:
	_initialize_game()

func _initialize_game() -> void:
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
	
	# Initially position camera at the player start position
	camera.position = player_start_position
	
	# Register camera in group for background to find
	camera.add_to_group("camera")
	
	# Ensure space background is initialized
	if space_background and not space_background.initialized:
		space_background.setup_background()
	
	# Start the game using GameManager
	_start_game_manager()

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
		if space_background:
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
