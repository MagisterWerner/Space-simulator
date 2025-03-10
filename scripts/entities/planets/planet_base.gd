# scripts/entities/planets/planet_base.gd
# Base class for all planets with moon orbit system
extends Node2D
class_name PlanetBase

## Constants and Enums
const PlanetThemes = preload("res://scripts/generators/planet_generator_base.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator_base.gd").PlanetCategory

enum MoonType { ROCKY, ICY, VOLCANIC }

## Signals
signal planet_loaded(planet)

## Planet Configuration
@export_group("Planet Properties")
@export var max_moons: int = 2
@export var moon_chance: int = 40  # Percentage chance to have moons

@export_group("Moon Orbit Configuration")
@export var min_moon_distance_factor: float = 1.8
@export var max_moon_distance_factor: float = 2.5
@export var max_orbit_deviation: float = 0.15
@export var moon_orbit_factor: float = 0.05

@export_group("Debug Options")
@export var debug_draw_orbits: bool = false
@export var debug_orbit_line_width: float = 1.0

## Internal properties
var seed_value: int = 0
var planet_texture: Texture2D
var atmosphere_texture: Texture2D
var theme_id: int
var planet_name: String
var pixel_size: int = 256
var moons = []
var is_gaseous_planet: bool = false
var use_texture_cache: bool = true
var grid_x: int = 0
var grid_y: int = 0
var atmosphere_data: Dictionary = {}

# Moon scene cache
var _moon_scenes = {}
var _initialized: bool = false

# Moon Type Parameters (configurable through subclasses)
var _moon_params = {
	"distance_ranges": {
		MoonType.VOLCANIC: Vector2(1.3, 1.6),  # Closest to planet
		MoonType.ROCKY: Vector2(1.9, 2.2),     # Middle distance
		MoonType.ICY: Vector2(2.5, 3.0)        # Furthest from planet
	},
	"speed_modifiers": {
		MoonType.VOLCANIC: 1.4,  # Faster for close moons
		MoonType.ROCKY: 1.0,     # Normal speed
		MoonType.ICY: 0.7        # Slower for distant moons
	},
	"colors": {
		MoonType.VOLCANIC: Color(1.0, 0.3, 0.0, 0.4),  # Orange-red for volcanic
		MoonType.ROCKY: Color(0.7, 0.7, 0.7, 0.4),     # Gray for rocky
		MoonType.ICY: Color(0.5, 0.8, 1.0, 0.4)        # Light blue for icy
	},
	"z_indices": {
		MoonType.VOLCANIC: -6,  # Closest moons always in front
		MoonType.ROCKY: -7,     # Middle distance moons
		MoonType.ICY: -8        # Furthest moons always behind
	}
}

# Common constants - changed ORBIT_COLLISION_MARGIN to 16.0 as requested
const ORBIT_COLLISION_MARGIN: float = 16.0  # Fixed margin between moons
const DEFAULT_Z_INDEX: int = -7

#region Lifecycle Methods
func _ready() -> void:
	z_index = -10  # Explicitly set planet z-index to -10
	_load_moon_scenes()

func _process(delta: float) -> void:
	queue_redraw()
	_update_moons(delta)
#endregion

#region Initialization Methods
func initialize(params: Dictionary) -> void:
	if _initialized:
		return
		
	# Core parameters
	seed_value = params.seed_value
	grid_x = params.get("grid_x", 0)
	grid_y = params.get("grid_y", 0)
	is_gaseous_planet = params.get("category_override", PlanetCategories.TERRAN) == PlanetCategories.GASEOUS
	
	# Apply optional customizations 
	_apply_config_params(params)
	
	# Initialize specific planet implementation
	_perform_specialized_initialization(params)
	
	# Generate a planet name
	planet_name = _get_planet_type_name() + "-" + str(seed_value % 1000)
	
	# Defer moon creation to avoid stuttering
	call_deferred("_create_moons")
	
	_initialized = true

