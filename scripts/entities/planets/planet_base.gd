# scripts/entities/planets/planet_base.gd
extends Node2D
class_name PlanetBase

# Existing signal declarations
signal planet_loaded(planet)

# Constants and Enums
const PlanetThemes = preload("res://scripts/generators/planet_generator_base.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator_base.gd").PlanetCategory
const DEFAULT_Z_INDEX: int = -7

enum MoonType { ROCKY, ICY, VOLCANIC }

# Planet properties
var seed_value: int = 0
var planet_texture: Texture2D
var atmosphere_texture: Texture2D
var theme_id: int
var planet_name: String
var pixel_size: int = 256
var moons = []
var is_gaseous_planet: bool = false
var use_texture_cache: bool = true
var debug_planet_generation: bool = false
var grid_x: int = 0
var grid_y: int = 0
var atmosphere_data: Dictionary = {}

# Moon orbit properties
var max_moons: int = 2
var moon_chance: int = 40
var min_moon_distance_factor: float = 1.8
var max_moon_distance_factor: float = 2.5
var max_orbit_deviation: float = 0.15
var moon_orbit_factor: float = 0.05

# Debug options
var debug_draw_orbits: bool = false
var debug_orbit_line_width: float = 1.0

# Moon configuration by type
var _moon_params = {
	"distance_ranges": {
		MoonType.VOLCANIC: Vector2(1.3, 1.6),
		MoonType.ROCKY: Vector2(1.9, 2.2),
		MoonType.ICY: Vector2(2.5, 3.0)
	},
	"speed_modifiers": {
		MoonType.VOLCANIC: 1.4,
		MoonType.ROCKY: 1.0,
		MoonType.ICY: 0.7
	},
	"colors": {
		MoonType.VOLCANIC: Color(1.0, 0.3, 0.0, 0.4),
		MoonType.ROCKY: Color(0.7, 0.7, 0.7, 0.4),
		MoonType.ICY: Color(0.5, 0.8, 1.0, 0.4)
	},
	"z_indices": {
		MoonType.VOLCANIC: -6,
		MoonType.ROCKY: -7,
		MoonType.ICY: -8
	}
}

# Moon scene references
var _moon_scenes = {}
var _initialized: bool = false

func _ready() -> void:
	z_index = -10
	_load_moon_scenes()
	
	if Engine.has_singleton("SeedManager") and not SeedManager.is_connected("seed_changed", _on_seed_changed):
		SeedManager.connect("seed_changed", _on_seed_changed)

func _process(delta: float) -> void:
	queue_redraw()
	_update_moons(delta)

# Setup from data method
func setup_from_data(planet_data: PlanetData) -> void:
	if _initialized:
		return
		
	# Set core planet properties
	seed_value = planet_data.seed_value
	grid_x = planet_data.grid_cell.x
	grid_y = planet_data.grid_cell.y
	is_gaseous_planet = planet_data.is_gaseous
	theme_id = planet_data.planet_theme
	planet_name = planet_data.planet_name
	pixel_size = planet_data.pixel_size
	atmosphere_data = planet_data.atmosphere_data
	
	# Generate textures
	_generate_planet_texture()
	_generate_atmosphere_texture()
	
	# Create moons
	for moon_data in planet_data.moons:
		_create_moon_from_data(moon_data)
	
	_initialized = true
	planet_loaded.emit(self)

# Create moon from MoonData
func _create_moon_from_data(moon_data: MoonData) -> Node:
	# Get the appropriate scene for this moon type
	var scene_key = "moon_base"
	match moon_data.moon_type:
		MoonType.ROCKY: scene_key = "moon_rocky"
		MoonType.ICY: scene_key = "moon_icy" 
		MoonType.VOLCANIC: scene_key = "moon_volcanic"
	
	# Fall back to base moon if needed
	if not _moon_scenes.has(scene_key):
		scene_key = "moon_base"
		
	if not _moon_scenes.has(scene_key):
		push_error("PlanetBase: Moon scene not found")
		return null
	
	# Instantiate the moon
	var moon = _moon_scenes[scene_key].instantiate()
	add_child(moon)
	
	# Set up the moon with its data
	if moon.has_method("setup_from_data"):
		moon.setup_from_data(moon_data)
	
	# Add to moons array
	moons.append(moon)
	
	return moon

