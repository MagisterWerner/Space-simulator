# scripts/game_settings.gd
# =========================
# Purpose:
#   A comprehensive settings manager for the game
#   Centralizes all configurable aspects of the game in one place
#   Provides consistent access and validation for all game systems
extends Node
class_name GameSettings

# SIGNALS
signal settings_initialized
signal settings_saved
signal settings_loaded
signal setting_changed(category, key, value)
signal debug_settings_changed(debug_settings)
signal seed_changed(new_seed)

# CATEGORIES - Enum for organizing settings logically
enum SettingCategory {
	SEED,       # Seed and procedural generation
	WORLD,      # World generation and grid
	PLAYER,     # Player-related settings
	GAME,       # General game settings
	AUDIO,      # Audio settings
	GRAPHICS,   # Visual and graphical settings
	DEBUG       # Debug and development options
}

# Internal mapping of UI dropdown indices to PlanetTheme enum values
# This makes the relationship explicit and avoids off-by-one errors
const UI_TO_PLANET_TYPE = {
	0: -1,      # Random (special case)
	1: 0,       # Arid     = PlanetTheme.ARID
	2: 1,       # Ice      = PlanetTheme.ICE
	3: 2,       # Lava     = PlanetTheme.LAVA
	4: 3,       # Lush     = PlanetTheme.LUSH
	5: 4,       # Desert   = PlanetTheme.DESERT
	6: 5,       # Alpine   = PlanetTheme.ALPINE
	7: 6        # Ocean    = PlanetTheme.OCEAN
}

# ---- SEED SETTINGS ----
@export_group("Seed Settings")
## Main game seed that affects all procedural generation
@export var game_seed: int = 0:
	set(value):
		if game_seed != value:
			game_seed = value
			seed_hash = _generate_seed_hash(value)
			_notify_setting_changed(SettingCategory.SEED, "game_seed", value)
			seed_changed.emit(value)

## Whether to generate a random seed on game start
@export var use_random_seed: bool = true:
	set(value):
		if use_random_seed != value:
			use_random_seed = value
			_notify_setting_changed(SettingCategory.SEED, "use_random_seed", value)

## Hash of the seed for display/save purposes
var seed_hash: String = ""

# ---- WORLD SETTINGS ----
@export_group("World Settings")
## Size of each grid cell in pixels
@export var grid_cell_size: int = 1024:
	set(value):
		if grid_cell_size != value:
			grid_cell_size = value
			_notify_setting_changed(SettingCategory.WORLD, "grid_cell_size", value)

## Grid dimensions (cells per side, creating an NxN grid)
@export var grid_size: int = 10:
	set(value):
		if grid_size != value:
			grid_size = value
			_notify_setting_changed(SettingCategory.WORLD, "grid_size", value)

## Color of the grid lines
@export var grid_color: Color = Color.CYAN:
	set(value):
		if grid_color != value:
			grid_color = value
			_notify_setting_changed(SettingCategory.WORLD, "grid_color", value)

## Width of grid lines
@export var grid_line_width: float = 2.0:
	set(value):
		if grid_line_width != value:
			grid_line_width = value
			_notify_setting_changed(SettingCategory.WORLD, "grid_line_width", value)

## Opacity of grid lines (0.0-1.0)
@export var grid_opacity: float = 0.5:
	set(value):
		if grid_opacity != value:
			grid_opacity = clamp(value, 0.0, 1.0)
			_notify_setting_changed(SettingCategory.WORLD, "grid_opacity", value)

# ---- PLAYER SETTINGS ----
@export_group("Player Settings")
## Starting planet type for the player
@export_enum("Random", "Arid", "Ice", "Lava", "Lush", "Desert", "Alpine", "Ocean") 
var player_starting_planet_type: int = 0:
	set(value):
		if player_starting_planet_type != value:
			player_starting_planet_type = value
			_notify_setting_changed(SettingCategory.PLAYER, "player_starting_planet_type", value)