func _load_moon_scenes() -> void:
	var scenes = {
		MoonType.ROCKY: "res://scenes/world/moon_rocky.tscn",
		MoonType.ICY: "res://scenes/world/moon_icy.tscn",
		MoonType.VOLCANIC: "res://scenes/world/moon_volcanic.tscn"
	}
	
	for type in scenes:
		var path = scenes[type]
		if ResourceLoader.exists(path):
			_moon_scenes[type] = load(path)
		else:
			push_error("Planet: Failed to load moon scene: %s" % path)

func _apply_config_params(params: Dictionary) -> void:
	# Apply all optional parameters with a concise approach
	var properties = {
		"max_moons": max_moons,
		"moon_chance": moon_chance,
		"min_moon_distance_factor": min_moon_distance_factor,
		"max_moon_distance_factor": max_moon_distance_factor,
		"max_orbit_deviation": max_orbit_deviation, 
		"moon_orbit_factor": moon_orbit_factor,
		"use_texture_cache": use_texture_cache,
		"debug_draw_orbits": debug_draw_orbits,
		"debug_orbit_line_width": debug_orbit_line_width,
		"is_gaseous_planet": is_gaseous_planet
	}
	
	# Apply all properties that exist in params
	for prop in properties:
		if params.has(prop):
			set(prop, params[prop])
	
	# Special case for moon orbit speed factor
	if params.has("moon_orbit_speed_factor") and params.moon_orbit_speed_factor != 1.0:
		moon_orbit_factor *= params.moon_orbit_speed_factor
#endregion

#region Drawing and Visuals
func _draw() -> void:
	# Draw atmosphere (behind the planet)
	if atmosphere_texture:
		draw_texture(atmosphere_texture, 
					-Vector2(atmosphere_texture.get_width(), atmosphere_texture.get_height()) / 2, 
					Color.WHITE)
	
	# Draw planet - make planet's z-index -10
	if planet_texture:
		draw_texture(planet_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)
	
	# Debug orbit visualizations
	if debug_draw_orbits:
		_draw_debug_orbits()

func _draw_debug_orbits() -> void:
	const SEGMENTS = 64
	
	for moon in moons:
		if not is_instance_valid(moon):
			continue
			
		# Get appropriate orbit color
		var orbit_color = _get_moon_property(moon, "color")
		
		# Draw orbit path segments
		var prev_point = Vector2.ZERO
		var first_point = Vector2.ZERO
		
		for i in range(SEGMENTS + 1):
			var angle = i * TAU / SEGMENTS
			var point = calculate_orbit_position(moon, angle)
			
			if i == 0:
				first_point = point
			elif i > 0:
				draw_line(prev_point, point, orbit_color, debug_orbit_line_width)
				
			prev_point = point
		
		# Connect last segment to complete the orbit
		draw_line(prev_point, first_point, orbit_color, debug_orbit_line_width)
		
		# Draw current moon position indicator
		var current_angle = moon.base_angle + (Time.get_ticks_msec() / 1000.0) * moon.orbit_speed + moon.phase_offset
		var current_pos = calculate_orbit_position(moon, current_angle)
		draw_circle(current_pos, 3.0, orbit_color)
#endregion

#region Moon Positioning and Updates
func _update_moons(_delta: float) -> void:
	var time = Time.get_ticks_msec() / 1000.0
	
	for moon in moons:
		if not is_instance_valid(moon):
			continue
			
		# Calculate orbit angle and position
		var moon_angle = moon.base_angle + time * moon.orbit_speed + moon.phase_offset
		var orbit_position = calculate_orbit_position(moon, moon_angle)
		
		# Set moon position
		moon.position = orbit_position
		
		# Set z-index for visual layering
		if is_gaseous_planet:
			moon.z_index = _get_moon_property(moon, "z_index")
		else:
			# Use absolute z-indices, not relative to parent
			moon.z_as_relative = false
			
			if sin(moon_angle) > 0:
				# Top half of orbit - should be BEHIND planet
				moon.z_index = 50
			else:
				# Bottom half of orbit - should be IN FRONT of planet
				moon.z_index = -50

