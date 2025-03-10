# scripts/entities/planets/planet_gaseous.gd
# Specialized implementation for gaseous planets (gas giants)
extends PlanetBase
class_name PlanetGaseous

# Moon ring settings
const INNER_RING_FACTOR = 1.3  # Distance factor for inner ring (volcanic moons)
const MIDDLE_RING_FACTOR = 1.5  # Distance factor for middle ring (rocky moons)
const OUTER_RING_FACTOR = 1.7  # Distance factor for outer ring (icy moons)

# Moon count settings for gas giants
const INNER_RING_MOONS = 2  # Number of volcanic moons in inner ring
const MIDDLE_RING_MOONS = 2  # Number of rocky moons in middle ring
const OUTER_RING_MOONS = 3  # Number of icy moons in outer ring

func _init() -> void:
	# Fixed number of moons for all gaseous planets
	max_moons = INNER_RING_MOONS + MIDDLE_RING_MOONS + OUTER_RING_MOONS
	moon_chance = 100  # Always have moons
	min_moon_distance_factor = 1.3  # Starting from atmosphere's edge
	max_moon_distance_factor = 1.8  # Maximum distance factor

# Override specialized initialization for gaseous planets
func _perform_specialized_initialization(params: Dictionary) -> void:
	# Create a local RNG for consistent random generation
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# For gaseous planets, determine specific theme
	var theme_override = params.get("theme_override", -1)
	
	# Handle backwards compatibility with old gas_giant_type_override parameter
	var gas_giant_type_override = params.get("gas_giant_type_override", -1)
	if gas_giant_type_override >= 0 and gas_giant_type_override < 4:
		# Map from the old style (0-3) to the new enum values
		theme_override = PlanetThemes.JUPITER + gas_giant_type_override
	
	# Set the theme based on parameters or randomize
	if theme_override >= PlanetThemes.JUPITER and theme_override <= PlanetThemes.NEPTUNE:
		# Valid gaseous planet theme provided
		theme_id = theme_override
	else:
		# Choose a random gaseous theme
		theme_id = PlanetThemes.JUPITER + rng.randi() % 4
	
	# Generate or get planet textures
	_generate_planet_texture()
	
	# Generate or get atmosphere textures
	_generate_atmosphere_texture()
	
	# Set the pixel size for gaseous planets (larger)
	pixel_size = 512

# Generate gas giant planet texture
func _generate_planet_texture() -> void:
	# Create a unique identifier that includes the theme
	var unique_identifier = str(seed_value) + "_theme_" + str(theme_id)
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.has("gaseous") and PlanetGeneratorBase.texture_cache.gaseous.has(unique_identifier):
		# Use cached texture
		var textures = PlanetGeneratorBase.texture_cache.gaseous[unique_identifier]
		planet_texture = textures[0]
	else:
		# Generate new texture using the specialized gaseous generator
		var generator = PlanetGeneratorGaseous.new()
		var textures = generator.create_planet_texture(seed_value, theme_id)
		planet_texture = textures[0]
		
		# Cache the texture
		if use_texture_cache:
			if not PlanetGeneratorBase.texture_cache.has("gaseous"):
				PlanetGeneratorBase.texture_cache["gaseous"] = {}
			PlanetGeneratorBase.texture_cache.gaseous[unique_identifier] = textures

# Generate atmosphere texture for gas giants
func _generate_atmosphere_texture() -> void:
	var atmosphere_generator = AtmosphereGenerator.new()
	
	# Pass the correct theme ID directly (no need for adjusted seed)
	atmosphere_data = atmosphere_generator.generate_atmosphere_data(theme_id, seed_value)
	
	var unique_identifier = str(seed_value) + "_atmo_" + str(theme_id)
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.has("atmospheres") and PlanetGeneratorBase.texture_cache.atmospheres.has(unique_identifier):
		# Use cached atmosphere texture
		atmosphere_texture = PlanetGeneratorBase.texture_cache.atmospheres[unique_identifier]
	else:
		# Generate new atmosphere texture
		atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
			theme_id, seed_value, atmosphere_data.color, atmosphere_data.thickness)
			
		# Cache the texture
		if use_texture_cache:
			if not PlanetGeneratorBase.texture_cache.has("atmospheres"):
				PlanetGeneratorBase.texture_cache["atmospheres"] = {}
			PlanetGeneratorBase.texture_cache.atmospheres[unique_identifier] = atmosphere_texture