## Starting credits for the player
@export var player_starting_credits: int = 1000:
	set(value):
		if player_starting_credits != value:
			player_starting_credits = value
			_notify_setting_changed(SettingCategory.PLAYER, "player_starting_credits", value)

## Starting fuel for the player
@export var player_starting_fuel: int = 100:
	set(value):
		if player_starting_fuel != value:
			player_starting_fuel = value
			_notify_setting_changed(SettingCategory.PLAYER, "player_starting_fuel", value)

# ---- WORLD GENERATION SETTINGS ----
@export_group("World Generation")
## Number of terran planets to generate
@export var terran_planets: int = 5:
	set(value):
		if terran_planets != value:
			terran_planets = value
			_notify_setting_changed(SettingCategory.WORLD, "terran_planets", value)

## Number of gaseous planets to generate
@export var gaseous_planets: int = 1:
	set(value):
		if gaseous_planets != value:
			gaseous_planets = value
			_notify_setting_changed(SettingCategory.WORLD, "gaseous_planets", value)

## Number of asteroid fields to generate
@export var asteroid_fields: int = 0:
	set(value):
		if asteroid_fields != value:
			asteroid_fields = value
			_notify_setting_changed(SettingCategory.WORLD, "asteroid_fields", value)

## Number of space stations to generate
@export var space_stations: int = 0:
	set(value):
		if space_stations != value:
			space_stations = value
			_notify_setting_changed(SettingCategory.WORLD, "space_stations", value)

# ---- GAME SETTINGS ----
@export_group("Game Settings")
## Game difficulty level
@export_enum("Easy", "Normal", "Hard") var difficulty: int = 1:
	set(value):
		if difficulty != value:
			difficulty = value
			_notify_setting_changed(SettingCategory.GAME, "difficulty", value)

## Enable tutorial messages
@export var show_tutorials: bool = true:
	set(value):
		if show_tutorials != value:
			show_tutorials = value
			_notify_setting_changed(SettingCategory.GAME, "show_tutorials", value)

# ---- AUDIO SETTINGS ----
@export_group("Audio Settings")
## Master volume (0.0 - 1.0)
@export_range(0.0, 1.0, 0.01) var master_volume: float = 1.0:
	set(value):
		if master_volume != value:
			master_volume = clamp(value, 0.0, 1.0)
			_apply_audio_settings()
			_notify_setting_changed(SettingCategory.AUDIO, "master_volume", value)

## Music volume (0.0 - 1.0)
@export_range(0.0, 1.0, 0.01) var music_volume: float = 0.8:
	set(value):
		if music_volume != value:
			music_volume = clamp(value, 0.0, 1.0)
			_apply_audio_settings()
			_notify_setting_changed(SettingCategory.AUDIO, "music_volume", value)

## Sound effects volume (0.0 - 1.0)
@export_range(0.0, 1.0, 0.01) var sfx_volume: float = 1.0:
	set(value):
		if sfx_volume != value:
			sfx_volume = clamp(value, 0.0, 1.0)
			_apply_audio_settings()
			_notify_setting_changed(SettingCategory.AUDIO, "sfx_volume", value)

## Enable positional audio
@export var positional_audio: bool = true:
	set(value):
		if positional_audio != value:
			positional_audio = value
			_apply_audio_settings()
			_notify_setting_changed(SettingCategory.AUDIO, "positional_audio", value)

# ---- GRAPHICS SETTINGS ----
@export_group("Graphics Settings")
## Enable visual effects
@export var visual_effects: bool = true:
	set(value):
		if visual_effects != value:
			visual_effects = value
			_notify_setting_changed(SettingCategory.GRAPHICS, "visual_effects", value)

## Particle system density (0.0 - 1.0)
@export_range(0.0, 1.0, 0.1) var particle_density: float = 1.0:
	set(value):
		if particle_density != value:
			particle_density = clamp(value, 0.0, 1.0)
			_notify_setting_changed(SettingCategory.GRAPHICS, "particle_density", value)

## Enable screen shake
@export var screen_shake: bool = true:
	set(value):
		if screen_shake != value:
			screen_shake = value
			_notify_setting_changed(SettingCategory.GRAPHICS, "screen_shake", value)

