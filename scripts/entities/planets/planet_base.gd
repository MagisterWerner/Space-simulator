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
var use_texture_cache: bool = true
var _moon_scenes: Dictionary = {}
var _initialized: bool = false

# New properties for orbit type differentiation
var is_gaseous_planet: bool = false
var orbit_inclination_range: Vector2 = Vector2(0.0, 0.1) # For terran planets, how much moons can deviate from equatorial plane

func _ready() -> void:
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

func _update_moons(_delta: float) -> void:
	var time = Time.get_ticks_msec() / 1000.0
	
	for moon in moons:
		if is_instance_valid(moon):
			if is_gaseous_planet:
				_update_gaseous_moon_orbit(moon, time)
			else:
				_update_terran_moon_orbit(moon, time)

# New method specifically for terran moon orbits
func _update_terran_moon_orbit(moon, time: float) -> void:
	# Calculate the orbit angle based on time, speed and initial offset
	var moon_angle = moon.base_angle + time * moon.orbit_speed + moon.phase_offset
	
	# Calculate deviation for elliptical orbits using sine function
	var deviation_factor = sin(moon_angle * 2) * moon.orbit_deviation
	
	# Calculate moon position using parametric equation of ellipse
	# This creates an equatorial orbit that passes in front of and behind the planet
	moon.global_position = global_position + Vector2(
		cos(moon_angle) * moon.distance * (1.0 + deviation_factor * 0.3),
		sin(moon_angle) * moon.distance
	)
	
	# Determine if moon is behind or in front of planet
	# When sin(moon_angle) is negative, the moon is in the "back half" of its orbit
	var relative_y = sin(moon_angle)
	
	# Set z-index dynamically based on position relative to planet
	# This creates the visual effect of moon passing behind the planet and atmosphere
	moon.z_index = -12 if relative_y < 0 else -9

# New method specifically for gaseous moon orbits
func _update_gaseous_moon_orbit(moon, time: float) -> void:
	# Calculate the orbit angle based on time, speed and initial offset
	var moon_angle = moon.base_angle + time * moon.orbit_speed + moon.phase_offset
	
	# Get moon's individual inclination and offset
	var inclination = moon.orbital_inclination 
	var orbit_offset = moon.orbit_vertical_offset
	
	# Calculate position using 3D orbit projection to 2D
	# This creates an orbit that never visually intersects with the planet
	var horizontal_scale = moon.distance
	var vertical_scale = moon.distance * inclination
	
	# Calculate position using modified ellipse that's offset from planet center
	moon.global_position = global_position + Vector2(
		cos(moon_angle) * horizontal_scale,
		sin(moon_angle) * vertical_scale + orbit_offset
	)
	
	# Always set z-index to be in front of the planet
	# For gaseous planets, moons are always visible
	moon.z_index = -8

# Base initialization function - handles common setup
func initialize(params: Dictionary) -> void:
	if _initialized:
		return
		
	seed_value = params.seed_value
	grid_x = params.get("grid_x", 0)
	grid_y = params.get("grid_y", 0)
	
	# Detect if this is a gaseous planet (can be overridden by subclasses)
	is_gaseous_planet = params.get("category_override", PlanetCategories.TERRAN) == PlanetCategories.GASEOUS
	
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
	if "is_gaseous_planet" in params: is_gaseous_planet = params.is_gaseous_planet

	# Each subclass will implement its own custom initialization
	_perform_specialized_initialization(params)
	
	# Generate a simple name based on type and seed
	planet_name = _get_planet_type_name() + "-" + str(seed_value % 1000)
	
	# Defer moon creation to avoid stuttering
	call_deferred("_create_moons")
	
	_initialized = true

# Virtual method to be implemented by subclasses
func _perform_specialized_initialization(_params: Dictionary) -> void:
	push_error("PlanetBase: _perform_specialized_initialization is a virtual method that should be overridden")

# Get the scaling factor for moon sizes
func _get_moon_size_scale() -> float:
	return 1.0  # Default no scaling

