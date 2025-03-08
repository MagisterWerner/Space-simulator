# scripts/game_settings.gd
extends Node
class_name GameSettings

signal settings_changed

## Seed Settings
@export_category("Seed Settings")
@export var game_seed: int = 0:
	set(value):
		game_seed = value
		settings_changed.emit()
@export var use_random_seed: bool = true:
	set(value):
		use_random_seed = value
		settings_changed.emit()

## Grid Settings
@export_category("Grid Settings")
@export var grid_size: int = 10:
	set(value):
		grid_size = value
		settings_changed.emit()
@export var cell_size: int = 1024:
	set(value):
		cell_size = value
		settings_changed.emit()
@export var grid_color: Color = Color.CYAN:
	set(value):
		grid_color = value
		settings_changed.emit()
@export var grid_line_width: float = 2.0:
	set(value):
		grid_line_width = value
		settings_changed.emit()
@export var grid_opacity: float = 0.5:
	set(value):
		grid_opacity = value
		settings_changed.emit()

## Planet Settings
@export_category("Planet Settings")
@export var num_terran_planets: int = 5:
	set(value):
		num_terran_planets = value
		settings_changed.emit()
@export var min_planet_distance: int = 1:  # Minimum empty cells between planets
	set(value):
		min_planet_distance = value
		settings_changed.emit()
@export_enum("Lush", "Ocean", "Desert", "Arid", "Alpine", "Ice", "Lava") var starting_planet_type: int = 0:  # Default to Lush
	set(value):
		starting_planet_type = value
		settings_changed.emit()

## Performance Settings
@export_category("Performance Settings")
@export var preload_textures: bool = true:
	set(value):
		preload_textures = value
		settings_changed.emit()
@export var use_threading: bool = true:
	set(value):
		use_threading = value
		settings_changed.emit()
@export var async_planet_generation: bool = true:
	set(value):
		async_planet_generation = value
		settings_changed.emit()
@export var pregenerate_common_textures: bool = true:
	set(value):
		pregenerate_common_textures = value
		settings_changed.emit()

# Planet type mapping constants
const PLANET_TYPES = {
	"lush": {"index": 0, "color": Color(0.2, 0.7, 0.3), "name": "Lush"},
	"ocean": {"index": 1, "color": Color(0.1, 0.4, 0.7), "name": "Ocean"},
	"desert": {"index": 2, "color": Color(0.85, 0.7, 0.4), "name": "Desert"},
	"arid": {"index": 3, "color": Color(0.85, 0.65, 0.35), "name": "Arid"},
	"alpine": {"index": 4, "color": Color(0.85, 0.95, 0.9), "name": "Alpine"},
	"ice": {"index": 5, "color": Color(0.8, 0.9, 1.0), "name": "Ice"},
	"lava": {"index": 6, "color": Color(0.9, 0.3, 0.1), "name": "Lava"}
}

var _settings_hash: int = 0
var _initialized: bool = false

func _ready() -> void:
	_initialized = true
	_update_settings_hash()

func _update_settings_hash() -> void:
	if not _initialized:
		return
	
	# Calculate a hash of all settings to detect changes
	var hash_inputs = [
		game_seed, int(use_random_seed),
		grid_size, cell_size, 
		grid_color.to_rgba32(), grid_line_width, grid_opacity,
		num_terran_planets, min_planet_distance, starting_planet_type,
		int(preload_textures), int(use_threading), 
		int(async_planet_generation), int(pregenerate_common_textures)
	]
	
	var new_hash = hash(str(hash_inputs))
	if new_hash != _settings_hash:
		_settings_hash = new_hash
		settings_changed.emit()

# Get the type data for a planet type index
func get_planet_type_by_index(index: int) -> Dictionary:
	for type_key in PLANET_TYPES:
		var type_data = PLANET_TYPES[type_key]
		if type_data.index == index:
			return {"key": type_key, "data": type_data}
	
	# Default to lush if not found
	return {"key": "lush", "data": PLANET_TYPES.lush}

# Get string name for starting planet type
func get_starting_planet_type_name() -> String:
	var type_data = get_planet_type_by_index(starting_planet_type)
	return type_data.key

# Get all planet types in priority order (starting type first)
func get_planet_types_ordered() -> Array:
	var ordered_types = []
	
	# Add starting type first
	var starting_type = get_starting_planet_type_name()
	ordered_types.append(starting_type)
	
	# Add all other types
	for type_key in PLANET_TYPES:
		if type_key != starting_type:
			ordered_types.append(type_key)
	
	return ordered_types
