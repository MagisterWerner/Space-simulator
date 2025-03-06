# planet.gd
extends Node2D

signal planet_loaded(planet)

@export var max_moons: int = 2
@export var moon_chance: int = 40
@export var min_moon_distance_factor: float = 1.8
@export var max_moon_distance_factor: float = 2.5
@export var max_orbit_deviation: float = 0.15
@export var moon_orbit_factor: float = 0.05

# These properties will be set by PlanetGenerationManager
var seed_value: int = 0
var pixel_size: int = 256
var planet_texture: Texture2D
var atmosphere_texture: Texture2D
var theme_id: int
var planet_name: String = ""
var atmosphere_data: Dictionary
var moons: Array = []
var grid_x: int = 0
var grid_y: int = 0
var planet_gen_manager = null

func _ready():
	# Get reference to name component
	var name_component = get_node_or_null("NameComponent")
	planet_gen_manager = get_node_or_null("/root/PlanetGenerationManager")
	
	# Generate textures if not already set (fallback mechanism)
	if not planet_texture:
		_generate_planet_data()
	
	# Set up name if we have the component
	if name_component:
		if name_component.has_method("initialize"):
			name_component.initialize(seed_value, grid_x, grid_y)
			planet_name = name_component.get_entity_name()
		else:
			planet_name = "Planet-" + str(seed_value % 1000)
	else:
		planet_name = "Planet-" + str(seed_value % 1000)
	
	# Create moons after initialization
	call_deferred("_create_moons")
	z_index = 6
	
	# Emit signal that planet has loaded
	planet_loaded.emit(self)

func _process(delta):
	queue_redraw()
	_update_moons(delta)

func _draw():
	if atmosphere_texture:
		draw_texture(atmosphere_texture, -Vector2(atmosphere_texture.get_width(), atmosphere_texture.get_height()) / 2, Color.WHITE)
	
	if planet_texture:
		draw_texture(planet_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)

func _update_moons(delta):
	var time = Time.get_ticks_msec() / 1000.0
	
	for moon in moons:
		if is_instance_valid(moon):
			var moon_angle = moon.base_angle + time * moon.orbit_speed + moon.phase_offset
			var deviation_factor = sin(moon_angle) * moon.orbit_deviation
			
			moon.global_position = global_position + Vector2(
				cos(moon_angle) * moon.distance,
				sin(moon_angle) * moon.distance * (1.0 + deviation_factor)
			)
			
			moon.z_index = 10 if sin(moon_angle) <= 0 else 5

# Generate planet textures if they aren't set already
func _generate_planet_data() -> void:
	var planet_generator = PlanetGenerator.new()
	var textures = planet_generator.create_planet_texture(seed_value)
	
	var atmosphere_generator = AtmosphereGenerator.new()
	var theme = planet_generator.get_planet_theme(seed_value)
	var atm_data = atmosphere_generator.generate_atmosphere_data(theme, seed_value)
	var atm_texture = atmosphere_generator.generate_atmosphere_texture(
		theme, 
		seed_value,
		atm_data.color,
		atm_data.thickness
	)
	
	planet_texture = textures[0]
	theme_id = theme
	pixel_size = 256
	atmosphere_data = atm_data
	atmosphere_texture = atm_texture

func _create_moons():
	var moon_scene = load("res://scenes/world/moon.tscn")
	if not moon_scene:
		print("Error: Moon scene couldn't be loaded")
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var has_moons = rng.randi() % 100 < moon_chance
	var num_moons = rng.randi_range(1, max_moons) if has_moons else 0
	
	# Try to get pre-generated moon textures
	var moon_textures = []
	if planet_gen_manager and planet_gen_manager.initialized:
		moon_textures = planet_gen_manager.get_moon_textures_for_planet(seed_value, num_moons)
	
	for m in range(num_moons):
		var moon_seed = seed_value + m * 100
		var moon_texture = null
		var moon_size = 0
		
		# Use pre-generated texture if available
		if m < moon_textures.size():
			moon_texture = moon_textures[m].texture
			moon_size = moon_textures[m].size
		
		var moon_instance = moon_scene.instantiate()
		if not moon_instance:
			continue
			
		var min_distance = pixel_size / 2.0 * min_moon_distance_factor
		var max_distance = pixel_size / 2.0 * max_moon_distance_factor
		
		# Set up moon properties
		moon_instance.seed_value = moon_seed
		moon_instance.parent_planet = self
		moon_instance.distance = rng.randf_range(min_distance, max_distance)
		moon_instance.base_angle = rng.randf_range(0, TAU)
		moon_instance.orbit_speed = rng.randf_range(0.2, 0.5) * moon_orbit_factor
		moon_instance.orbit_deviation = rng.randf_range(-max_orbit_deviation, max_orbit_deviation)
		moon_instance.phase_offset = rng.randf_range(0, TAU)
		
		if moon_texture:
			moon_instance.moon_texture = moon_texture
			moon_instance.pixel_size = moon_size
		
		add_child(moon_instance)
		moons.append(moon_instance)