# Moon creation - common for all planet types
func _create_moons() -> void:
	if _moon_scenes.is_empty():
		push_error("Planet: Moon scenes not available for moon creation")
		emit_signal("planet_loaded", self)
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Determine if this planet has moons based on chance
	var has_moons = (rng.randi() % 100 < moon_chance)
	var num_moons = 0
	
	if has_moons:
		# Calculate how many moons (1 to max_moons)
		num_moons = rng.randi_range(1, max_moons)
	
	# If no moons, exit early
	if num_moons <= 0:
		emit_signal("planet_loaded", self)
		return
	
	# Generate orbital parameters for all moons to prevent collisions
	var orbital_params = _generate_orbital_parameters(num_moons, rng)
	
	for m in range(num_moons):
		var moon_seed = seed_value + m * 100 + rng.randi() % 1000
		
		# Determine moon type based on planet category
		var moon_type = _get_moon_type_for_position(m, num_moons, rng)
		
		# Get the correct moon scene for this type
		if not _moon_scenes.has(moon_type):
			push_warning("Planet: Moon type not available: " + str(moon_type) + ", using ROCKY")
			moon_type = MoonType.ROCKY
			
		if not _moon_scenes.has(moon_type):
			push_error("Planet: No moon scenes available")
			continue
			
		var moon_scene = _moon_scenes[moon_type]
		if not moon_scene:
			continue
			
		var moon_instance = moon_scene.instantiate()
		if not moon_instance:
			continue
		
		# Generate a simple moon name
		var moon_name = _get_moon_type_prefix(moon_type) + " Moon-" + str(moon_seed % 1000)
		
		# Generate orbital parameters specific to planet type
		var orbit_params = _get_orbit_params_for_planet_type(m, num_moons, rng)
		
		# Use the pre-calculated orbital parameters
		var moon_params = {
			"seed_value": moon_seed,
			"parent_planet": self,
			"distance": orbital_params[m].distance,
			"base_angle": orbital_params[m].base_angle,
			"orbit_speed": orbital_params[m].orbit_speed,
			"orbit_deviation": orbital_params[m].orbit_deviation,
			"phase_offset": orbital_params[m].phase_offset,
			"parent_name": planet_name,
			"use_texture_cache": use_texture_cache,
			"moon_type": moon_type,
			"size_scale": _get_moon_size_scale(),
			"is_gaseous": is_gaseous_planet,
			"moon_name": moon_name,
			# New orbit parameters for different planet types
			"orbital_inclination": orbit_params.inclination,
			"orbit_vertical_offset": orbit_params.vertical_offset
		}
		
		add_child(moon_instance)
		moon_instance.initialize(moon_params)
		moons.append(moon_instance)
	
	# Emit signal that the planet has been loaded (after moons are created)
	emit_signal("planet_loaded", self)

# Generate orbit parameters specific to planet type
func _get_orbit_params_for_planet_type(moon_index: int, total_moons: int, rng: RandomNumberGenerator) -> Dictionary:
	if is_gaseous_planet:
		# For gaseous planets, create orbits that never visually intersect with the planet
		# by giving them significant inclination and vertical offset
		
		# Distribute moons evenly through vertical space
		var vertical_position = (float(moon_index) / total_moons) - 0.5  # Range from -0.5 to 0.5
		
		# Add randomization to make it look natural
		var random_offset = rng.randf_range(-0.1, 0.1)
		vertical_position += random_offset
		
		# Calculate vertical offset and inclination
		var orbit_offset = vertical_position * pixel_size * 1.5  # Scale by planet size
		var inclination = rng.randf_range(0.2, 0.4)  # Flattened ellipses
		
		return {
			"inclination": inclination,
			"vertical_offset": orbit_offset
		}
	else:
		# For terran planets, create orbits near the equatorial plane
		# Slight inclination so not all moons are perfectly flat
		var inclination = rng.randf_range(orbit_inclination_range.x, orbit_inclination_range.y)
		
		return {
			"inclination": 1.0 + inclination,  # Near 1.0 for nearly circular, equatorial orbits
			"vertical_offset": 0.0  # No vertical offset for terran planets
		}

# Helper to get moon type prefix
func _get_moon_type_prefix(moon_type: int) -> String:
	match moon_type:
		MoonType.ROCKY: return "Rocky"
		MoonType.ICY: return "Icy"
		MoonType.VOLCANIC: return "Volcanic"
		_: return "Moon"

# Virtual method to determine appropriate moon types
func _get_moon_type_for_position(_position: int, _total_moons: int, _rng: RandomNumberGenerator) -> int:
	# Default implementation - return a rocky moon
	return MoonType.ROCKY

# Generate well-distributed orbital parameters to prevent moon collisions
func _generate_orbital_parameters(moon_count: int, rng: RandomNumberGenerator) -> Array:
	var params = []
	
	if moon_count <= 0:
		return params
	
	# Calculate planet radius for reference
	var planet_radius = pixel_size / 2.0
	
	# Define distance range based on planet size
	var min_distance = planet_radius * min_moon_distance_factor
	var max_distance = planet_radius * max_moon_distance_factor
	
	# Adjust distance range for gaseous planets
	if is_gaseous_planet:
		# Spread moons further from gaseous planets
		min_distance *= 1.2
		max_distance *= 1.3
	
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
			
			params.append({
				"distance": distance,
				"base_angle": 0.0, # Start at same position, but phase_offset will separate them
				"orbit_speed": orbit_speed,
				"orbit_deviation": orbit_deviation,
				"phase_offset": phase_offset
			})
	else:
		# For a single moon, use simpler parameters
		params.append({
			"distance": rng.randf_range(min_distance, max_distance),
			"base_angle": 0.0,
			"orbit_speed": rng.randf_range(0.2, 0.5) * moon_orbit_factor * _get_orbit_speed_modifier(),
			"orbit_deviation": rng.randf_range(0.05, max_orbit_deviation),
			"phase_offset": rng.randf_range(0, TAU) # Random starting position
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
