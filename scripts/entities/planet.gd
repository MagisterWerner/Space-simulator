# scripts/entities/planet.gd
extends Node2D

# Import classification constants
const PlanetThemes = preload("res://scripts/generators/planet_generator.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator.gd").PlanetCategory

signal planet_loaded(planet)

@export var max_moons: int = 2
@export var moon_chance: int = 40
@export var min_moon_distance_factor: float = 1.8
@export var max_moon_distance_factor: float = 2.5
@export var max_orbit_deviation: float = 0.15
@export var moon_orbit_factor: float = 0.05

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

# Planet classification properties
var planet_category: int = PlanetCategories.TERRAN  # Default to terran

# Define moon types for consistent reference
enum MoonType {
	ROCKY,
	ICE,
	LAVA
}

# Gas giant types
enum GasGiantType {
	JUPITER = 0,
	SATURN = 1,
	NEPTUNE = 2,
	EXOTIC = 3
}

# Track the gas giant type for gaseous planets
var gas_giant_type: int = -1

var name_component
var use_texture_cache: bool = true

func _ready() -> void:
	name_component = get_node_or_null("NameComponent")
	# Set appropriate z-index to render behind player but in front of atmosphere
	z_index = -10

func _process(delta: float) -> void:
	queue_redraw()
	_update_moons(delta)

func _draw() -> void:
	if atmosphere_texture:
		# Draw atmosphere first so it's behind the planet
		draw_texture(atmosphere_texture, -Vector2(atmosphere_texture.get_width(), atmosphere_texture.get_height()) / 2, Color.WHITE)
	
	if planet_texture:
		draw_texture(planet_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)

func _update_moons(delta: float) -> void:
	var time = Time.get_ticks_msec() / 1000.0
	
	for moon in moons:
		if is_instance_valid(moon):
			# Calculate the orbit angle based on time, speed and initial offset
			var moon_angle = moon.base_angle + time * moon.orbit_speed + moon.phase_offset
			
			# Calculate deviation for elliptical orbits using sine function
			var deviation_factor = sin(moon_angle * 2) * moon.orbit_deviation
			
			# Calculate moon position using parametric equation of ellipse
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