# GASEOUS MOON CREATION: Create the ring-based moon system
func _create_moons() -> void:
	if _moon_scenes.is_empty():
		push_error("Planet: Moon scenes not available for moon creation")
		emit_signal("planet_loaded", self)
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Initialize ring data - always create the full moon system for gas giants
	var ring_data = [
		{
			"name": "Inner Ring",
			"distance_factor": INNER_RING_FACTOR,
			"max_moons": INNER_RING_MOONS,
			"moon_type": MoonType.VOLCANIC,
			"speed_factor": 1.3,  # Inner moons move faster
			"phase_spread": 0.7   # How spread out the moons are in the ring (0-1)
		},
		{
			"name": "Middle Ring",
			"distance_factor": MIDDLE_RING_FACTOR,
			"max_moons": MIDDLE_RING_MOONS,
			"moon_type": MoonType.ROCKY,
			"speed_factor": 1.0,  # Standard speed
			"phase_spread": 0.8
		},
		{
			"name": "Outer Ring",
			"distance_factor": OUTER_RING_FACTOR,
			"max_moons": OUTER_RING_MOONS,
			"moon_type": MoonType.ICY,
			"speed_factor": 0.7,  # Outer moons move slower
			"phase_spread": 0.9
		}
	]
	
	# Clear any existing moons
	moons.clear()
	
	# Calculate planet radius for reference
	var planet_radius = pixel_size / 2.0
	
	# Count for naming/uniqueness
	var moon_counter = 0
	
	# Create moons for each ring
	for ring in ring_data:
		var actual_moons = ring.max_moons
		
		# Determine actual moon count with some randomness
		if rng.randi() % 100 < 30:  # 30% chance to have 1 fewer moon than max
			actual_moons = max(1, ring.max_moons - 1)
		
		# Calculate base distance for this ring
		var ring_distance = planet_radius * ring.distance_factor
		
		# Create each moon in the ring
		for m in range(actual_moons):
			# Calculate unique seed for this moon
			var moon_seed = seed_value + moon_counter * 100 + rng.randi() % 1000
			moon_counter += 1
			
			# Generate a unique position in the ring by spreading phases
			var phase_offset = (m * TAU / actual_moons) * ring.phase_spread
			# Add randomness to make it look less perfectly arranged
			phase_offset += rng.randf_range(-0.1, 0.1)
			
			# Calculate speed based on distance and ring speed factor
			var orbit_speed = 0.3 * moon_orbit_factor * ring.speed_factor
			
			# Add slight distance variation within the ring
			var distance_variation = rng.randf_range(-0.05, 0.05)
			var distance = ring_distance * (1.0 + distance_variation)
			
			# Get the moon scene for this ring
			var moon_type = ring.moon_type
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
			
			# Configure the moon
			var moon_params = {
				"seed_value": moon_seed,
				"parent_planet": self,
				"distance": distance,
				"base_angle": 0.0,
				"orbit_speed": orbit_speed,
				"orbit_deviation": 0.0,  # No deviation for gas giant moons - perfect rings
				"phase_offset": phase_offset,
				"parent_name": planet_name,
				"use_texture_cache": use_texture_cache,
				"moon_type": moon_type,
				"is_gaseous": true,  # Mark that this is a gas giant moon
				"ring_name": ring.name  # Add ring identifier
			}
			
			add_child(moon_instance)
			moon_instance.initialize(moon_params)
			moons.append(moon_instance)
	
	# Emit signal that the planet has been loaded (after moons are created)
	emit_signal("planet_loaded", self)

