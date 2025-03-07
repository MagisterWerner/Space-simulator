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

func _update_moons(_delta: float) -> void:
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
	grid_x = params.grid_x
	grid_y = params.grid_y
	
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
	
	# Allow theme override if specified
	if "theme_override" in params and params.theme_override >= 0:
		theme_id = params.theme_override
	else:
		# Determine theme from seed
		var planet_generator = PlanetGenerator.new()
		theme_id = planet_generator.get_planet_theme(seed_value)
	
	# Determine planet category based on theme
	planet_category = PlanetGenerator.get_planet_category(theme_id)
	
	# Check if specific category was requested
	if "category_override" in params:
		planet_category = params.category_override
		# Need to adjust theme if category changed
		if planet_category == PlanetCategories.GASEOUS:
			theme_id = PlanetThemes.GAS_GIANT  # Currently the only gaseous type
		elif planet_category == PlanetCategories.TERRAN and theme_id == PlanetThemes.GAS_GIANT:
			# If we need a terran planet but had gas giant theme, pick a random terran theme
			var planet_generator = PlanetGenerator.new()
			theme_id = planet_generator.get_themed_planet_for_category(seed_value, PlanetCategories.TERRAN)
	
	# For convenience, detect if this is a gaseous planet
	var is_gaseous = planet_category == PlanetCategories.GASEOUS
	
	# Adjust moon parameters based on planet category
	if is_gaseous:
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value + 12345
		# Gaseous planets always have 3-6 moons
		max_moons = rng.randi_range(3, 6)
		moon_chance = 100  # Gaseous planets ALWAYS have moons
	
	# Attempt to use cached textures if texture caching is enabled
	if use_texture_cache and PlanetSpawner.texture_cache != null:
		# Try to get planet texture from cache
		if PlanetSpawner.texture_cache.planets.has(seed_value):
			planet_texture = PlanetSpawner.texture_cache.planets[seed_value]
			pixel_size = 512 if is_gaseous else 256
		else:
			# Generate and cache the texture
			var planet_generator = PlanetGenerator.new()
			var textures = planet_generator.create_planet_texture(seed_value)
			planet_texture = textures[0]
			pixel_size = 512 if is_gaseous else 256
			PlanetSpawner.texture_cache.planets[seed_value] = planet_texture
		
		# Try to get atmosphere texture from cache
		if PlanetSpawner.texture_cache.atmospheres.has(seed_value):
			atmosphere_texture = PlanetSpawner.texture_cache.atmospheres[seed_value]
		else:
			# Generate and cache the texture
			var atmosphere_generator = AtmosphereGenerator.new()
			atmosphere_data = atmosphere_generator.generate_atmosphere_data(theme_id, seed_value)
			atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
				theme_id, seed_value, atmosphere_data.color, atmosphere_data.thickness)
			PlanetSpawner.texture_cache.atmospheres[seed_value] = atmosphere_texture
	else:
		# Generate textures without caching
		var planet_gen_params = _generate_planet_data(seed_value)
		
		theme_id = planet_gen_params.theme if not "theme_override" in params else params.theme_override
		pixel_size = planet_gen_params.pixel_size
		planet_texture = planet_gen_params.texture
		atmosphere_data = planet_gen_params.atmosphere
		atmosphere_texture = planet_gen_params.atmosphere_texture
		planet_category = PlanetGenerator.get_planet_category(theme_id)
	
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

func _emit_planet_loaded() -> void:
	planet_loaded.emit(self)

func _generate_planet_data(planet_seed: int) -> Dictionary:
	var planet_generator = PlanetGenerator.new()
	var theme = planet_generator.get_planet_theme(planet_seed)
	var category = PlanetGenerator.get_planet_category(theme)
	
	var textures = planet_generator.create_planet_texture(planet_seed)
	
	var atmosphere_generator = AtmosphereGenerator.new()
	var atm_data = atmosphere_generator.generate_atmosphere_data(theme, planet_seed)
	var atm_texture = atmosphere_generator.generate_atmosphere_texture(
		theme, 
		planet_seed,
		atm_data.color,
		atm_data.thickness
	)
	
	return {
		"texture": textures[0],
		"theme": theme,
		"pixel_size": (512 if category == PlanetCategories.GASEOUS else 256),
		"atmosphere": atm_data,
		"atmosphere_texture": atm_texture
	}

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

# Get a random moon type with proper weighting
func _get_random_moon_type(rng: RandomNumberGenerator) -> int:
	# For terran planets, always return ROCKY
	if planet_category == PlanetCategories.TERRAN:
		return MoonType.ROCKY
	
	# This can be kept for backward compatibility or custom distribution
	var roll = rng.randi() % 100
	
	if roll < 60:
		return MoonType.ROCKY
	elif roll < 80:
		return MoonType.ICE
	else:
		return MoonType.LAVA

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
