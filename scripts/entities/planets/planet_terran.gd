# scripts/entities/planets/planet_terran.gd
# Specialized implementation for terran planets (rocky planets with solid surfaces)
extends PlanetBase
class_name PlanetTerran

# Additional terran-specific properties
var terran_subtype: String = ""  # Descriptive subtype (lush, desert, etc)

func _init() -> void:
	# Default max_moons value for terran planets is lower
	max_moons = 2
	moon_chance = 40  # 40% chance to have moons

# Override specialized initialization for terran planets
func _perform_specialized_initialization(params: Dictionary) -> void:
	# Create a local RNG for consistent random generation
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# Determine theme based on seed or override
	var explicit_theme = params.get("theme_override", -1)
	
	if explicit_theme >= 0 and explicit_theme < PlanetThemes.JUPITER:
		# Use the explicitly requested theme if it's a valid terran theme
		theme_id = explicit_theme
	else:
		# Generate a random terran theme
		theme_id = _determine_theme(seed_value)
	
	# Set the terran subtype for reference
	terran_subtype = get_theme_name().to_lower()
	
	# Generate or get planet textures
	_generate_planet_texture()
	
	# Generate or get atmosphere textures
	_generate_atmosphere_texture()
	
	# Set the pixel size for terran planets
	pixel_size = 256

# Determine theme based on seed - returns a valid terran theme
func _determine_theme(seed_val: int) -> int:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_val
	
	# Generate a random terran theme (0 to JUPITER-1)
	return rng.randi() % PlanetThemes.JUPITER

# Generate planet textures
func _generate_planet_texture() -> void:
	var unique_identifier = str(seed_value) + "_terran_" + str(theme_id)
	
	if use_texture_cache and PlanetGeneratorBase.texture_cache.has("terran") and PlanetGeneratorBase.texture_cache.terran.has(unique_identifier):
		# Use cached texture
		var textures = PlanetGeneratorBase.texture_cache.terran[unique_identifier]
		planet_texture = textures[0]
	else:
		# Generate new texture
		var generator = PlanetGeneratorTerran.new()
		var textures = generator.create_planet_texture(seed_value, theme_id)
		planet_texture = textures[0]
		
		# Cache the texture
		if use_texture_cache:
			if not PlanetGeneratorBase.texture_cache.has("terran"):
				PlanetGeneratorBase.texture_cache["terran"] = {}
			PlanetGeneratorBase.texture_cache.terran[unique_identifier] = textures

# Generate atmosphere texture
func _generate_atmosphere_texture() -> void:
	var atmosphere_generator = AtmosphereGenerator.new()
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

# TERRAN MOON CREATION: Moons orbit on a tilted equator
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
		
		# Determine moon type - for terran planets, mostly rocky moons, but allow variation
		var moon_type_roll = rng.randi() % 100
		var moon_type
		
		if moon_type_roll < 70:  # 70% chance for rocky moons
			moon_type = MoonType.ROCKY
		elif moon_type_roll < 85:  # 15% chance for icy moons
			moon_type = MoonType.ICY
		else:  # 15% chance for volcanic moons
			moon_type = MoonType.VOLCANIC
		
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
			"is_gaseous": false,  # Mark as terran planet moon
			"orbit_is_tilted": true,  # Mark as using tilted orbit
			"tilt_angle": orbital_params[m].tilt_angle,
			"tilt_amount": orbital_params[m].tilt_amount
		}
		
		add_child(moon_instance)
		moon_instance.initialize(moon_params)
		moons.append(moon_instance)
	
	# Emit signal that the planet has been loaded (after moons are created)
	emit_signal("planet_loaded", self)

# TERRAN MOON ORBITS: Update moon positions using tilted orbit model
func _update_moons(delta: float) -> void:
	var time = Time.get_ticks_msec() / 1000.0
	
	for moon in moons:
		if not is_instance_valid(moon):
			continue
		
		# Calculate the orbit angle based on time, speed and initial offset
		var moon_angle = moon.base_angle + time * moon.orbit_speed + moon.phase_offset
		
		# Calculate deviation for elliptical orbits using sine function
		var deviation_factor = sin(moon_angle * 2) * moon.orbit_deviation
		
		# Calculate untilted position
		var distance = moon.distance * (1.0 + deviation_factor * 0.3)
		var base_x = cos(moon_angle) * distance
		var base_y = sin(moon_angle) * distance
		
		# Apply tilt transformation if this moon uses tilted orbits
		# FIXED: Use get() instead of has() to check for property
		if moon.get("orbit_is_tilted", false):
			# Apply a 3D-like projection by modifying the y component based on tilt
			var tilt_effect = sin(moon_angle - moon.tilt_angle) * moon.tilt_amount
			base_y *= (1.0 - tilt_effect)
			
			# Add a slight x-adjustment for more realistic orbital appearance
			base_x *= (1.0 + abs(tilt_effect) * 0.1)
		
		# Set final position
		moon.global_position = global_position + Vector2(base_x, base_y)
		
		# Determine if moon is behind or in front of planet
		# When moon is in the "back half" of its orbit and tilted down, it should appear behind the planet
		var is_behind = false
		
		# FIXED: Use get() instead of has() to check for property
		if moon.get("orbit_is_tilted", false):
			# Calculate if moon is behind based on angle and tilt
			var relative_angle = fmod(moon_angle - moon.tilt_angle + TAU, TAU)
			var y_factor = sin(moon_angle)
			var tilt_factor = sin(moon_angle - moon.tilt_angle)
			
			# Moon is behind if (moving down in the back half of orbit) OR (moving up in front half of orbit with negative tilt)
			is_behind = (y_factor > 0 and tilt_factor < 0) or (y_factor < 0 and tilt_factor > 0)
		else:
			# Simpler calculation if no tilt (just back half of orbit)
			var relative_y = sin(moon_angle)
			is_behind = relative_y > 0
		
		# Set z-index dynamically based on position relative to planet
		# This creates the visual effect of moon passing behind the planet and atmosphere
		moon.z_index = -12 if is_behind else -9

# Override for orbit speed - terran planets have faster moon orbits
func _get_orbit_speed_modifier() -> float:
	return 1.0  # Standard speed for terran planets

# Override to return appropriate planet type name
func _get_planet_type_name() -> String:
	if theme_id >= 0 and theme_id < PlanetThemes.JUPITER:
		return get_theme_name()
	return "Terran"

# Return planet category
func get_category() -> int:
	return PlanetCategories.TERRAN

# Return category name as string (for debugging/UI)
func get_category_name() -> String:
	return "Terran"