# GASEOUS MOON ORBITS: Update moon positions using flat ring system
func _update_moons(delta: float) -> void:
	var time = Time.get_ticks_msec() / 1000.0
	
	for moon in moons:
		if not is_instance_valid(moon):
			continue
		
		# Calculate the orbit angle based on time, speed and initial offset
		var moon_angle = moon.base_angle + time * moon.orbit_speed + moon.phase_offset
		
		# For gas giants, we use perfect circular orbits (no deviation)
		# and moons are always in front of the planet
		
		# Calculate final position (simple circular orbit)
		var distance = moon.distance
		var moon_x = cos(moon_angle) * distance
		var moon_y = sin(moon_angle) * distance
		
		# Set the moon position
		moon.global_position = global_position + Vector2(moon_x, moon_y)
		
		# Gas giant moons ALWAYS appear in front of the planet
		moon.z_index = -9
	
		# Add a subtle "wobble" for visual interest
		var wobble_amount = 0.02
		var wobble_speed = 0.5
		var wobble = sin(time * wobble_speed + moon.phase_offset * 3) * wobble_amount
		moon.scale = Vector2(1.0 + wobble, 1.0 - wobble)

# Override for orbit speed - gas giants have slower orbiting moons due to mass
func _get_orbit_speed_modifier() -> float:
	return 0.7  # 30% slower than terran planets

# Override to return appropriate planet type name
func _get_planet_type_name() -> String:
	return PlanetGeneratorBase.get_theme_name(theme_id)

# Generate evenly distributed orbital parameters for moons
# NOTE: This is only used for backward compatibility
# Gas giants use _create_moons directly with the ring system
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
		# Improved spacing formula with REDUCED gaps between moons for gaseous planets
		for i in range(moon_count):
			# Use a LESS quadratic distribution to space moons closer together
			var t = float(i) / float(moon_count - 1)
			
			# More linear spacing to keep moons visibly grouped
			var distance_factor = min_distance + (max_distance - min_distance) * (t * 0.6 + t * t * 0.4)
			
			# Reduce the jitter to keep moons in more consistent orbits
			var jitter_range = 0.03  # Reduced jitter (was 0.05)
			var jitter = distance_factor * jitter_range * rng.randf_range(-1.0, 1.0)
			var distance = clamp(distance_factor + jitter, min_distance, max_distance)
			
			# Calculate orbital speed based on distance
			var speed_factor = 1.0 / sqrt(distance / min_distance)
			var orbit_speed = rng.randf_range(0.15, 0.3) * moon_orbit_factor * speed_factor * _get_orbit_speed_modifier()
			
			# Distribute phase offsets evenly around orbit
			var phase_offset = (i * TAU / float(moon_count)) + rng.randf_range(-0.1, 0.1)
			
			# Set orbit deviation (for elliptical orbits)
			var orbit_deviation = 0.0  # Gas giants have perfect circular orbits
			
			params.append({
				"distance": distance,
				"base_angle": 0.0,
				"orbit_speed": orbit_speed,
				"orbit_deviation": orbit_deviation,
				"phase_offset": phase_offset
			})
	else:
		# For a single moon, use simpler parameters
		params.append({
			"distance": rng.randf_range(min_distance, max_distance),
			"base_angle": 0.0,
			"orbit_speed": rng.randf_range(0.15, 0.3) * moon_orbit_factor * _get_orbit_speed_modifier(),
			"orbit_deviation": 0.0,
			"phase_offset": rng.randf_range(0, TAU) # Random starting position
		})
	
	return params

# Return planet category
func get_category() -> int:
	return PlanetCategories.GASEOUS

# Return category name as string (for debugging/UI)
func get_category_name() -> String:
	return "Gaseous"

# Get gas giant type name
func get_gas_giant_type_name() -> String:
	match theme_id:
		PlanetThemes.JUPITER: return "Jupiter-like"
		PlanetThemes.SATURN: return "Saturn-like"
		PlanetThemes.URANUS: return "Uranus-like"
		PlanetThemes.NEPTUNE: return "Neptune-like"
		_: return "Unknown Gas Giant"
