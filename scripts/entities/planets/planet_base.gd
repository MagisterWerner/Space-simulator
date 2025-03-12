# scripts/entities/planets/planet_base.gd
# Base class for all planets with moon orbit system
extends Node2D
class_name PlanetBase

## Constants and Enums
const PlanetThemes = preload("res://scripts/generators/planet_generator_base.gd").PlanetTheme
const PlanetCategories = preload("res://scripts/generators/planet_generator_base.gd").PlanetCategory
const ORBIT_COLLISION_MARGIN: float = 16.0
const DEFAULT_Z_INDEX: int = -7

enum MoonType { ROCKY, ICY, VOLCANIC }

## Signals
signal planet_loaded(planet)

## Planet Configuration
@export_group("Planet Properties")
@export var max_moons: int = 2
@export var moon_chance: int = 40

@export_group("Moon Orbit Configuration")
@export var min_moon_distance_factor: float = 1.8
@export var max_moon_distance_factor: float = 2.5
@export var max_orbit_deviation: float = 0.15
@export var moon_orbit_factor: float = 0.05

@export_group("Debug Options")
@export var debug_draw_orbits: bool = false
@export var debug_orbit_line_width: float = 1.0

## Internal properties
var seed_value: int = 0
var planet_texture: Texture2D
var atmosphere_texture: Texture2D
var theme_id: int
var planet_name: String
var pixel_size: int = 256
var moons = []
var is_gaseous_planet: bool = false
var use_texture_cache: bool = true
var grid_x: int = 0
var grid_y: int = 0
var atmosphere_data: Dictionary = {}

# Moon type configuration
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

var _moon_scenes = {}
var _initialized: bool = false
var _init_params: Dictionary = {}

func _ready() -> void:
	z_index = -10
	_load_moon_scenes()
	
	if not SeedManager.is_connected("seed_changed", _on_seed_changed):
		SeedManager.connect("seed_changed", _on_seed_changed)

func _process(delta: float) -> void:
	queue_redraw()
	_update_moons(delta)

func initialize(params: Dictionary) -> void:
	if _initialized:
		return
	
	_init_params = params.duplicate()
	
	seed_value = params.seed_value
	grid_x = params.get("grid_x", 0)
	grid_y = params.get("grid_y", 0)
	is_gaseous_planet = params.get("category_override", PlanetCategories.TERRAN) == PlanetCategories.GASEOUS
	
	_apply_config_params(params)
	_perform_specialized_initialization(params)
	
	planet_name = _get_planet_type_name() + "-" + str(seed_value % 1000)
	call_deferred("_create_moons")
	
	_initialized = true

# Fixed: Added underscore to parameter name to indicate it's intentionally unused
func _on_seed_changed(_new_seed: int) -> void:
	if not _initialized or _init_params.is_empty():
		return
	
	if has_node("/root/SeedManager"):
		var base_seed = SeedManager.get_seed()
		var seed_offset = seed_value % 1000
		_init_params.seed_value = base_seed + seed_offset
	
	for moon in moons:
		if is_instance_valid(moon):
			moon.queue_free()
	moons.clear()
	
	initialize(_init_params)

func _load_moon_scenes() -> void:
	var scenes = {
		MoonType.ROCKY: "res://scenes/world/moon_rocky.tscn",
		MoonType.ICY: "res://scenes/world/moon_icy.tscn",
		MoonType.VOLCANIC: "res://scenes/world/moon_volcanic.tscn"
	}
	
	for type in scenes:
		var path = scenes[type]
		if ResourceLoader.exists(path):
			_moon_scenes[type] = load(path)
		else:
			push_error("Planet: Failed to load moon scene: %s" % path)

func _apply_config_params(params: Dictionary) -> void:
	var props = ["max_moons", "moon_chance", "min_moon_distance_factor", 
				"max_moon_distance_factor", "max_orbit_deviation", "moon_orbit_factor",
				"use_texture_cache", "debug_draw_orbits", "debug_orbit_line_width",
				"is_gaseous_planet"]
	
	for prop in props:
		if params.has(prop):
			set(prop, params[prop])
	
	if params.has("moon_orbit_speed_factor") and params.moon_orbit_speed_factor != 1.0:
		moon_orbit_factor *= params.moon_orbit_speed_factor

func _draw() -> void:
	if atmosphere_texture:
		var size = Vector2(atmosphere_texture.get_width(), atmosphere_texture.get_height()) / 2
		draw_texture(atmosphere_texture, -size, Color.WHITE)
	
	if planet_texture:
		draw_texture(planet_texture, -Vector2(pixel_size, pixel_size) / 2, Color.WHITE)
	
	if debug_draw_orbits:
		_draw_debug_orbits()

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