func calculate_orbit_position(moon, angle: float) -> Vector2:
	if is_gaseous_planet:
		# Perfect circular orbit
		return Vector2(cos(angle), sin(angle)) * moon.distance
	else:
		# Tilted orbit for terran planets
		var deviation = sin(angle * 2) * moon.orbit_deviation
		var radius = moon.distance * (1.0 + deviation * 0.3)
		
		# Create a tilted orbit effect by applying a y-axis compression
		var tilt_factor = 0.4  # Controls how "tilted" the orbit appears
		
		# Calculate orbital position with tilt
		var orbit_x = cos(angle) * radius
		var orbit_y = sin(angle) * radius * tilt_factor
		
		return Vector2(orbit_x, orbit_y)
#endregion

#region Moon Creation
func _create_moons() -> void:
	if _moon_scenes.is_empty():
		push_error("Planet: Moon scenes not available")
		emit_signal("planet_loaded", self)
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# For gaseous planets, ALWAYS create moons (bypass chance check completely)
	if not is_gaseous_planet:
		# Only do chance check for terran planets
		var has_moons = rng.randi() % 100 < moon_chance
		if not has_moons:
			emit_signal("planet_loaded", self)
			return
	
	# Determine number of moons
	var num_moons = rng.randi_range(1, max_moons)
	
	# For gaseous planets, ensure at least 3 moons (one of each type)
	if is_gaseous_planet:
		num_moons = max(3, num_moons)
	
	# Generate and distribute moons
	var moon_distribution = _calculate_moon_distribution(num_moons)
	var orbital_params = _generate_orbital_parameters(num_moons, rng, moon_distribution)
	var existing_orbits = []
	
	# Create each moon
	for m in range(num_moons):
		var moon_type = _determine_moon_type(m, moon_distribution)
		var moon_instance = _create_moon(m, moon_type, orbital_params, existing_orbits, rng)
		
		if moon_instance:
			moons.append(moon_instance)
	
	# Signal that planet is fully loaded
	emit_signal("planet_loaded", self)

func _calculate_moon_distribution(num_moons: int) -> Dictionary:
	# Distribution of moon types depends on planet type
	if is_gaseous_planet:
		# For gaseous planets, ALWAYS start with exactly 1 of each type
		var volcanic_count = 1
		var rocky_count = 1
		var icy_count = 1
		
		# Calculate remaining moons to distribute
		var remaining = num_moons - 3
		
		if remaining > 0:
			var rng = RandomNumberGenerator.new()
			rng.seed = seed_value
			
			# Distribute remaining moons based on seed priority
			var types_to_increase = []
			var priority_seed = (seed_value % 3)
			
			if priority_seed == 0:
				types_to_increase = [MoonType.VOLCANIC, MoonType.ROCKY, MoonType.ICY]
			elif priority_seed == 1:
				types_to_increase = [MoonType.ROCKY, MoonType.ICY, MoonType.VOLCANIC]
			else:
				types_to_increase = [MoonType.ICY, MoonType.VOLCANIC, MoonType.ROCKY]
			
			# Add remaining slots based on priority
			for i in range(remaining):
				var type = types_to_increase[i % 3]
				
				if type == MoonType.VOLCANIC and volcanic_count < 2:
					volcanic_count += 1
				elif type == MoonType.ROCKY and rocky_count < 2:
					rocky_count += 1
				elif type == MoonType.ICY and icy_count < 2:
					icy_count += 1
				else:
					# If this type already has 2 moons, find another type with less than 2
					if volcanic_count < 2:
						volcanic_count += 1
					elif rocky_count < 2:
						rocky_count += 1
					elif icy_count < 2:
						icy_count += 1
		
		return {
			MoonType.VOLCANIC: volcanic_count,
			MoonType.ROCKY: rocky_count,
			MoonType.ICY: icy_count
		}
	else:
		# For terran planets, it's all rocky by default
		return {
			MoonType.ROCKY: num_moons
		}