# ---- DEBUG SETTINGS ----
@export_group("Debug")
## Master toggle for all debug features
@export var debug_mode: bool = false:
	set(value):
		if debug_mode != value:
			debug_mode = value
			_update_debug_settings()
			_notify_setting_changed(SettingCategory.DEBUG, "debug_mode", value)

## Specific debug systems (only active when debug_mode is true)
@export_subgroup("Debug Systems")

## Enable detailed logging
@export var debug_logging: bool = false:
	set(value):
		if debug_logging != value:
			debug_logging = value
			_update_debug_settings()
			_notify_setting_changed(SettingCategory.DEBUG, "debug_logging", value)

## Draw debug grid
@export var debug_grid: bool = false:
	set(value):
		if debug_grid != value:
			debug_grid = value
			_update_debug_settings()
			_notify_setting_changed(SettingCategory.DEBUG, "debug_grid", value)

## Enable seed manager debugging
@export var debug_seed_manager: bool = false:
	set(value):
		if debug_seed_manager != value:
			debug_seed_manager = value
			_update_debug_settings()
			_notify_setting_changed(SettingCategory.DEBUG, "debug_seed_manager", value)

## Enable world generator debugging
@export var debug_world_generator: bool = false:
	set(value):
		if debug_world_generator != value:
			debug_world_generator = value
			_update_debug_settings()
			_notify_setting_changed(SettingCategory.DEBUG, "debug_world_generator", value)

## Enable entity generation debugging
@export var debug_entity_generation: bool = false:
	set(value):
		if debug_entity_generation != value:
			debug_entity_generation = value
			_update_debug_settings()
			_notify_setting_changed(SettingCategory.DEBUG, "debug_entity_generation", value)

## Enable physics debugging
@export var debug_physics: bool = false:
	set(value):
		if debug_physics != value:
			debug_physics = value
			_update_debug_settings()
			_notify_setting_changed(SettingCategory.DEBUG, "debug_physics", value)

## Enable UI debugging
@export var debug_ui: bool = false:
	set(value):
		if debug_ui != value:
			debug_ui = value
			_update_debug_settings()
			_notify_setting_changed(SettingCategory.DEBUG, "debug_ui", value)

## Enable component system debugging
@export var debug_components: bool = false:
	set(value):
		if debug_components != value:
			debug_components = value
			_update_debug_settings()
			_notify_setting_changed(SettingCategory.DEBUG, "debug_components", value)

# ---- INTERNAL VARIABLES ----
var _initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _debug_settings: Dictionary = {}

func _ready() -> void:
	# Initialize seed if needed
	_initialize_seed()
	
	# Initialize debug settings dictionary
	_initialize_debug_settings()
	
	# Log settings if debug mode is on
	if debug_mode:
		print("GameSettings initialized with seed: ", game_seed)
		print("Grid size: ", grid_size, "x", grid_size, " (", grid_cell_size, " pixels per cell)")
		print("Player starting planet type: ", get_planet_type_description())
	
	_initialized = true
	settings_initialized.emit()
	
	# Apply initial debug settings
	_update_debug_settings()
	
	# Apply initial audio settings
	_apply_audio_settings()

# ---- SEED MANAGEMENT ----

func _initialize_seed() -> void:
	if use_random_seed or game_seed == 0:
		_generate_deterministic_random_seed()
	else:
		# Use the provided seed
		seed_hash = _generate_seed_hash(game_seed)

func get_seed() -> int:
	return game_seed

func set_seed(new_seed: int) -> void:
	# Use the property setter to trigger signals
	game_seed = new_seed
	use_random_seed = false

# Deterministic random seed generation
func _generate_deterministic_random_seed() -> void:
	# Use time-based seed but make it more deterministic
	var current_time = Time.get_unix_time_from_system()
	var new_seed = int(current_time * 1000) % 1000000
	set_seed(new_seed)
	use_random_seed = true
	
	if debug_mode:
		print("GameSettings: Generated deterministic random seed: ", new_seed)