func _update_moons(_delta: float) -> void:
	var time = Time.get_ticks_msec() / 1000.0
	
	for moon in moons:
		if not is_instance_valid(moon):
			continue
			
		var moon_angle = moon.base_angle + time * moon.orbit_speed + moon.phase_offset
		var orbit_position = calculate_orbit_position(moon, moon_angle)
		
		moon.position = orbit_position
		
		if is_gaseous_planet:
			moon.z_index = _get_moon_property(moon, "z_index")
		else:
			moon.z_as_relative = false
			moon.z_index = sin(moon_angle) > 0 if 50 else -50

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

func _create_moons() -> void:
	if _moon_scenes.is_empty():
		push_error("Planet: Moon scenes not available")
		emit_signal("planet_loaded", self)
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value
	
	var num_moons = 1
	
	if is_gaseous_planet:
		num_moons = 3
		
		for i in range(3):  # Check for additional moons (40% chance each)
			if rng.randi() % 100 < 40:
				num_moons += 1
	else:
		if not (rng.randi() % 100 < moon_chance):
			emit_signal("planet_loaded", self)
			return
			
		if max_moons > 1 and rng.randi() % 100 < 40:
			num_moons = 2
	
	var moon_distribution = _calculate_moon_distribution(num_moons)
	var orbital_params = _generate_orbital_parameters(num_moons, rng, moon_distribution)
	var existing_orbits = []
	
	for m in range(num_moons):
		var moon_type = _determine_moon_type(m, moon_distribution)
		var moon_instance = _create_moon(m, moon_type, orbital_params, existing_orbits, rng)
		
		if moon_instance:
			moons.append(moon_instance)
	
	emit_signal("planet_loaded", self)

func _calculate_moon_distribution(num_moons: int) -> Dictionary:
	if is_gaseous_planet:
		# Calculate better distribution based on number of moons
		var volcanic_count = min(2, int(ceil(num_moons / 3.0)))
		var rocky_count = min(2, int(ceil(num_moons / 3.0)))
		var icy_count = min(2, int(ceil(num_moons / 3.0)))
		
		# Adjust to ensure total matches num_moons
		var total = volcanic_count + rocky_count + icy_count
		
		# If we have too many, reduce from least interesting moons first
		while total > num_moons:
			if icy_count > 1:
				icy_count -= 1
			elif rocky_count > 1:
				rocky_count -= 1
			elif volcanic_count > 1:
				volcanic_count -= 1
			else:
				# Shouldn't reach here, but just in case
				icy_count = max(0, icy_count - 1)
			total = volcanic_count + rocky_count + icy_count
		
		# If we have too few, add to most visually interesting moons first
		while total < num_moons:
			if volcanic_count < 2:
				volcanic_count += 1
			elif rocky_count < 2:
				rocky_count += 1
			else:
				icy_count += 1
			total = volcanic_count + rocky_count + icy_count
			
		return {
			MoonType.VOLCANIC: volcanic_count,
			MoonType.ROCKY: rocky_count,
			MoonType.ICY: icy_count
		}
	else:
		return {
			MoonType.ROCKY: num_moons
		}

func _generate_orbital_parameters(num_moons: int, rng: RandomNumberGenerator, 
								 distribution: Dictionary) -> Array:
	var params = []
	
	if is_gaseous_planet:
		var _index = 0
		
		for type in [MoonType.VOLCANIC, MoonType.ROCKY, MoonType.ICY]:
			if distribution.has(type):
				var count = distribution[type]
				var distance_range = _moon_params.distance_ranges[type]
				var speed_mod = _moon_params.speed_modifiers[type]
				
				for i in range(count):
					params.append(_generate_single_moon_params(
						i, count, type, rng, speed_mod, distance_range
					))
					_index += 1
	else:
		var planet_radius = pixel_size / 2.0
		var min_distance = planet_radius * min_moon_distance_factor
		var max_distance = planet_radius * max_moon_distance_factor
		var distance_step = (max_distance - min_distance) / max(1, num_moons)
		
		for i in range(num_moons):
			var base_distance = min_distance + i * distance_step
			var jitter = distance_step * 0.2 * rng.randf_range(-1.0, 1.0)
			var distance = clamp(base_distance + jitter, min_distance, max_distance)
			
			var speed_factor = 1.0 / sqrt(distance / min_distance)
			var orbit_speed = rng.randf_range(0.2, 0.4) * moon_orbit_factor * speed_factor * _get_orbit_speed_modifier()
			
			var phase_offset = (i * TAU / float(num_moons)) + rng.randf_range(-0.2, 0.2)
			var orbit_deviation = rng.randf_range(0.05, max_orbit_deviation) * (distance / max_distance)
			
			params.append({
				"center_x": 0,
				"center_y": 0,
				"distance": distance,
				"base_angle": 0.0,
				"orbit_speed": orbit_speed,
				"orbit_deviation": orbit_deviation,
				"phase_offset": phase_offset
			})
	
	return params

