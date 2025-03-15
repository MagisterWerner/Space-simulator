# scripts/main.gd
# Main scene controller that integrates all game systems
# Updated to include pre-generation systems
extends Node2D

@onready var camera = $Camera2D
@onready var space_background = $SpaceBackground
@onready var game_settings = $GameSettings

var screen_size: Vector2
var player_start_position: Vector2 = Vector2.ZERO
var player_start_cell: Vector2i = Vector2i(-1, -1)
var initialization_complete = false

# Pre-generation managers
var fragment_pool_manager = null
var projectile_pool_manager = null
var effect_pool_manager = null
var content_registry = null

# Initialization tracking
var _systems_loaded = {
	"seed": false,
	"fragment_pool": false,
	"projectile_pool": false,
	"effect_pool": false,
	"content_registry": false,
	"audio": false,
	"world": false
}

func _ready() -> void:
	# Create pre-generation systems first
	_create_pre_generation_systems()
	
	screen_size = get_viewport_rect().size
	
	# Wait for game settings to initialize if needed
	if game_settings and not game_settings.is_connected("settings_initialized", _on_game_settings_initialized):
		if not game_settings._initialized:
			game_settings.connect("settings_initialized", _on_game_settings_initialized)
			return
	
	# If settings already initialized or not available, initialize directly
	_initialize_game()

func _create_pre_generation_systems() -> void:
	# Create content registry
	if not content_registry:
		content_registry = ContentRegistry.new()
		content_registry.name = "ContentRegistry"
		add_child(content_registry)
		content_registry.connect("content_loaded", _on_content_loaded)
	
	# Create fragment pool manager
	if not fragment_pool_manager:
		fragment_pool_manager = FragmentPoolManager.new()
		fragment_pool_manager.name = "FragmentPoolManager"
		add_child(fragment_pool_manager)
		fragment_pool_manager.connect("pools_initialized", _on_fragment_pools_initialized)
	
	# Create projectile pool manager
	if not projectile_pool_manager:
		projectile_pool_manager = ProjectilePoolManager.new()
		projectile_pool_manager.name = "ProjectilePoolManager"
		add_child(projectile_pool_manager)
		projectile_pool_manager.connect("pools_initialized", _on_projectile_pools_initialized)
	
	# Create effect pool manager
	if not effect_pool_manager:
		effect_pool_manager = EffectPoolManager.new()
		effect_pool_manager.name = "EffectPoolManager"
		add_child(effect_pool_manager)
		effect_pool_manager.connect("pools_initialized", _on_effect_pools_initialized)

func _on_content_loaded() -> void:
	_systems_loaded.content_registry = true
	_check_all_systems_loaded()

func _on_fragment_pools_initialized() -> void:
	_systems_loaded.fragment_pool = true
	_check_all_systems_loaded()

func _on_projectile_pools_initialized() -> void:
	_systems_loaded.projectile_pool = true
	_check_all_systems_loaded()

func _on_effect_pools_initialized() -> void:
	_systems_loaded.effect_pool = true
	_check_all_systems_loaded()

func _on_game_settings_initialized() -> void:
	_initialize_game()

func _initialize_game() -> void:
	# Ensure we only initialize once
	if initialization_complete:
		return
	
	# Ensure seed is properly set first
	_initialize_seed()
	
	# Preload sound effects after seed is established
	_preload_audio()
	
	# Initialize background and camera
	_initialize_background_and_camera()
	
	# Configure the WorldManager with settings
	_configure_world_manager()
	
	# Wait for other systems to be ready before starting the game
	_check_all_systems_loaded()

func _check_all_systems_loaded() -> void:
	# Check if all required systems are loaded
	var all_loaded = true
	for system in _systems_loaded:
		if not _systems_loaded[system]:
			all_loaded = false
			break
	
	# Start the game if all systems are loaded
	if all_loaded:
		initialization_complete = true
		_start_game_manager()
		
		if game_settings and game_settings.debug_mode:
			print("Main: All pre-generation systems initialized")

func _initialize_seed() -> void:
	# Make sure SeedManager gets the correct seed from GameSettings
	if has_node("/root/SeedManager") and game_settings:
		# Wait for SeedManager to be initialized if necessary
		if "is_initialized" in SeedManager and not SeedManager.is_initialized:
			if SeedManager.has_signal("seed_initialized"):
				SeedManager.connect("seed_initialized", _on_seed_manager_initialized)
				return
		
		# Set the seed in SeedManager - important for world generation
		SeedManager.set_seed(game_settings.get_seed())
		
		if game_settings.debug_mode:
			print("Main: Initialized SeedManager with seed: ", game_settings.get_seed())
		
		_systems_loaded.seed = true
	else:
		print("Warning: SeedManager not found or GameSettings not available")
		_systems_loaded.seed = true  # Mark as loaded anyway to continue

func _on_seed_manager_initialized() -> void:
	# Check if we've already completed initialization
	if initialization_complete:
		# Just update the seed and return
		if game_settings:
			SeedManager.set_seed(game_settings.get_seed())
		return
	
	# SeedManager is now initialized, set the seed
	if game_settings:
		SeedManager.set_seed(game_settings.get_seed())
	
	_systems_loaded.seed = true
	_check_all_systems_loaded()

func _preload_audio() -> void:
	# Preload sound effects
	if has_node("/root/AudioManager"):
		AudioManager.preload_sfx("laser", "res://assets/audio/laser.sfxr", 20)  # Pool size of 20
		AudioManager.preload_sfx("explosion_debris", "res://assets/audio/explosion_debris.wav", 10)
		AudioManager.preload_sfx("explosion_fire", "res://assets/audio/explosion_fire.wav", 10)
		AudioManager.preload_sfx("missile", "res://assets/audio/missile.sfxr", 5)
		AudioManager.preload_sfx("thruster", "res://assets/audio/thruster.wav", 5)
		
		# Wait for audio to be initialized
		if not AudioManager.is_initialized():
			AudioManager.audio_buses_initialized.connect(_on_audio_initialized)
		else:
			_systems_loaded.audio = true
			_check_all_systems_loaded()
	else:
		_systems_loaded.audio = true  # Mark as loaded anyway to continue

func _on_audio_initialized() -> void:
	_systems_loaded.audio = true
	_check_all_systems_loaded()

func _configure_world_manager() -> void:
	# Configure WorldManager with settings from GameSettings
	if has_node("/root/WorldManager") and game_settings:
		WorldManager.cell_size = game_settings.grid_cell_size
		WorldManager.grid_size = game_settings.grid_size
		
		# Connect to WorldManager signals
		if WorldManager.has_signal("world_generation_completed"):
			WorldManager.connect("world_generation_completed", _on_world_generation_completed)
		
		_systems_loaded.world = true
	else:
		_systems_loaded.world = true  # Mark as loaded anyway to continue

func _initialize_background_and_camera() -> void:
	# Initially position camera at the player start position
	if player_start_position != Vector2.ZERO:
		camera.position = player_start_position
	else:
		# Determine initial player position
		if game_settings:
			player_start_position = game_settings.get_player_starting_position()
			player_start_cell = WorldManager.world_to_cell(player_start_position)
		else:
			player_start_position = screen_size / 2
			
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