func _generate_orbital_parameters(num_moons: int, rng: RandomNumberGenerator, 
								 distribution: Dictionary) -> Array:
	var params = []
	
	# Calculate specific parameters based on planet type
	if is_gaseous_planet:
		# Generate each type of moon separately to ensure proper distribution
		var _index = 0
		
		for type in [MoonType.VOLCANIC, MoonType.ROCKY, MoonType.ICY]:
			if distribution.has(type):
				var count = distribution[type]
				var distance_range = _moon_params.distance_ranges[type]
				var speed_mod = _moon_params.speed_modifiers[type]
				
				# Generate parameters for this type
				for i in range(count):
					# Add parameters for this moon
					params.append(_generate_single_moon_params(
						i, count, type, rng, speed_mod, distance_range
					))
					_index += 1
	else:
		# For terran planets, simpler evenly spaced orbits
		var planet_radius = pixel_size / 2.0
		var min_distance = planet_radius * min_moon_distance_factor
		var max_distance = planet_radius * max_moon_distance_factor
		var distance_step = (max_distance - min_distance) / max(1, num_moons)
		
		for i in range(num_moons):
			# Calculate evenly distributed distance with jitter
			var base_distance = min_distance + i * distance_step
			var jitter = distance_step * 0.2 * rng.randf_range(-1.0, 1.0)
			var distance = clamp(base_distance + jitter, min_distance, max_distance)
			
			# Determine orbital speed (closer = faster via Kepler's law)
			var speed_factor = 1.0 / sqrt(distance / min_distance)
			var orbit_speed = rng.randf_range(0.2, 0.4) * moon_orbit_factor * speed_factor * _get_orbit_speed_modifier()
			
			# Distribute phase offsets evenly
			var phase_offset = (i * TAU / float(num_moons)) + rng.randf_range(-0.2, 0.2)
			
			# Set orbit deviation (ellipse eccentricity)
			var orbit_deviation = rng.randf_range(0.05, max_orbit_deviation) * (distance / max_distance)
			
			params.append({
				"center_x": 0,
				"center_y": 0,
				"distance": distance,
				"base_angle": 0.0,
				"orbit_speed": orbit_speed,
				"orbit_deviation": orbit_deviation,
				"phase_offset": phase_offset
			})
	
	return params

func _generate_single_moon_params(index: int, count: int, _type: int, rng: RandomNumberGenerator,
								speed_mod: float, distance_range: Vector2) -> Dictionary:
	var planet_radius = pixel_size / 2.0
	
	# Calculate distance based on index within type group
	var distance_percent = float(index) / max(1, count)
	var distance = planet_radius * lerp(distance_range.x, distance_range.y, distance_percent)
	
	# Calculate orbit speed
	var base_speed = rng.randf_range(0.2, 0.4) * moon_orbit_factor * _get_orbit_speed_modifier()
	var orbit_speed = base_speed * speed_mod
	
	# Distribute evenly with slight variation
	var phase_offset = (index * TAU / count) + rng.randf_range(-0.1, 0.1)
	
	return {
		"center_x": 0,
		"center_y": 0,
		"distance": distance,
		"base_angle": 0.0,
		"orbit_speed": orbit_speed,
		"orbit_deviation": 0.0,  # No deviation for gaseous planets
		"phase_offset": phase_offset
	}

func _determine_moon_type(index: int, distribution: Dictionary) -> int:
	# For gaseous planets, determine by distribution counts
	if is_gaseous_planet:
		var volcanic_count = distribution.get(MoonType.VOLCANIC, 0)
		var rocky_count = distribution.get(MoonType.ROCKY, 0)
		
		if index < volcanic_count:
			return MoonType.VOLCANIC
		elif index < volcanic_count + rocky_count:
			return MoonType.ROCKY
		else:
			return MoonType.ICY
	
	# For terran planets, use specialized method
	return _get_moon_type_for_position(index)