# Generate a readable hash string from the seed
func _generate_seed_hash(seed_value: int) -> String:
	# Convert to a 6-character alphanumeric hash
	var characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # Omitting similar characters
	var hash_string = ""
	var temp_seed = seed_value
	
	for i in range(6):
		var index = temp_seed % characters.length()
		hash_string += characters[index]
		# Use float division to avoid integer division
		temp_seed = int(temp_seed / float(characters.length()))
	
	return hash_string

# ---- DEBUG SETTINGS MANAGEMENT ----

func _initialize_debug_settings() -> void:
	_debug_settings = {
		"master": debug_mode,
		"logging": debug_logging,
		"grid": debug_grid,
		"seed_manager": debug_seed_manager,
		"world_generator": debug_world_generator, 
		"entity_generation": debug_entity_generation,
		"physics": debug_physics,
		"ui": debug_ui,
		"components": debug_components
	}

func _update_debug_settings() -> void:
	# Update debug settings dictionary
	_debug_settings = {
		"master": debug_mode,
		"logging": debug_logging,
		"grid": debug_grid,
		"seed_manager": debug_seed_manager,
		"world_generator": debug_world_generator,
		"entity_generation": debug_entity_generation,
		"physics": debug_physics,
		"ui": debug_ui,
		"components": debug_components
	}
	
	# Update SeedManager if available
	if Engine.has_singleton("SeedManager"):
		SeedManager.set_debug_mode(debug_mode and debug_seed_manager)
	
	# Emit signal with all current debug settings
	debug_settings_changed.emit(_debug_settings)

# ---- AUDIO SETTINGS MANAGEMENT ----

func _apply_audio_settings() -> void:
	if not _initialized:
		return
		
	if has_node("/root/AudioManager"):
		var audio_manager = get_node("/root/AudioManager")
		
		# Wait for initialization if needed
		if audio_manager.has_method("is_initialized"):
			if not audio_manager.is_initialized():
				await audio_manager.audio_buses_initialized
		
		# Apply volume settings
		if audio_manager.has_method("set_master_volume"):
			audio_manager.set_master_volume(master_volume)
			
		if audio_manager.has_method("set_music_volume"):
			audio_manager.set_music_volume(music_volume)
			
		if audio_manager.has_method("set_sfx_volume"):
			audio_manager.set_sfx_volume(sfx_volume)
			
		# Apply positional audio setting
		if audio_manager.has_method("set_positional_audio"):
			audio_manager.set_positional_audio(positional_audio)

# ---- SETTING CHANGE NOTIFICATION ----

func _notify_setting_changed(category: int, key: String, value) -> void:
	if not _initialized:
		return
		
	# Emit general setting changed signal
	setting_changed.emit(category, key, value)

# ---- GRID POSITION HELPERS ----

# Get the starting position for the player in world coordinates
func get_player_starting_position() -> Vector2:
	# Player starts near the center of the grid
	var center_cell = Vector2i(int(grid_size / 2.0), int(grid_size / 2.0))
	return get_cell_world_position(center_cell)

# Convert grid cell coordinates to world position (center of cell)
func get_cell_world_position(cell_coords: Vector2i) -> Vector2:
	var grid_center = Vector2(grid_cell_size * grid_size / 2.0, grid_cell_size * grid_size / 2.0)
	var cell_position = Vector2(
		cell_coords.x * grid_cell_size + grid_cell_size / 2.0,
		cell_coords.y * grid_cell_size + grid_cell_size / 2.0
	)
	return cell_position - grid_center

# Convert world position to grid cell coordinates
func get_cell_coords(world_position: Vector2) -> Vector2i:
	var grid_center = Vector2(grid_cell_size * grid_size / 2.0, grid_cell_size * grid_size / 2.0)
	var local_pos = world_position + grid_center
	
	var cell_x = int(floor(local_pos.x / grid_cell_size))
	var cell_y = int(floor(local_pos.y / grid_cell_size))
	
	return Vector2i(cell_x, cell_y)

