# planet.gd
extends Node2D

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

var name_component

func _ready():
	name_component = get_node_or_null("NameComponent")

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

func initialize(params: Dictionary):
	seed_value = params.seed_value
	grid_x = params.grid_x
	grid_y = params.grid_y
	
	if "max_moons" in params: max_moons = params.max_moons
	if "moon_chance" in params: moon_chance = params.moon_chance
	if "min_moon_distance_factor" in params: min_moon_distance_factor = params.min_moon_distance_factor
	if "max_moon_distance_factor" in params: max_moon_distance_factor = params.max_moon_distance_factor
	if "max_orbit_deviation" in params: max_orbit_deviation = params.max_orbit_deviation
	if "moon_orbit_factor" in params: moon_orbit_factor = params.moon_orbit_factor
	
	var planet_gen_params = _generate_planet_data(seed_value)
	theme_id = planet_gen_params.theme
	pixel_size = planet_gen_params.pixel_size
	planet_texture = planet_gen_params.texture
	atmosphere_data = planet_gen_params.atmosphere
	atmosphere_texture = planet_gen_params.atmosphere_texture
	
	name_component = get_node_or_null("NameComponent")
	if name_component:
		name_component.initialize(seed_value, grid_x, grid_y)
		planet_name = name_component.get_entity_name()
	else:
		planet_name = "Planet-" + str(seed_value % 1000)
	
	call_deferred("_create_moons")
	z_index = 6
	
	emit_signal("planet_loaded", self)

func _generate_planet_data(seed_value: int) -> Dictionary:
	var planet_generator = PlanetGenerator.new()
	var textures = planet_generator.create_planet_texture(seed_value)
	
	var atmosphere_generator = AtmosphereGenerator.new()
	var theme = planet_generator.get_planet_theme(seed_value)
	var atmosphere_data = atmosphere_generator.generate_atmosphere_data(theme, seed_value)
	var atmosphere_texture = atmosphere_generator.generate_atmosphere_texture(
		theme, 
		seed_value,
		atmosphere_data.color,
		atmosphere_data.thickness
	)
	
	return {
		"texture": textures[0],
		"theme": theme,
		"pixel_size": 256,
		"atmosphere": atmosphere_data,
		"atmosphere_texture": atmosphere_texture
	}

func _create_moons():
	var moon_scene = load("res://scenes/moon.tscn")
	if not moon_scene:
		print("Error: Moon scene couldn't be loaded")
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var has_moons = rng.randi() % 100 < moon_chance
	var num_moons = rng.randi_range(1, max_moons) if has_moons else 0
	
	for m in range(num_moons):
		var moon_seed = seed_value + m * 100
		
		var moon_instance = moon_scene.instantiate()
		if not moon_instance:
			continue
			
		var min_distance = pixel_size / 2.0 * min_moon_distance_factor
		var max_distance = pixel_size / 2.0 * max_moon_distance_factor
		
		var moon_params = {
			"seed_value": moon_seed,
			"parent_planet": self,
			"distance": rng.randf_range(min_distance, max_distance),
			"base_angle": rng.randf_range(0, TAU),
			"orbit_speed": rng.randf_range(0.2, 0.5) * moon_orbit_factor,
			"orbit_deviation": rng.randf_range(-max_orbit_deviation, max_orbit_deviation),
			"phase_offset": rng.randf_range(0, TAU),
			"parent_name": planet_name
		}
		
		add_child(moon_instance)
		moon_instance.initialize(moon_params)
		moons.append(moon_instance)