func _generate_single_moon_params(index: int, count: int, _type: int, rng: RandomNumberGenerator,
								speed_mod: float, distance_range: Vector2) -> Dictionary:
	var planet_radius = pixel_size / 2.0
	
	var distance_percent = float(index) / max(1, count)
	var distance = planet_radius * lerp(distance_range.x, distance_range.y, distance_percent)
	
	var base_speed = rng.randf_range(0.2, 0.4) * moon_orbit_factor * _get_orbit_speed_modifier()
	var orbit_speed = base_speed * speed_mod
	
	var phase_offset = (index * TAU / count) + rng.randf_range(-0.1, 0.1)
	
	return {
		"center_x": 0,
		"center_y": 0,
		"distance": distance,
		"base_angle": 0.0,
		"orbit_speed": orbit_speed,
		"orbit_deviation": 0.0,
		"phase_offset": phase_offset
	}

func _determine_moon_type(index: int, distribution: Dictionary) -> int:
	if is_gaseous_planet:
		var volcanic_count = distribution.get(MoonType.VOLCANIC, 0)
		var rocky_count = distribution.get(MoonType.ROCKY, 0)
		
		if index < volcanic_count:
			return MoonType.VOLCANIC
		elif index < volcanic_count + rocky_count:
			return MoonType.ROCKY
		else:
			return MoonType.ICY
	
	return _get_moon_type_for_position(index)

func _create_moon(index: int, moon_type: int, params: Array, existing_orbits: Array, 
				  rng: RandomNumberGenerator) -> Node:
	if not _moon_scenes.has(moon_type):
		push_warning("Planet: Moon type not available: " + str(moon_type))
		return null
	
	var moon_scene = _moon_scenes[moon_type]
	var moon_instance = moon_scene.instantiate()
	if not moon_instance:
		return null
	
	if not is_gaseous_planet and moon_instance is Node2D:
		moon_instance.z_as_relative = false
		
	var moon_seed = seed_value + index * 100 + rng.randi() % 1000
	
	var param_index = min(index, params.size() - 1)
	var moon_params = params[param_index].duplicate()
	
	var moon_generator = MoonGenerator.new()
	var moon_size = moon_generator.get_moon_size(moon_seed, is_gaseous_planet)
	
	moon_params["moon_size"] = moon_size
	
	if _check_orbit_collision(moon_params, existing_orbits):
		if not _resolve_orbit_collision(moon_params, existing_orbits, moon_type, rng):
			push_warning("Planet: Skipping moon due to unresolvable collision")
			moon_instance.queue_free()
			return null
	
	existing_orbits.append(moon_params)
	
	var prefix = _get_moon_type_prefix(moon_type)
	var moon_name = prefix + " Moon-" + str(moon_seed % 1000)
	
	var moon_init_params = {
		"seed_value": moon_seed,
		"parent_planet": self,
		"distance": moon_params.distance,
		"base_angle": moon_params.base_angle,
		"orbit_speed": moon_params.orbit_speed,
		"orbit_deviation": moon_params.orbit_deviation,
		"phase_offset": moon_params.phase_offset,
		"parent_name": planet_name,
		"use_texture_cache": use_texture_cache,
		"moon_type": moon_type,
		"size_scale": _get_moon_size_scale(),
		"is_gaseous": is_gaseous_planet,
		"moon_name": moon_name,
		"orbital_inclination": 1.0,
		"orbit_vertical_offset": 0.0
	}
	
	add_child(moon_instance)
	
	moon_instance.initialize(moon_init_params)
	
	var start_angle = moon_params.base_angle + moon_params.phase_offset
	var start_position = calculate_orbit_position(moon_params, start_angle)
	moon_instance.position = start_position
	
	return moon_instance