# Check if a cell is valid (within grid bounds)
func is_valid_cell(cell_coords: Vector2i) -> bool:
	return (
		cell_coords.x >= 0 and cell_coords.x < grid_size and
		cell_coords.y >= 0 and cell_coords.y < grid_size
	)

# ---- PLANET TYPE METHODS ----

# Check if player planet type should be random
func is_random_player_planet() -> bool:
	return player_starting_planet_type == 0  # 0 = Random

# Get the effective planet type (accounting for Random selection)
# This now properly maps UI values to PlanetTheme enum values
# UI indices: 0=Random, 1=Arid, 2=Ice, 3=Lava, etc.
# PlanetTheme enum: 0=ARID, 1=ICE, 2=LAVA, etc.
func get_effective_planet_type(seed_value: int = 0) -> int:
	if is_random_player_planet():
		# Generate a random planet type based on seed
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value if seed_value != 0 else game_seed
		return rng.randi_range(0, 6)  # 0-6 for the 7 planet types
	else:
		# Use the explicit mapping for UI-to-enum conversion
		# This ensures we always get the right enum value
		var planet_type = UI_TO_PLANET_TYPE.get(player_starting_planet_type, 0)
		
		# Validate planet type is in valid range
		if planet_type < 0 or planet_type > 6:
			push_warning("Invalid planet type selected: " + str(player_starting_planet_type))
			return 0  # Default to ARID if invalid
			
		return planet_type

# Get a description of the selected planet type for debugging
func get_planet_type_description() -> String:
	if is_random_player_planet():
		return "Random (seed-based)"
	else:
		return get_planet_type_name(get_effective_planet_type())

# Get planet type name from index
func get_planet_type_name(type_index: int) -> String:
	match type_index:
		0: return "Arid"
		1: return "Ice"
		2: return "Lava"
		3: return "Lush"
		4: return "Desert"
		5: return "Alpine"
		6: return "Ocean"
		_: return "Unknown"

# ---- DETERMINISTIC RANDOMIZATION ----

# Get a deterministic random value for an object ID
func get_random_value(object_id: int, min_val: float, max_val: float, object_subid: int = 0) -> float:
	# Create seed based on game seed and object ID
	_rng.seed = _hash_combine(game_seed, object_id + object_subid)
	return min_val + _rng.randf() * (max_val - min_val)

# Get a deterministic random integer
func get_random_int(object_id: int, min_val: int, max_val: int, object_subid: int = 0) -> int:
	# Create seed based on game seed and object ID
	_rng.seed = _hash_combine(game_seed, object_id + object_subid)
	return _rng.randi_range(min_val, max_val)

# Get a deterministic position within a circle
func get_random_point_in_circle(object_id: int, radius: float, object_subid: int = 0) -> Vector2:
	# Create seed based on game seed and object ID
	_rng.seed = _hash_combine(game_seed, object_id + object_subid)
	var angle = _rng.randf() * TAU
	var distance = sqrt(_rng.randf()) * radius  # Square root for uniform distribution
	return Vector2(cos(angle) * distance, sin(angle) * distance)

# Helper function to combine seed and object ID into a new hash
func _hash_combine(seed_value: int, object_id: int) -> int:
	return ((seed_value << 5) + seed_value) ^ object_id

# ---- DEBUG API ----

# Set a debug option by name
func set_debug_option(option_name: String, value: bool) -> void:
	# Convert from system name to property name if needed
	var property_name = "debug_" + option_name
	if option_name == "master":
		property_name = "debug_mode"
	elif option_name == "grid":
		property_name = "debug_grid"
	
	# Only set if property exists
	if has_property(self, property_name):
		set(property_name, value)

# Get debug status for a system
func get_debug_status(system_name: String) -> bool:
	# First check if we have this in our settings dictionary
	if _debug_settings.has(system_name):
		# Debug is on only if both master and specific toggle are on
		return debug_mode and _debug_settings[system_name]
	
	# Handle special cases
	if system_name == "master":
		return debug_mode
	elif system_name == "grid":
		return debug_mode and debug_grid
	
	# Default to false for unknown systems
	return false

