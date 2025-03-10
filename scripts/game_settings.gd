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
## Starting planet type for the player
@export_enum("Arid", "Ice", "Lava", "Lush", "Desert", "Alpine", "Ocean") 
var player_starting_planet_type: int = 3  # Default to Lush (index 3)
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
## Enable debug output and visualizations
@export var debug_mode: bool = false
## Draw additional debug info for generation
@export var draw_debug_grid: bool = false

# ---- INTERNAL VARIABLES ----
var _initialized: bool = false
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _ready() -> void:
	# Initialize seed if needed
	_initialize_seed()
	
	# Log settings if debug mode is on
	if debug_mode:
		print("GameSettings initialized with seed: ", game_seed)
		print("Grid size: ", grid_size, "x", grid_size, " (", grid_cell_size, " pixels per cell)")
		print("Player starting planet type: ", get_planet_type_name(player_starting_planet_type))
	
	_initialized = true
	settings_initialized.emit()

# ---- SEED MANAGEMENT ----

func _initialize_seed() -> void:
	if use_random_seed and game_seed == 0:
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
	var center_cell = Vector2i(grid_size / 2, grid_size / 2)
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

# ---- DETERMINISTIC RANDOMIZATION ----

# Get a deterministic random value for an object ID
func get_random_value(object_id: int, min_val: float, max_val: float, object_subid: int = 0) -> float:
	_rng.seed = _hash_combine(game_seed, object_id + object_subid)
	return min_val + _rng.randf() * (max_val - min_val)

# Get a deterministic random integer
func get_random_int(object_id: int, min_val: int, max_val: int, object_subid: int = 0) -> int:
	_rng.seed = _hash_combine(game_seed, object_id + object_subid)
	return _rng.randi_range(min_val, max_val)

# Get a deterministic position within a circle
func get_random_point_in_circle(object_id: int, radius: float, object_subid: int = 0) -> Vector2:
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