func _create_moon(index: int, moon_type: int, params: Array, existing_orbits: Array, 
				  rng: RandomNumberGenerator) -> Node:
	# Validate moon scene
	if not _moon_scenes.has(moon_type):
		push_warning("Planet: Moon type not available: " + str(moon_type))
		return null
	
	# Get scene and instantiate
	var moon_scene = _moon_scenes[moon_type]
	var moon_instance = moon_scene.instantiate()
	if not moon_instance:
		return null
	
	# For terran planets, ensure moon uses absolute z-index
	if not is_gaseous_planet and moon_instance is Node2D:
		moon_instance.z_as_relative = false
		
	# Create unique moon seed
	var moon_seed = seed_value + index * 100 + rng.randi() % 1000
	
	# Get orbital parameters
	var param_index = min(index, params.size() - 1)
	var moon_params = params[param_index].duplicate()
	
	# Get moon size from MoonGenerator (create an instance first)
	var moon_generator = MoonGenerator.new()
	var moon_size = moon_generator.get_moon_size(moon_seed, is_gaseous_planet)
	
	# Add moon size to params for collision detection
	moon_params["moon_size"] = moon_size
	
	# Resolve orbit collisions if needed
	if _check_orbit_collision(moon_params, existing_orbits):
		if not _resolve_orbit_collision(moon_params, existing_orbits, moon_type, rng):
			push_warning("Planet: Skipping moon due to unresolvable collision")
			moon_instance.queue_free()
			return null
	
	# Track this orbit
	existing_orbits.append(moon_params)
	
	# Generate moon name
	var prefix = _get_moon_type_prefix(moon_type)
	var moon_name = prefix + " Moon-" + str(moon_seed % 1000)
	
	# Configure moon
	var moon_init_params = {
		"seed_value": moon_seed,
		"parent_planet": self,
		"distance": moon_params.distance,
		"base_angle": moon_params.base_angle,
		"orbit_speed": moon_params.orbit_speed,
		"orbit_deviation": moon_params.orbit_deviation,
		"phase_offset": moon_params.phase_offset,
		"parent_name": planet_name,
		"use_texture_cache": use_texture_cache,
		"moon_type": moon_type,
		"size_scale": _get_moon_size_scale(),
		"is_gaseous": is_gaseous_planet,
		"moon_name": moon_name,
		"orbital_inclination": 1.0,
		"orbit_vertical_offset": 0.0
	}
	
	# Add to scene
	add_child(moon_instance)
	
	# Initialize and position
	moon_instance.initialize(moon_init_params)
	
	# Set initial position
	var start_angle = moon_params.base_angle + moon_params.phase_offset
	var start_position = calculate_orbit_position(moon_params, start_angle)
	moon_instance.position = start_position
	
	return moon_instance

func _resolve_orbit_collision(moon_params: Dictionary, existing_orbits: Array, 
							  moon_type: int, rng: RandomNumberGenerator) -> bool:
	# Try several attempts to avoid collision
	var max_attempts = 5
	
	for attempt in range(max_attempts):
		# Adjust distance
		if is_gaseous_planet:
			var adjustment = rng.randf_range(20, 40)
			if rng.randf() > 0.5:
				moon_params.distance += adjustment
			else:
				moon_params.distance -= adjustment
			
			# Ensure within valid range for this moon type
			var distance_range = _moon_params.distance_ranges[moon_type]
			moon_params.distance = clamp(moon_params.distance, 
									   pixel_size/2 * distance_range.x, 
									   pixel_size/2 * distance_range.y)
		else:
			# For terran planets, adjust both distance and deviation
			var adjustment = rng.randf_range(15, 30)
			if rng.randf() > 0.5:
				moon_params.distance += adjustment
			else:
				moon_params.distance -= adjustment
			
			moon_params.orbit_deviation = rng.randf_range(0.05, max_orbit_deviation)
			
			# Keep within valid range
			var min_distance = pixel_size/2 * min_moon_distance_factor
			var max_distance = pixel_size/2 * max_moon_distance_factor
			moon_params.distance = clamp(moon_params.distance, min_distance, max_distance)
		
		# Adjust phase
		moon_params.phase_offset = rng.randf_range(0, TAU)
		
		# Check if orbit is now collision-free
		if not _check_orbit_collision(moon_params, existing_orbits):
			return true
	
	return false
