# scripts/game_settings.gd
# =========================
# Purpose:
#   Centralized configuration node for all game-wide settings
#   Handles seed management, grid configuration, planet generation
#   Provides consistent access to game parameters for all systems

extends Node
class_name GameSettings

signal settings_initialized
signal seed_changed(new_seed)
signal debug_settings_changed(debug_settings)

# ---- SEED SETTINGS ----
@export_category("Seed Settings")
## Main game seed that affects all procedural generation
@export var game_seed: int = 0
## Whether to generate a random seed on game start
@export var use_random_seed: bool = true 
## Hash of the seed for display/save purposes
var seed_hash: String = ""

# ---- GRID SETTINGS ----
@export_category("Grid Settings")
## Size of each grid cell in pixels
@export var grid_cell_size: int = 1024
## Grid dimensions (cells per side, creating an NxN grid)
@export var grid_size: int = 10
## Color of the grid lines
@export var grid_color: Color = Color.CYAN
## Width of grid lines
@export var grid_line_width: float = 2.0
## Opacity of grid lines (0.0-1.0)
@export var grid_opacity: float = 0.5

# ---- PLAYER SETTINGS ----
@export_category("Player Settings")
## Starting planet type for the player - added "Random" option
@export_enum("Random", "Arid", "Ice", "Lava", "Lush", "Desert", "Alpine", "Ocean") 
var player_starting_planet_type: int = 0  # Default to Random (index 0)
## Starting credits for the player
@export var player_starting_credits: int = 1000
## Starting fuel for the player
@export var player_starting_fuel: int = 100

# ---- WORLD GENERATION ----
@export_category("World Generation")
## Number of terran planets to generate
@export var terran_planets: int = 5
## Number of gaseous planets to generate
@export var gaseous_planets: int = 1
## Number of asteroid fields to generate
@export var asteroid_fields: int = 0
## Number of space stations to generate
@export var space_stations: int = 0

# ---- DEBUG OPTIONS ----
@export_category("Debug Options")
## Enable debug output and visualizations (master toggle)
@export var debug_mode: bool = false
## Draw additional debug info for generation
@export var draw_debug_grid: bool = false
## Show debug panel
@export var debug_panel: bool = false:
	set(value):
		debug_panel = value
		_notify_debug_change("panel", value)
		_update_debug_panel_visibility()

# ---- DETAILED DEBUG OPTIONS ----
@export_category("Detailed Debug Options")
## Enable SeedManager debug logging
@export var debug_seed_manager: bool = false:
	set(value):
		debug_seed_manager = value
		_notify_debug_change("seed_manager", value)

## Enable world generator debug
@export var debug_world_generator: bool = false:
	set(value):
		debug_world_generator = value
		_notify_debug_change("world_generator", value)

## Enable entity generation debug visualization
@export var debug_entity_generation: bool = false:
	set(value):
		debug_entity_generation = value
		_notify_debug_change("entity_generation", value)

## Enable physics debug visualization
@export var debug_physics: bool = false:
	set(value):
		debug_physics = value
		_notify_debug_change("physics", value)

## Enable UI debug information
@export var debug_ui: bool = false:
	set(value):
		debug_ui = value
		_notify_debug_change("ui", value)

## Enable component system debug
@export var debug_components: bool = false:
	set(value):
		debug_components = value
		_notify_debug_change("components", value)

## Enable detailed error logging
@export var debug_logging: bool = false:
	set(value):
		debug_logging = value
		_notify_debug_change("logging", value)

# ---- INTERNAL VARIABLES ----
var _initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _debug_settings: Dictionary = {}
var _debug_panel = null

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
	_apply_debug_settings()
	
	# Setup debug panel if needed
	call_deferred("_setup_debug_panel")

# Initialize debug settings dictionary
func _initialize_debug_settings() -> void:
	_debug_settings = {
		"master": debug_mode,
		"grid": draw_debug_grid,
		"panel": debug_panel,
		"seed_manager": debug_seed_manager,
		"world_generator": debug_world_generator,
		"entity_generation": debug_entity_generation,
		"physics": debug_physics,
		"ui": debug_ui,
		"components": debug_components,
		"logging": debug_logging
	}

# Apply debug settings to systems
func _apply_debug_settings() -> void:
	# Update SeedManager
	if Engine.has_singleton("SeedManager"):
		SeedManager.set_debug_mode(debug_mode and debug_seed_manager)
	
	# Update debug panel visibility
	_update_debug_panel_visibility()
	
	# Emit signal with all current debug settings
	debug_settings_changed.emit(_debug_settings)

# Set up debug panel
func _setup_debug_panel() -> void:
	# Find or create a CanvasLayer for the debug panel
	var debug_canvas = get_node_or_null("/root/DebugCanvas")
	
	if not debug_canvas:
		# FIX: Add check for Engine.get_main_loop()
		var main_loop = Engine.get_main_loop()
		if main_loop != null:
			debug_canvas = CanvasLayer.new()
			debug_canvas.name = "DebugCanvas"
			debug_canvas.layer = 100  # Put it on top
			main_loop.root.add_child(debug_canvas)
		else:
			push_warning("GameSettings: Cannot create DebugCanvas, Engine.get_main_loop() is null")
			return
	
	# Load debug panel scene if it exists
	var debug_panel_path = "res://scenes/ui/debug_panel.tscn"
	if ResourceLoader.exists(debug_panel_path):
		var debug_panel_scene = load(debug_panel_path)
		_debug_panel = debug_panel_scene.instantiate()
		_debug_panel.name = "DebugPanel"
		debug_canvas.add_child(_debug_panel)
		
		# Set initial visibility
		_update_debug_panel_visibility()
	
	# Register keyboard shortcut for toggling panel
	set_process_input(true)