# Helper function to check if an object has a property
static func has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false

# ---- SAVE & LOAD SETTINGS ----

# Save settings to file
func save_settings(filepath: String = "user://game_settings.cfg") -> bool:
	var config = ConfigFile.new()
	
	# Save seed settings
	config.set_value("seed", "game_seed", game_seed)
	config.set_value("seed", "use_random_seed", use_random_seed)
	
	# Save world settings
	config.set_value("world", "grid_cell_size", grid_cell_size)
	config.set_value("world", "grid_size", grid_size)
	config.set_value("world", "grid_color", grid_color)
	config.set_value("world", "grid_line_width", grid_line_width)
	config.set_value("world", "grid_opacity", grid_opacity)
	config.set_value("world", "terran_planets", terran_planets)
	config.set_value("world", "gaseous_planets", gaseous_planets)
	config.set_value("world", "asteroid_fields", asteroid_fields)
	config.set_value("world", "space_stations", space_stations)
	
	# Save player settings
	config.set_value("player", "player_starting_planet_type", player_starting_planet_type)
	config.set_value("player", "player_starting_credits", player_starting_credits)
	config.set_value("player", "player_starting_fuel", player_starting_fuel)
	
	# Save game settings
	config.set_value("game", "difficulty", difficulty)
	config.set_value("game", "show_tutorials", show_tutorials)
	
	# Save audio settings
	config.set_value("audio", "master_volume", master_volume)
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("audio", "positional_audio", positional_audio)
	
	# Save graphics settings
	config.set_value("graphics", "visual_effects", visual_effects)
	config.set_value("graphics", "particle_density", particle_density)
	config.set_value("graphics", "screen_shake", screen_shake)
	
	# Save debug settings
	config.set_value("debug", "debug_mode", debug_mode)
	config.set_value("debug", "debug_logging", debug_logging)
	config.set_value("debug", "debug_grid", debug_grid)
	config.set_value("debug", "debug_seed_manager", debug_seed_manager)
	config.set_value("debug", "debug_world_generator", debug_world_generator)
	config.set_value("debug", "debug_entity_generation", debug_entity_generation)
	config.set_value("debug", "debug_physics", debug_physics)
	config.set_value("debug", "debug_ui", debug_ui)
	config.set_value("debug", "debug_components", debug_components)
	
	# Save to file
	var error = config.save(filepath)
	if error != OK:
		if debug_mode and debug_logging:
			print("Error saving settings: ", error)
		return false
	
	settings_saved.emit()
	return true

