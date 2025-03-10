# scripts/entities/planets/planet_base.gd
# Base planet class with shared functionality across planet types
extends Node2D
class_name PlanetBase

# Import classification constants for backward compatibility
const PlanetThemes = preload("res://scripts/generators/planet_generator_base.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator_base.gd").PlanetCategory

signal planet_loaded(planet)

# Common properties for all planets
@export var max_moons: int = 2
@export var moon_chance: int = 40
@export var min_moon_distance_factor: float = 1.8
@export var max_moon_distance_factor: float = 2.5
@export var max_orbit_deviation: float = 0.15
@export var moon_orbit_factor: float = 0.05

# Shared properties
var seed_value: int = 0
var pixel_size: int = 256
var planet_texture: Texture2D
var atmosphere_texture: Texture2D
var theme_id: int
var planet_name: String
var atmosphere_data: Dictionary
var moons = []
var grid_x: int = 0
var grid_y: int = 0

# Define moon types for consistent reference
enum MoonType {
	ROCKY,
	ICY,
	VOLCANIC
}

# Base class properties
var name_component
var use_texture_cache: bool = true
var _moon_scenes: Dictionary = {}
var _initialized: bool = false

func _ready() -> void:
	name_component = get_node_or_null("NameComponent")
	# Set appropriate z-index to render behind player but in front of atmosphere
	z_index = -10
	
	# Load moon scene references
	_load_moon_scenes()
	
func _load_moon_scenes() -> void:
	# Load all moon type scenes
	var rocky_path = "res://scenes/world/moon_rocky.tscn"
	var icy_path = "res://scenes/world/moon_icy.tscn"
	var volcanic_path = "res://scenes/world/moon_volcanic.tscn"
	
	if ResourceLoader.exists(rocky_path):
		_moon_scenes[MoonType.ROCKY] = load(rocky_path)
	else:
		push_error("Planet: Failed to load rocky moon scene")
		
	if ResourceLoader.exists(icy_path):
		_moon_scenes[MoonType.ICY] = load(icy_path)
	else:
		push_error("Planet: Failed to load icy moon scene")
		
	if ResourceLoader.exists(volcanic_path):
		_moon_scenes[MoonType.VOLCANIC] = load(volcanic_path)
	else:
		push_error("Planet: Failed to load volcanic moon scene")

func _process(delta: float) -> void:
	queue_redraw()
	_update_moons(delta)

func _draw() -> void:
	if atmosphere_texture:
		# Draw atmosphere first so it's behind the planet
		draw_texture(atmosphere_texture, -Vector2(atmosphere_texture.get_width(), atmosphere_texture.get_height()) / 2, Color.WHITE)
	
	if planet_texture:
		draw_texture(planet_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)

# Base moon update method - override in subclasses for specific behavior
func _update_moons(_delta: float) -> void:
	# This should be overridden in subclasses
	pass

# Base initialization function - handles common setup
func initialize(params: Dictionary) -> void:
	if _initialized:
		return
		
	seed_value = params.seed_value
	grid_x = params.get("grid_x", 0)
	grid_y = params.get("grid_y", 0)
	
	# Apply customizations if provided
	if "max_moons" in params: max_moons = params.max_moons
	if "moon_chance" in params: moon_chance = params.moon_chance
	if "min_moon_distance_factor" in params: min_moon_distance_factor = params.min_moon_distance_factor
	if "max_moon_distance_factor" in params: max_moon_distance_factor = params.max_moon_distance_factor
	if "max_orbit_deviation" in params: max_orbit_deviation = params.max_orbit_deviation
	if "moon_orbit_factor" in params: moon_orbit_factor = params.moon_orbit_factor
	if "use_texture_cache" in params: use_texture_cache = params.use_texture_cache
	if "moon_orbit_speed_factor" in params and params.moon_orbit_speed_factor != 1.0:
		moon_orbit_factor *= params.moon_orbit_speed_factor

	# Each subclass will implement its own custom initialization
	_perform_specialized_initialization(params)
	
	# All planets need a name
	_setup_name_component(params)
	
	# Defer moon creation to avoid stuttering
	call_deferred("_create_moons")
	
	_initialized = true

# Virtual method to be implemented by subclasses
func _perform_specialized_initialization(_params: Dictionary) -> void:
	push_error("PlanetBase: _perform_specialized_initialization is a virtual method that should be overridden")

# Get the scaling factor for moon sizes
func _get_moon_size_scale() -> float:
	return 1.0  # Default no scaling

# Create moons - this is a placeholder that subclasses should override
func _create_moons() -> void:
	# To be overridden in subclasses
	pass