# Input handling for debug panel toggle
func _input(event: InputEvent) -> void:
	# Toggle debug panel with F3 key
	if OS.is_debug_build() and event is InputEventKey:
		if event.pressed and event.keycode == KEY_F3:
			debug_panel = !debug_panel

# Update the debug panel visibility
func _update_debug_panel_visibility() -> void:
	# Find debug panel if we don't have a reference
	if not _debug_panel:
		# FIX: Add check for Engine.get_main_loop()
		var main_loop = Engine.get_main_loop()
		if main_loop != null:
			_debug_panel = main_loop.root.find_child("DebugPanel", true, false)
		else:
			return
	
	# Update visibility if we found it
	if _debug_panel:
		_debug_panel.visible = debug_panel
		print("Debug panel visibility: " + str(debug_panel))

# Notify systems when a specific debug setting changes
func _notify_debug_change(setting_name: String, value: bool) -> void:
	if not _initialized:
		return
		
	# Update the debug settings dictionary
	_debug_settings[setting_name] = value
	
	# Special handling for certain systems
	if setting_name == "seed_manager" and Engine.has_singleton("SeedManager"):
		SeedManager.set_debug_mode(debug_mode and value)
	
	# Notify all systems about the changes
	debug_settings_changed.emit(_debug_settings)

# Set a debug option by name
func set_debug_option(option_name: String, value: bool) -> void:
	# Convert from system name to property name if needed
	var property_name = "debug_" + option_name
	if option_name == "master":
		property_name = "debug_mode"
	elif option_name == "grid":
		property_name = "draw_debug_grid"
	elif option_name == "panel":
		property_name = "debug_panel"
	
	# Only set if property exists
	if has_property(self, property_name):
		set(property_name, value)
		
		# Update main debug_mode as needed
		if option_name != "master":
			_debug_settings[option_name] = value
		else:
			# If master toggle changes, apply to all settings dictionary
			_debug_settings["master"] = value
			
		# Notify systems
		debug_settings_changed.emit(_debug_settings)

# Toggle a debug option by name
func toggle_debug_option(option_name: String) -> bool:
	# Convert from system name to property name if needed
	var property_name = "debug_" + option_name
	if option_name == "master":
		property_name = "debug_mode"
	elif option_name == "grid":
		property_name = "draw_debug_grid"
	elif option_name == "panel":
		property_name = "debug_panel"
	
	# Only toggle if property exists
	if has_property(self, property_name):
		var current_value = get(property_name)
		set(property_name, not current_value)
		return not current_value
	
	return false

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
		return debug_mode and draw_debug_grid
	elif system_name == "panel":
		return debug_panel
	
	# Default to false for unknown systems
	return false

# Helper function to check if an object has a property
static func has_property(object: Object, property_name: String) -> bool:
	for property in object.get_property_list():
		if property.name == property_name:
			return true
	return false

# ---- SEED MANAGEMENT ----

func _initialize_seed() -> void:
	if use_random_seed or game_seed == 0:
		generate_random_seed()
	else:
		# Use the provided seed
		seed_hash = _generate_seed_hash(game_seed)

func get_seed() -> int:
	return game_seed

func set_seed(new_seed: int) -> void:
	var old_seed = game_seed
	game_seed = new_seed
	use_random_seed = false
	seed_hash = _generate_seed_hash(game_seed)
	
	if debug_mode and old_seed != new_seed:
		print("GameSettings: Seed changed from ", old_seed, " to ", new_seed)
	
	seed_changed.emit(new_seed)

func generate_random_seed() -> void:
	randomize()
	var new_seed = randi()
	set_seed(new_seed)
	use_random_seed = true

# ---- GRID POSITION HELPERS ----

# Get the starting position for the player in world coordinates
func get_player_starting_position() -> Vector2:
	# Player starts near the center of the grid
	var center_cell = Vector2i(grid_size / 2.0, grid_size / 2.0)
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
func get_effective_planet_type(seed_value: int = 0) -> int:
	if is_random_player_planet():
		# Generate a random planet type based on seed
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value if seed_value != 0 else game_seed
		return rng.randi_range(0, 6)  # 0-6 for the 7 planet types
	else:
		# Adjust for the "Random" option at index 0
		return player_starting_planet_type - 1

# Get a description of the selected planet type for debugging
func get_planet_type_description() -> String:
	if is_random_player_planet():
		return "Random (seed-based)"
	else:
		return get_planet_type_name(player_starting_planet_type - 1)

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

# ---- PLANET TYPE HELPERS ----

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

# Convert planet type name to theme ID used in planet generators
func get_planet_theme_id(type_index: int) -> int:
	# In PlanetTheme enum:
	# ARID = 0, ICE = 1, LAVA = 2, LUSH = 3, DESERT = 4, ALPINE = 5, OCEAN = 6
	# So we can use the type_index directly
	return type_index

# ---- UTILITY FUNCTIONS ----

# Generate a readable hash string from the seed
func _generate_seed_hash(seed_value: int) -> String:
	# Convert to a 6-character alphanumeric hash
	var characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # Omitting similar characters
	var hash_string = ""
	var temp_seed = seed_value
	
	for i in range(6):
		var index = temp_seed % characters.length()
		hash_string += characters[index]
		# Fix for integer division
		temp_seed = int(temp_seed / float(characters.length()))
	
	return hash_string

# Helper function to combine seed and object ID into a new hash
func _hash_combine(seed_value: int, object_id: int) -> int:
	return ((seed_value << 5) + seed_value) ^ object_id