# Load settings from file
func load_settings(filepath: String = "user://game_settings.cfg") -> bool:
	var config = ConfigFile.new()
	var error = config.load(filepath)
	
	if error != OK:
		if debug_mode and debug_logging:
			print("Error loading settings: ", error)
		return false
	
	# Load seed settings
	if config.has_section_key("seed", "game_seed"):
		game_seed = config.get_value("seed", "game_seed")
	if config.has_section_key("seed", "use_random_seed"):
		use_random_seed = config.get_value("seed", "use_random_seed")
	
	# Load world settings
	if config.has_section_key("world", "grid_cell_size"):
		grid_cell_size = config.get_value("world", "grid_cell_size")
	if config.has_section_key("world", "grid_size"):
		grid_size = config.get_value("world", "grid_size")
	if config.has_section_key("world", "grid_color"):
		grid_color = config.get_value("world", "grid_color")
	if config.has_section_key("world", "grid_line_width"):
		grid_line_width = config.get_value("world", "grid_line_width")
	if config.has_section_key("world", "grid_opacity"):
		grid_opacity = config.get_value("world", "grid_opacity")
	if config.has_section_key("world", "terran_planets"):
		terran_planets = config.get_value("world", "terran_planets")
	if config.has_section_key("world", "gaseous_planets"):
		gaseous_planets = config.get_value("world", "gaseous_planets")
	if config.has_section_key("world", "asteroid_fields"):
		asteroid_fields = config.get_value("world", "asteroid_fields")
	if config.has_section_key("world", "space_stations"):
		space_stations = config.get_value("world", "space_stations")
	
	# Load player settings
	if config.has_section_key("player", "player_starting_planet_type"):
		player_starting_planet_type = config.get_value("player", "player_starting_planet_type")
	if config.has_section_key("player", "player_starting_credits"):
		player_starting_credits = config.get_value("player", "player_starting_credits")
	if config.has_section_key("player", "player_starting_fuel"):
		player_starting_fuel = config.get_value("player", "player_starting_fuel")
	
	# Load game settings
	if config.has_section_key("game", "difficulty"):
		difficulty = config.get_value("game", "difficulty")
	if config.has_section_key("game", "show_tutorials"):
		show_tutorials = config.get_value("game", "show_tutorials")
	
	# Load audio settings
	if config.has_section_key("audio", "master_volume"):
		master_volume = config.get_value("audio", "master_volume")
	if config.has_section_key("audio", "music_volume"):
		music_volume = config.get_value("audio", "music_volume")
	if config.has_section_key("audio", "sfx_volume"):
		sfx_volume = config.get_value("audio", "sfx_volume")
	if config.has_section_key("audio", "positional_audio"):
		positional_audio = config.get_value("audio", "positional_audio")
	
	# Load graphics settings
	if config.has_section_key("graphics", "visual_effects"):
		visual_effects = config.get_value("graphics", "visual_effects")
	if config.has_section_key("graphics", "particle_density"):
		particle_density = config.get_value("graphics", "particle_density")
	if config.has_section_key("graphics", "screen_shake"):
		screen_shake = config.get_value("graphics", "screen_shake")
	
	# Load debug settings
	if config.has_section_key("debug", "debug_mode"):
		debug_mode = config.get_value("debug", "debug_mode")
	if config.has_section_key("debug", "debug_logging"):
		debug_logging = config.get_value("debug", "debug_logging")
	if config.has_section_key("debug", "debug_grid"):
		debug_grid = config.get_value("debug", "debug_grid")
	if config.has_section_key("debug", "debug_seed_manager"):
		debug_seed_manager = config.get_value("debug", "debug_seed_manager")
	if config.has_section_key("debug", "debug_world_generator"):
		debug_world_generator = config.get_value("debug", "debug_world_generator")
	if config.has_section_key("debug", "debug_entity_generation"):
		debug_entity_generation = config.get_value("debug", "debug_entity_generation")
	if config.has_section_key("debug", "debug_physics"):
		debug_physics = config.get_value("debug", "debug_physics")
	if config.has_section_key("debug", "debug_ui"):
		debug_ui = config.get_value("debug", "debug_ui")
	if config.has_section_key("debug", "debug_components"):
		debug_components = config.get_value("debug", "debug_components")
	
	# Apply settings
	_update_debug_settings()
	_apply_audio_settings()
	
	settings_loaded.emit()
	return true

# Reset settings to defaults
func reset_to_defaults() -> void:
	# Reset to inspector defaults
	game_seed = 0
	use_random_seed = true
	
	grid_cell_size = 1024
	grid_size = 10
	grid_color = Color.CYAN
	grid_line_width = 2.0
	grid_opacity = 0.5
	
	player_starting_planet_type = 0
	player_starting_credits = 1000
	player_starting_fuel = 100
	
	terran_planets = 5
	gaseous_planets = 1
	asteroid_fields = 0
	space_stations = 0
	
	difficulty = 1
	show_tutorials = true
	
	master_volume = 1.0
	music_volume = 0.8
	sfx_volume = 1.0
	positional_audio = true
	
	visual_effects = true
	particle_density = 1.0
	screen_shake = true
	
	debug_mode = false
	debug_logging = false
	debug_grid = false
	debug_seed_manager = false
	debug_world_generator = false
	debug_entity_generation = false
	debug_physics = false
	debug_ui = false
	debug_components = false
	
	# Generate a new seed
	_generate_deterministic_random_seed()
	
	# Apply settings
	_update_debug_settings()
	_apply_audio_settings()