# Virtual method to determine appropriate moon types
func _get_moon_type_for_position(_position: int, _total_moons: int, _rng: RandomNumberGenerator) -> int:
	# Default implementation - return a rocky moon
	return MoonType.ROCKY

# Name setup for all planets
func _setup_name_component(_params: Dictionary) -> void:
	name_component = get_node_or_null("NameComponent")
	if name_component:
		# The name component initialization depends on the planet type
		# This will be customized in the subclasses
		var type_prefix = _get_planet_type_name()
		name_component.initialize(seed_value, grid_x, grid_y, "", type_prefix)
		planet_name = name_component.get_entity_name()
	else:
		# Fallback naming if no name component
		planet_name = _get_planet_type_name() + "-" + str(seed_value % 1000)

# Generate well-distributed orbital parameters to prevent moon collisions
# This is used for terran planets - gaseous planets override this
func _generate_orbital_parameters(moon_count: int, rng: RandomNumberGenerator) -> Array:
	var params = []
	
	if moon_count <= 0:
		return params
	
	# Calculate planet radius for reference
	var planet_radius = pixel_size / 2.0
	
	# Define distance range based on planet size
	var min_distance = planet_radius * min_moon_distance_factor
	var max_distance = planet_radius * max_moon_distance_factor
	
	# For multiple moons, use intelligent parameter distribution
	if moon_count > 1:
		# Step 1: Calculate distances with spacing to avoid crowding
		var distance_step = (max_distance - min_distance) / float(moon_count)
		
		for i in range(moon_count):
			# Apply even spacing with a little randomness
			var base_distance = min_distance + i * distance_step
			var jitter = distance_step * 0.2 * rng.randf_range(-1.0, 1.0)
			var distance = clamp(base_distance + jitter, min_distance, max_distance)
			
			# Step 2: Calculate orbital speed based on distance (Kepler's law)
			# Closer moons orbit faster (sqrt relationship)
			var speed_factor = 1.0 / sqrt(distance / min_distance)
			
			# Adjust for planet mass
			var orbit_modifier = _get_orbit_speed_modifier()
			var orbit_speed = rng.randf_range(0.2, 0.4) * moon_orbit_factor * speed_factor * orbit_modifier
			
			# Step 3: Distribute phase offsets evenly around orbit
			# This ensures moons start at different positions
			var phase_offset = (i * TAU / float(moon_count)) + rng.randf_range(-0.2, 0.2)
			
			# Step 4: Set orbit deviation (for elliptical orbits)
			# Larger deviation for farther moons
			var orbit_deviation = rng.randf_range(0.05, max_orbit_deviation) * (distance / max_distance)
			
			# Create random orbit tilt (only for terran moons)
			var tilt_angle = rng.randf_range(0, TAU)
			var tilt_amount = rng.randf_range(0.1, 0.4)  # Maximum 40% tilt
			
			params.append({
				"distance": distance,
				"base_angle": 0.0, # Start at same position, but phase_offset will separate them
				"orbit_speed": orbit_speed,
				"orbit_deviation": orbit_deviation,
				"phase_offset": phase_offset,
				"tilt_angle": tilt_angle,
				"tilt_amount": tilt_amount
			})
	else:
		# For a single moon, use simpler parameters
		params.append({
			"distance": rng.randf_range(min_distance, max_distance),
			"base_angle": 0.0,
			"orbit_speed": rng.randf_range(0.2, 0.5) * moon_orbit_factor * _get_orbit_speed_modifier(),
			"orbit_deviation": rng.randf_range(0.05, max_orbit_deviation),
			"phase_offset": rng.randf_range(0, TAU), # Random starting position
			"tilt_angle": rng.randf_range(0, TAU),
			"tilt_amount": rng.randf_range(0.1, 0.4)
		})
	
	return params

# Virtual method for orbit speed modifier
func _get_orbit_speed_modifier() -> float:
	return 1.0

# Virtual method for planet type name 
func _get_planet_type_name() -> String:
	return "Planet"

# Get the theme name of this planet - for UI/debugging
func get_theme_name() -> String:
	match theme_id:
		PlanetThemes.ARID: return "Arid"
		PlanetThemes.ICE: return "Ice"
		PlanetThemes.LAVA: return "Lava"
		PlanetThemes.LUSH: return "Lush"
		PlanetThemes.DESERT: return "Desert"
		PlanetThemes.ALPINE: return "Alpine"
		PlanetThemes.OCEAN: return "Ocean"
		PlanetThemes.JUPITER: return "Jupiter-like"
		PlanetThemes.SATURN: return "Saturn-like"
		PlanetThemes.URANUS: return "Uranus-like"
		PlanetThemes.NEPTUNE: return "Neptune-like"
		_: return "Unknown"
