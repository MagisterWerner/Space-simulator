# scripts/entities/moon.gd
extends Node2D

var seed_value: int = 0
var pixel_size: int = 32
var moon_texture: Texture2D
var parent_planet = null
var distance: float = 0
var base_angle: float = 0
var orbit_speed: float = 0
var orbit_deviation: float = 0
var phase_offset: float = 0
var moon_name: String

var name_component

func _ready():
	name_component = get_node_or_null("NameComponent")
	# Set appropriate z-index to be behind player but may be in front or behind planet
	# The actual z-index will be dynamically adjusted by parent planet based on orbit position
	z_index = -9

func _process(_delta):
	queue_redraw()

func _draw():
	if moon_texture:
		draw_texture(moon_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)

func initialize(params: Dictionary):
	seed_value = params.seed_value
	parent_planet = params.parent_planet
	distance = params.distance
	base_angle = params.base_angle
	orbit_speed = params.orbit_speed
	orbit_deviation = params.orbit_deviation
	phase_offset = params.phase_offset
	
	var moon_data = _generate_moon_data(seed_value)
	moon_texture = moon_data.texture
	pixel_size = moon_data.pixel_size
	
	name_component = get_node_or_null("NameComponent")
	if name_component:
		name_component.initialize(seed_value, 0, 0, params.parent_name)
		moon_name = name_component.get_entity_name()
	else:
		moon_name = "Moon-" + str(seed_value % 1000)

func _generate_moon_data(moon_seed: int) -> Dictionary:
	var moon_generator = MoonGenerator.new()
	var texture = moon_generator.create_moon_texture(moon_seed)
	var size = moon_generator.get_moon_size(moon_seed)
	
	return {
		"texture": texture,
		"pixel_size": size
	}