func initialize(params: Dictionary) -> void:
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
	
	# Create a local RNG for consistent random generation
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# ===== STEP 1: DETERMINE PLANET CATEGORY (TERRAN OR GASEOUS) =====
	# Always respect the category override parameter if provided
	if "category_override" in params:
		planet_category = params.category_override
	else:
		# If no category specified, use the correct lookup based on theme or randomly determine
		var planet_generator = PlanetGenerator.new()
		var auto_theme = planet_generator.get_planet_theme(seed_value)
		planet_category = PlanetGenerator.get_planet_category(auto_theme)
	
	# Debug the category choice
	print("Planet category set to: ", "Gaseous" if planet_category == PlanetCategories.GASEOUS else "Terran")
	
	# ===== STEP 2: DETERMINE THEME BASED ON CATEGORY =====
	# We need very explicit handling here to fix the issues
	if planet_category == PlanetCategories.TERRAN:
		# TERRAN PLANET THEME SELECTION
		if "theme_override" in params and params.theme_override >= 0 and params.theme_override < PlanetThemes.GAS_GIANT:
			# Use explicitly provided terran theme
			theme_id = params.theme_override
			print("Using explicit terran theme: ", theme_id)
		else:
			# Generate a truly random terran theme with improved entropy
			var theme_generator = RandomNumberGenerator.new()
			
			# Create a better unique seed for each planet
			var unique_seed = seed_value
			
			# Add grid position entropy
			if "grid_x" in params and "grid_y" in params:
				unique_seed = unique_seed ^ (params.grid_x * 31 + params.grid_y * 37)
			
			# Mix in more bit variation with prime multipliers
			unique_seed = unique_seed ^ (seed_value * 73 + 9973)
			
			theme_generator.seed = unique_seed
			theme_id = theme_generator.randi() % PlanetThemes.GAS_GIANT
			print("Generated random terran theme: ", theme_id, " from unique seed: ", unique_seed)
	else:
		# GASEOUS PLANET - Always GAS_GIANT theme
		theme_id = PlanetThemes.GAS_GIANT
		
		# Determine gas giant type - this is critical to fix the issue
		if "gas_giant_type_override" in params and params.gas_giant_type_override >= 0 and params.gas_giant_type_override < 4:
			# Use explicitly provided gas giant type
			gas_giant_type = params.gas_giant_type_override
			print("Using explicit gas giant type: ", gas_giant_type)
		else:
			# Generate a truly random gas giant type
			var type_generator = RandomNumberGenerator.new()
			type_generator.seed = seed_value ^ 54321  # Different seed than theme
			gas_giant_type = type_generator.randi() % 4
			print("Generated random gas giant type: ", gas_giant_type)
	
	# Log the selected theme and type for debugging
	print("Final planet theme: ", theme_id, " (", _get_theme_name(theme_id), ")")
	if planet_category == PlanetCategories.GASEOUS:
		print("Gas giant type: ", gas_giant_type, " (", _get_gas_giant_type_name(gas_giant_type), ")")
	
	# For convenience, detect if this is a gaseous planet
	var is_gaseous = planet_category == PlanetCategories.GASEOUS
	
	# Adjust moon parameters based on planet category
	if is_gaseous:
		# Gaseous planets always have 3-6 moons
		var moon_rng = RandomNumberGenerator.new()
		moon_rng.seed = seed_value ^ 789  # Separate seed for moon count
		max_moons = moon_rng.randi_range(3, 6)
		moon_chance = 100  # Gaseous planets ALWAYS have moons
	
	# ===== STEP 3: GENERATE PLANET TEXTURES =====
	# For gas giants, incorporate the type into the seed to ensure different appearances
	
	if planet_category == PlanetCategories.GASEOUS:
		# Add gas giant type to seed to ensure different types look different
		var adjusted_seed = seed_value + (gas_giant_type * 10000)
		
		# Check if we can use the cache
		if use_texture_cache and PlanetSpawner.texture_cache != null:
			var cache_key = str(adjusted_seed) + "_gas_" + str(gas_giant_type)
			
			if PlanetSpawner.texture_cache.has(cache_key):
				planet_texture = PlanetSpawner.texture_cache[cache_key]
			else:
				# Create a gas giant planet with type-dependent appearance
				var planet_generator = PlanetGenerator.new()
				var textures
				# If this planet_generator has a create_gas_giant_planet method that accepts a type
				if planet_generator.has_method("create_gas_giant_planet"):
					textures = planet_generator.create_gas_giant_planet(adjusted_seed, gas_giant_type)
				else:
					# Fallback to standard method but with adjusted seed
					textures = planet_generator.create_planet_texture(adjusted_seed, theme_id)
				planet_texture = textures[0]
				PlanetSpawner.texture_cache[cache_key] = planet_texture
			
			# Also handle atmosphere texture
			if PlanetSpawner.texture_cache.atmospheres.has(adjusted_seed):
				atmosphere_texture = PlanetSpawner.texture_cache.atmospheres[adjusted_seed]
			else:
				# Generate and cache the texture - use the adjusted seed that incorporates gas giant type
				var atmosphere_generator = AtmosphereGenerator.new()
				atmosphere_data = atmosphere_generator.generate_atmosphere_data(theme_id, adjusted_seed)
				atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
					theme_id, adjusted_seed, atmosphere_data.color, atmosphere_data.thickness)
				PlanetSpawner.texture_cache.atmospheres[adjusted_seed] = atmosphere_texture
			
			pixel_size = 512  # Gas giants are larger
		else:
			# Generate without caching
			var planet_generator = PlanetGenerator.new()
			var textures
			# Try to use gas giant specific method if available
			if planet_generator.has_method("create_gas_giant_planet"):
				textures = planet_generator.create_gas_giant_planet(adjusted_seed, gas_giant_type)
			else:
				# Fallback to standard method with adjusted seed
				textures = planet_generator.create_planet_texture(adjusted_seed, theme_id)
			planet_texture = textures[0]
			
			var atmosphere_generator = AtmosphereGenerator.new()
			atmosphere_data = atmosphere_generator.generate_atmosphere_data(theme_id, adjusted_seed)
			atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
				theme_id, adjusted_seed, atmosphere_data.color, atmosphere_data.thickness)
			
			pixel_size = 512  # Gas giants are larger
	else:
		# TERRAN PLANET TEXTURE GENERATION
		# Standard texture generation for terran planets
		if use_texture_cache and PlanetSpawner.texture_cache != null:
			# Try to get planet texture from cache
			var cache_key = str(seed_value) + "_terran_" + str(theme_id)
			
			if PlanetSpawner.texture_cache.planets.has(cache_key):
				planet_texture = PlanetSpawner.texture_cache.planets[cache_key]
			else:
				# Generate and cache the texture
				var planet_generator = PlanetGenerator.new()
				var textures = planet_generator.create_planet_texture(seed_value, theme_id)
				planet_texture = textures[0]
				PlanetSpawner.texture_cache.planets[cache_key] = planet_texture
			
			# Try to get atmosphere texture from cache
			if PlanetSpawner.texture_cache.atmospheres.has(cache_key):
				atmosphere_texture = PlanetSpawner.texture_cache.atmospheres[cache_key]
			else:
				# Generate and cache the texture
				var atmosphere_generator = AtmosphereGenerator.new()
				atmosphere_data = atmosphere_generator.generate_atmosphere_data(theme_id, seed_value)
				atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
					theme_id, seed_value, atmosphere_data.color, atmosphere_data.thickness)
				PlanetSpawner.texture_cache.atmospheres[cache_key] = atmosphere_texture
			
			pixel_size = 256  # Terran planets are smaller
		else:
			# Generate without caching
			var planet_generator = PlanetGenerator.new()
			var textures = planet_generator.create_planet_texture(seed_value, theme_id)
			planet_texture = textures[0]
			
			var atmosphere_generator = AtmosphereGenerator.new()
			atmosphere_data = atmosphere_generator.generate_atmosphere_data(theme_id, seed_value)
			atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
				theme_id, seed_value, atmosphere_data.color, atmosphere_data.thickness)
			
			pixel_size = 256  # Terran planets are smaller
	
	# ===== STEP 4: SET UP NAME AND FINISH INITIALIZATION =====
	# Set up name component
	name_component = get_node_or_null("NameComponent")
	if name_component:
		var type_prefix = ""
		if is_gaseous:
			type_prefix = "Gas Giant"
		name_component.initialize(seed_value, grid_x, grid_y, "", type_prefix)
		planet_name = name_component.get_entity_name()
	else:
		# Fallback naming if no name component
		if is_gaseous:
			planet_name = "Gas Giant-" + str(seed_value % 1000)
		else:
			planet_name = "Planet-" + str(seed_value % 1000)
	
	# Defer moon creation to avoid stuttering
	call_deferred("_create_moons")