# Load moon scenes
func _load_moon_scenes() -> void:
	var scenes = {
		"moon_base": "res://scenes/world/moon_base.tscn",
		"moon_rocky": "res://scenes/world/moon_rocky.tscn",
		"moon_icy": "res://scenes/world/moon_icy.tscn",
		"moon_volcanic": "res://scenes/world/moon_volcanic.tscn"
	}
	
	for key in scenes:
		var path = scenes[key]
		if ResourceLoader.exists(path):
			_moon_scenes[key] = load(path)

# Handle seed changes
func _on_seed_changed(_new_seed: int) -> void:
	# Reload with the same data if we have it
	if _initialized:
		# This would ideally reload from the same data with new seed
		# Implementation depends on how data is stored globally
		pass

# Virtual method for texture generation - to be overridden
func _generate_planet_texture() -> void:
	push_error("PlanetBase: _generate_planet_texture must be overridden")

# Virtual method for atmosphere generation - to be overridden
func _generate_atmosphere_texture() -> void:
	push_error("PlanetBase: _generate_atmosphere_texture must be overridden")

# Update moon positions
func _update_moons(delta: float) -> void:
	var time = Time.get_ticks_msec() / 1000.0
	
	for moon in moons:
		if not is_instance_valid(moon):
			continue
			
		var moon_angle = moon.base_angle + time * moon.orbit_speed + moon.phase_offset
		var orbit_position = calculate_orbit_position(moon, moon_angle)
		
		moon.position = orbit_position
		
		# Set z-index to keep moons behind player but respect planet orbit
		if is_gaseous_planet:
			var moon_z = _get_moon_property(moon, "z_index")
			moon.z_as_relative = true
			moon.z_index = moon_z
		else:
			moon.z_as_relative = true
			moon.z_index = sin(moon_angle) > 0 if -2 else -12

# Calculate orbit position
func calculate_orbit_position(moon, angle: float) -> Vector2:
	if is_gaseous_planet:
		return Vector2(cos(angle), sin(angle)) * moon.distance
	else:
		var deviation = sin(angle * 2) * moon.orbit_deviation
		var radius = moon.distance * (1.0 + deviation * 0.3)
		
		var tilt_factor = 0.4
		var orbit_x = cos(angle) * radius
		var orbit_y = sin(angle) * radius * tilt_factor
		
		return Vector2(orbit_x, orbit_y)

# Draw the planet and debug orbits
func _draw() -> void:
	if atmosphere_texture:
		var size = Vector2(atmosphere_texture.get_width(), atmosphere_texture.get_height()) / 2
		draw_texture(atmosphere_texture, -size, Color.WHITE)
	
	if planet_texture:
		draw_texture(planet_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)
	
	if debug_draw_orbits:
		_draw_debug_orbits()

# Draw debug orbits
func _draw_debug_orbits() -> void:
	const SEGMENTS = 64
	for moon in moons:
		if not is_instance_valid(moon):
			continue
			
		var orbit_color = _get_moon_property(moon, "color")
		var points = []
		
		for i in range(SEGMENTS + 1):
			var angle = i * TAU / SEGMENTS
			points.append(calculate_orbit_position(moon, angle))
		
		for i in range(SEGMENTS):
			draw_line(points[i], points[i+1], orbit_color, debug_orbit_line_width)
		
		var current_angle = moon.base_angle + (Time.get_ticks_msec() / 1000.0) * moon.orbit_speed + moon.phase_offset
		var current_pos = calculate_orbit_position(moon, current_angle)
		draw_circle(current_pos, 3.0, orbit_color)

# Get moon property
func _get_moon_property(moon, property_name: String):
	var moon_type = MoonType.ROCKY
	
	if moon is MoonBase:
		var prefix = moon._get_moon_type_prefix()
		match prefix:
			"Volcanic": moon_type = MoonType.VOLCANIC
			"Icy": moon_type = MoonType.ICY
			"Rocky": moon_type = MoonType.ROCKY
	
	match property_name:
		"color":
			return _moon_params.colors.get(moon_type, Color(1, 1, 1, 0.4))
		"z_index":
			return _moon_params.z_indices.get(moon_type, DEFAULT_Z_INDEX)
	
	return null

# Get the planet type name
func get_theme_name() -> String:
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

# Toggle orbit debug drawing
func toggle_orbit_debug(enabled: bool = true) -> void:
	debug_draw_orbits = enabled
	queue_redraw()

# Set orbit line width
func set_orbit_line_width(width: float) -> void:
	debug_orbit_line_width = width
	queue_redraw()
