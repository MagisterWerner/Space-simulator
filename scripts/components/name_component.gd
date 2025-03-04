# name_component.gd
extends Node
class_name NameComponent

@export_enum("planet", "moon") var entity_type: String = "planet"
@export var name_color: Color = Color(1, 1, 1, 1)
@export var display_height: float = 30.0
@export var font_size: int = 16

var entity_name: String = ""
var parent_name: String = ""

func _ready():
	set_process(true)

func _process(_delta):
	queue_redraw()

func _draw():
	if entity_name.is_empty():
		return
	
	var text = entity_name
	var text_size = ThemeDB.fallback_font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos = Vector2(-text_size.x / 2, -display_height)
	
	draw_string(
		ThemeDB.fallback_font,
		text_pos,
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		-1,
		font_size,
		name_color
	)

func initialize(seed_value: int, grid_x: int = 0, grid_y: int = 0, parent: String = ""):
	parent_name = parent
	
	if entity_type == "planet":
		entity_name = _generate_planet_name(seed_value, grid_x, grid_y)
	else:
		entity_name = _generate_moon_name(seed_value, parent)

func get_name() -> String:
	return entity_name

func _generate_planet_name(seed_value: int, x: int, y: int) -> String:
	var consonants = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"]
	var vowels = ["a", "e", "i", "o", "u"]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + (x * 100) + y
	
	var planet_name = ""

	planet_name += consonants[rng.randi() % consonants.size()].to_upper()
	planet_name += vowels[rng.randi() % vowels.size()]
	planet_name += consonants[rng.randi() % consonants.size()]
	planet_name += vowels[rng.randi() % vowels.size()]

	if rng.randi() % 2 == 0:
		planet_name += "-"
		planet_name += consonants[rng.randi() % consonants.size()].to_upper()
		planet_name += vowels[rng.randi() % vowels.size()]
	else:
		planet_name += " " + str((x + y) % 9 + 1)

	return planet_name

func _generate_moon_name(seed_value: int, parent_planet_name: String) -> String:
	var consonants = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"]
	var vowels = ["a", "e", "i", "o", "u"]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var moon_name = ""

	moon_name += consonants[rng.randi() % consonants.size()].to_upper()
	moon_name += vowels[rng.randi() % vowels.size()]
	moon_name += consonants[rng.randi() % consonants.size()]
	
	if parent_planet_name and !parent_planet_name.is_empty():
		var prefix = parent_planet_name.split(" ")[0].split("-")[0]
		moon_name = prefix + "-" + moon_name
	
	return moon_name
