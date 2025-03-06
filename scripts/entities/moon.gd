# moon.gd
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
var moon_name: String = ""

func _ready():
	var name_component = get_node_or_null("NameComponent")
	
	# Generate moon texture if not already set
	if not moon_texture:
		var moon_data = _generate_moon_data(seed_value)
		moon_texture = moon_data.texture
		pixel_size = moon_data.pixel_size
	
	# Initialize name component if available
	if name_component and parent_planet:
		var parent_name = ""
		if parent_planet and parent_planet.has_method("get"):
			parent_name = parent_planet.planet_name
		
		if name_component.has_method("initialize"):
			name_component.initialize(seed_value, 0, 0, parent_name)
			moon_name = name_component.get_entity_name()
		else:
			moon_name = "Moon-" + str(seed_value % 1000)
	else:
		moon_name = "Moon-" + str(seed_value % 1000)

func _process(_delta):
	queue_redraw()

func _draw():
	if moon_texture:
		draw_texture(moon_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)

func _generate_moon_data(seed_value: int) -> Dictionary:
	var moon_generator = MoonGenerator.new()
	var texture = moon_generator.create_moon_texture(seed_value)
	var size = moon_generator.get_moon_size(seed_value)
	
	return {
		"texture": texture,
		"pixel_size": size
	}