#endregion

#region Utility Methods
func _check_orbit_collision(new_orbit: Dictionary, existing_orbits: Array) -> bool:
	if existing_orbits.is_empty():
		return false
	
	# Get moon size from params or use reasonable default
	var new_moon_size = new_orbit.get("moon_size", 32)
	
	for orbit in existing_orbits:
		# Get existing moon size from params
		var existing_moon_size = orbit.get("moon_size", 32)
		
		# Calculate safe distance based on both moons' sizes plus margin
		var safe_distance = (new_moon_size + existing_moon_size) / 2.0 + ORBIT_COLLISION_MARGIN
		
		if is_gaseous_planet:
			# Simple radii difference check for circular orbits
			var radii_difference = abs(new_orbit.distance - orbit.distance)
			if radii_difference < safe_distance:
				return true
		else:
			# More complex check for elliptical orbits
			var new_max = new_orbit.distance * (1.0 + new_orbit.orbit_deviation * 0.3)
			var new_min = new_orbit.distance * (1.0 - new_orbit.orbit_deviation * 0.3)
			
			var existing_max = orbit.distance * (1.0 + orbit.orbit_deviation * 0.3)
			var existing_min = orbit.distance * (1.0 - orbit.orbit_deviation * 0.3)
			
			# Check orbit shell gaps
			var outer_gap = new_min - existing_max
			var inner_gap = existing_min - new_max
			
			if (outer_gap < safe_distance and outer_gap > -safe_distance) or (inner_gap < safe_distance and inner_gap > -safe_distance):
				return true
	
	return false

func _get_moon_property(moon, property_name: String):
	# Extract moon type from instance
	var moon_type = MoonType.ROCKY  # Default
	
	if moon is MoonBase:
		var prefix = moon._get_moon_type_prefix()
		match prefix:
			"Volcanic": moon_type = MoonType.VOLCANIC
			"Icy": moon_type = MoonType.ICY
			"Rocky": moon_type = MoonType.ROCKY
	
	# Return the appropriate property
	match property_name:
		"color":
			return _moon_params.colors.get(moon_type, Color(1, 1, 1, 0.4))
		"z_index":
			return _moon_params.z_indices.get(moon_type, DEFAULT_Z_INDEX)
	
	return null

func _get_moon_type_prefix(moon_type: int) -> String:
	match moon_type:
		MoonType.ROCKY: return "Rocky"
		MoonType.ICY: return "Icy"
		MoonType.VOLCANIC: return "Volcanic"
	return "Moon"

func get_theme_name() -> String:
	# Return human-readable theme name
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
	return "Unknown"
#endregion

#region Virtual Methods (to be overridden by subclasses)
func _perform_specialized_initialization(_params: Dictionary) -> void:
	push_error("PlanetBase: _perform_specialized_initialization must be overridden")

func _get_moon_type_for_position(_position: int) -> int:
	return MoonType.ROCKY

func _get_orbit_speed_modifier() -> float:
	return 1.0

func _get_moon_size_scale() -> float:
	return 1.0

func _get_planet_type_name() -> String:
	return "Planet"
#endregion

#region Public API Methods
func toggle_orbit_debug(enabled: bool = true) -> void:
	debug_draw_orbits = enabled
	queue_redraw()

func set_orbit_line_width(width: float) -> void:
	debug_orbit_line_width = width
	queue_redraw()
#endregion