func _resolve_orbit_collision(moon_params: Dictionary, existing_orbits: Array, 
							 moon_type: int, rng: RandomNumberGenerator) -> bool:
	var max_attempts = 15  # Increased from 10
	
	# Try systematic adjustments first
	for attempt in range(max_attempts):
		# Adjust distance more intelligently based on attempt number
		var adjustment = (20 + attempt * 10) * (1.0 + (attempt / 8.0))
		
		# Alternate between moving outward and inward, but prefer outward
		if attempt % 2 == 0 or existing_orbits.size() <= 1:
			moon_params.distance += adjustment
		else:
			moon_params.distance -= adjustment
			
		# Adjust orbit parameters based on planet type
		if is_gaseous_planet:
			var distance_range = _moon_params.distance_ranges[moon_type]
			moon_params.distance = clamp(moon_params.distance, 
									  pixel_size/2.0 * distance_range.x * 0.8, 
									  pixel_size/2.0 * distance_range.y * 1.5)
		else:
			# Increase deviation with each attempt for terrestrial planets
			moon_params.orbit_deviation = min(max_orbit_deviation * (1.0 + attempt * 0.15), 0.9)
			
			var min_distance = pixel_size/2.0 * min_moon_distance_factor * 0.8
			var max_distance = pixel_size/2.0 * max_moon_distance_factor * 1.5
			moon_params.distance = clamp(moon_params.distance, min_distance, max_distance)
		
		# Try placing moons at optimal phases around orbit
		if existing_orbits.size() > 0:
			var optimal_phase_gap = TAU / (existing_orbits.size() + 1)
			moon_params.phase_offset = optimal_phase_gap * (existing_orbits.size()) + rng.randf_range(-0.2, 0.2)
		else:
			moon_params.phase_offset = rng.randf() * TAU
		
		if not _check_orbit_collision(moon_params, existing_orbits):
			return true
	
	# Last resort: Try extreme placements
	if is_gaseous_planet:
		var distance_range = _moon_params.distance_ranges[moon_type]
		moon_params.distance = pixel_size/2.0 * distance_range.y * 2.0
	else:
		moon_params.distance = pixel_size/2.0 * max_moon_distance_factor * 2.0
		moon_params.orbit_deviation = max_orbit_deviation * 0.2
	
	moon_params.phase_offset = rng.randf() * TAU
	return not _check_orbit_collision(moon_params, existing_orbits)

func _check_orbit_collision(new_orbit: Dictionary, existing_orbits: Array) -> bool:
	if existing_orbits.is_empty():
		return false
	
	var new_moon_size = new_orbit.get("moon_size", 32)
	var collision_tolerance = 1.0 - (0.05 * existing_orbits.size())  # More moons = more tolerance
	
	for orbit in existing_orbits:
		var existing_moon_size = orbit.get("moon_size", 32)
		var safe_distance = (new_moon_size + existing_moon_size) / 2.0 * ORBIT_COLLISION_MARGIN * collision_tolerance
		
		# Distance-based collision tolerance
		if new_orbit.distance > orbit.distance * 1.5:
			safe_distance *= 0.8  # Reduce required safe distance for distant moons
		
		if is_gaseous_planet:
			var radii_difference = abs(new_orbit.distance - orbit.distance)
			if radii_difference < safe_distance:
				return true
		else:
			var new_max = new_orbit.distance * (1.0 + new_orbit.orbit_deviation * 0.3)
			var new_min = new_orbit.distance * (1.0 - new_orbit.orbit_deviation * 0.3)
			
			var existing_max = orbit.distance * (1.0 + orbit.orbit_deviation * 0.3)
			var existing_min = orbit.distance * (1.0 - orbit.orbit_deviation * 0.3)
			
			var outer_gap = new_min - existing_max
			var inner_gap = existing_min - new_max
			
			if (outer_gap < safe_distance and outer_gap > -safe_distance) or (inner_gap < safe_distance and inner_gap > -safe_distance):
				return true
	
	return false

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

func _get_moon_type_prefix(moon_type: int) -> String:
	match moon_type:
		MoonType.ROCKY: return "Rocky"
		MoonType.ICY: return "Icy"
		MoonType.VOLCANIC: return "Volcanic"
	return "Moon"

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

# Virtual methods (to be overridden by subclasses)
func _perform_specialized_initialization(_params: Dictionary) -> void:
	push_error("PlanetBase: _perform_specialized_initialization must be overridden")

func _get_moon_type_for_position(_position: int) -> int:
	return MoonType.ROCKY

func _get_orbit_speed_modifier() -> float:
	return 1.0

func _get_moon_size_scale() -> float:
	return 1.0

func _get_planet_type_name() -> String:
	return "Planet"

# Public API Methods
func toggle_orbit_debug(enabled: bool = true) -> void:
	debug_draw_orbits = enabled
	queue_redraw()

func set_orbit_line_width(width: float) -> void:
	debug_orbit_line_width = width
	queue_redraw()