# Method to get gas giant type name
func _get_gas_giant_type_name(type_id: int) -> String:
	match type_id:
		GasGiantType.JUPITER: return "Jupiter-like"
		GasGiantType.SATURN: return "Saturn-like"
		GasGiantType.NEPTUNE: return "Neptune-like"
		GasGiantType.EXOTIC: return "Exotic"
		_: return "Unknown"

# Method to get theme name
func _get_theme_name(theme_id: int) -> String:
	match theme_id:
		PlanetThemes.ARID: return "Arid"
		PlanetThemes.ICE: return "Ice"
		PlanetThemes.LAVA: return "Lava"
		PlanetThemes.LUSH: return "Lush"
		PlanetThemes.DESERT: return "Desert"
		PlanetThemes.ALPINE: return "Alpine"
		PlanetThemes.OCEAN: return "Ocean"
		PlanetThemes.GAS_GIANT: return "Gas Giant"
		_: return "Unknown"

# Get the gas giant type - for external access
func get_gas_giant_type() -> int:
	return gas_giant_type

func _emit_planet_loaded() -> void:
	planet_loaded.emit(self)

# Create moons for this planet
func _create_moons() -> void:
	# Use the correct path to moon scene
	var moon_scene = load("res://scenes/world/moon.tscn")
	if not moon_scene:
		push_error("Error: Moon scene couldn't be loaded from res://scenes/world/moon.tscn")
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	# For gaseous planets, always spawn moons. For other planets, check chance.
	var is_gaseous = planet_category == PlanetCategories.GASEOUS
	var has_moons = is_gaseous || (rng.randi() % 100 < moon_chance)
	var num_moons = 0
	
	if has_moons:
		if is_gaseous:
			# Gaseous planets always have 3-6 moons
			num_moons = max_moons  # We already set this to rng.randi_range(3, 6) in initialize()
		else:
			# Terran planets can have 1-max_moons
			num_moons = rng.randi_range(1, max_moons)
	
	# If no moons, exit early
	if num_moons <= 0:
		_emit_planet_loaded()
		return
	
	# Generate orbital parameters for all moons to prevent collisions
	var orbital_params = _generate_orbital_parameters(num_moons, rng)
	
	for m in range(num_moons):
		var moon_seed = seed_value + m * 100 + rng.randi() % 1000
		
		var moon_instance = moon_scene.instantiate()
		if not moon_instance:
			continue
		
		# Determine moon type based on planet category and orbital position
		var moon_type = MoonType.ROCKY  # Default for all moons
		
		if is_gaseous:
			# Apply the specific distribution pattern for gaseous planets:
			# - Innermost moon (m=0): LAVA (volcanic due to tidal forces)
			# - Second moon (m=1): ROCKY
			# - Outer moons (m>=2): ICE (colder as they're further away)
			if m == 0:
				moon_type = MoonType.LAVA
			elif m == 1:
				moon_type = MoonType.ROCKY
			else:
				moon_type = MoonType.ICE
		else:
			# Terran planets can only have rocky moons (for now)
			moon_type = MoonType.ROCKY
		
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
			"moon_type": moon_type  # Apply the moon type we determined
		}
		
		add_child(moon_instance)
		moon_instance.initialize(moon_params)
		moons.append(moon_instance)
	
	# Emit signal that the planet has been loaded (after moons are created)
	_emit_planet_loaded()

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
	
	# For gaseous planets, expand the orbital range for moons
	if planet_category == PlanetCategories.GASEOUS:
		max_distance = planet_radius * (max_moon_distance_factor + 0.5)
	
	# For multiple moons, use intelligent parameter distribution
	if moon_count > 1:
		# Step 1: Calculate distances with spacing to avoid crowding
		var distance_step = (max_distance - min_distance) / (moon_count)
		
		for i in range(moon_count):
			# Apply even spacing with a little randomness
			var base_distance = min_distance + i * distance_step
			var jitter = distance_step * 0.2 * rng.randf_range(-1.0, 1.0)
			var distance = clamp(base_distance + jitter, min_distance, max_distance)
			
			# Step 2: Calculate orbital speed based on distance (Kepler's law)
			# Closer moons orbit faster (sqrt relationship)
			var speed_factor = 1.0 / sqrt(distance / min_distance)
			
			# Gaseous planets have slower orbiting moons due to greater mass
			var orbit_modifier = 0.8 if planet_category == PlanetCategories.GASEOUS else 1.0
			var orbit_speed = rng.randf_range(0.2, 0.4) * moon_orbit_factor * speed_factor * orbit_modifier
			
			# Step 3: Distribute phase offsets evenly around orbit
			# This ensures moons start at different positions
			var phase_offset = (i * TAU / moon_count) + rng.randf_range(-0.2, 0.2)
			
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
			"orbit_speed": rng.randf_range(0.2, 0.5) * moon_orbit_factor * (0.8 if planet_category == PlanetCategories.GASEOUS else 1.0),
			"orbit_deviation": rng.randf_range(0.05, max_orbit_deviation),
			"phase_offset": rng.randf_range(0, TAU) # Random starting position
		})
	
	return params

# Get planet category name as string (for debugging/UI)
func get_category_name() -> String:
	match planet_category:
		PlanetCategories.TERRAN: return "Terran"
		PlanetCategories.GASEOUS: return "Gaseous"
		_: return "Unknown"

# Get theme name as string (for debugging/UI)
func get_theme_name() -> String:
	return _get_theme_name(theme_id)

# Get gas giant type name as string (for debugging/UI)
func get_gas_giant_type_name() -> String:
	if planet_category != PlanetCategories.GASEOUS:
		return "Not a Gas Giant"
	return _get_gas_giant_type_name(gas_giant_type)
