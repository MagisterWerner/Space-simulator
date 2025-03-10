# scripts/main.gd
# Main scene controller that integrates all game systems
# Updated to use GameSettings for configuration and generate a starter world
extends Node2D

@onready var player_ship = $PlayerShip
@onready var camera = $Camera2D
@onready var space_background = $SpaceBackground
@onready var game_settings = $GameSettings

var screen_size: Vector2
var world_generator: WorldGenerator

func _ready() -> void:
	screen_size = get_viewport_rect().size
	
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
	world_generator.world_generation_completed.connect(_on_world_generation_completed)
	
	# Generate starter world
	var planet_data = world_generator.generate_starter_world()
	
	# Update player starting position to the lush planet
	if planet_data.lush_planet_cell != Vector2i(-1, -1):
		# Update settings
		game_settings.player_starting_cell = planet_data.lush_planet_cell
		
		# Calculate world position
		var lush_planet_position = game_settings.get_cell_world_position(planet_data.lush_planet_cell)
		
		# Position the player ship near the lush planet
		player_ship.position = lush_planet_position
		
		if game_settings and game_settings.debug_mode:
			print("Main: Positioned player at lush planet: ", lush_planet_position)
	else:
		# Fallback to screen center if no lush planet
		player_ship.position = screen_size / 2
	
	# Camera follows player
	camera.position = player_ship.position
	
	# Register camera in group for background to find
	camera.add_to_group("camera")
	
	# Ensure space background is initialized
	if space_background and not space_background.initialized:
		space_background.setup_background()
	
	# Start the game using GameManager if available
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
	# Follow player from GameManager if available, otherwise use local reference
	if has_node("/root/GameManager"):
		var game_manager = get_node("/root/GameManager")
		if game_manager.player_ship and is_instance_valid(game_manager.player_ship):
			camera.position = game_manager.player_ship.position
		else:
			camera.position = player_ship.position
	else:
		camera.position = player_ship.position
