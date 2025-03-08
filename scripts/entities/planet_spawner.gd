# scripts/entities/planet_spawner.gd
extends Node2D
class_name PlanetSpawner

signal planet_spawned(planet_instance)
signal spawner_ready
signal generation_started
signal generation_completed

# Planet Categories
enum PlanetCategory {
	TERRAN,   # Rocky/solid surface planets (Earth-like, desert, ice, etc.)
	GASEOUS   # Gas planets without solid surface (gas giants, etc.)
}

# Planet Themes
enum PlanetTheme {
	# Terran planets
	ARID,
	ICE,
	LAVA,
	LUSH,
	DESERT,
	ALPINE,
	OCEAN,
	
	# Gaseous planets
	GAS_GIANT  # Currently the only gaseous type
}

# Planet Type Selection
@export_enum("Terran", "Gaseous") var planet_category: int = 0  # 0=Terran, 1=Gaseous

# Terran Planet Theme (only used when planet_category is Terran)
@export_enum("Random", "Arid", "Ice", "Lava", "Lush", "Desert", "Alpine", "Ocean") 
var terran_theme: int = 0  # 0=Random, 1-7=Specific Terran theme

# Grid Position
@export var use_grid_position: bool = true
@export var grid_x: int = 0
@export var grid_y: int = 0

# Performance Settings
@export var use_threading: bool = true
@export var use_texture_cache: bool = true
@export var z_index_base: int = -10
@export var debug_mode: bool = false

# Loading state
var _is_loading: bool = false
var _thread: Thread = null
var _planet_instance = null
var _seed_value: int = 0
var _initialized: bool = false
var _generation_time: float = 0.0

# Static texture cache for all planet spawners
static var texture_cache = {
	"planets": {},
	"atmospheres": {},
	"moons": {}
}

# Mapping from string type names to enum values
const THEME_MAP = {
	"arid": PlanetTheme.ARID,
	"ice": PlanetTheme.ICE,
	"lava": PlanetTheme.LAVA,
	"lush": PlanetTheme.LUSH, 
	"desert": PlanetTheme.DESERT,
	"alpine": PlanetTheme.ALPINE,
	"ocean": PlanetTheme.OCEAN,
	"gas_giant": PlanetTheme.GAS_GIANT
}

# Planet theme color mapping (for placeholder textures)
const THEME_COLORS = {
	PlanetTheme.ARID: Color(0.85, 0.65, 0.35),
	PlanetTheme.ICE: Color(0.8, 0.9, 1.0),
	PlanetTheme.LAVA: Color(0.9, 0.3, 0.1),
	PlanetTheme.LUSH: Color(0.2, 0.7, 0.3),
	PlanetTheme.DESERT: Color(0.85, 0.7, 0.4),
	PlanetTheme.ALPINE: Color(0.85, 0.95, 0.9),
	PlanetTheme.OCEAN: Color(0.1, 0.4, 0.7),
	PlanetTheme.GAS_GIANT: Color(0.7, 0.65, 0.5)
}

func _ready() -> void:
	# Initialize the spawner after autoloads are ready
	call_deferred("_initialize")

func _initialize() -> void:
	if _initialized:
		return
	
	# Connect to SeedManager if available
	if has_node("/root/SeedManager") and SeedManager.has_signal("seed_changed"):
		if not SeedManager.is_connected("seed_changed", _on_seed_changed):
			SeedManager.connect("seed_changed", _on_seed_changed)
	
	# Get seed value
	_update_seed_value()
	
	_initialized = true
	spawner_ready.emit()
	
	if debug_mode:
		print("PlanetSpawner initialized at grid position: ", grid_x, ",", grid_y)

func _exit_tree() -> void:
	# Clean up thread if needed
	if _thread and _thread.is_started():
		_thread.wait_to_finish()
	
	# Clean up planet instance to avoid memory leaks
	if _planet_instance and is_instance_valid(_planet_instance):
		if _planet_instance.has_signal("planet_loaded"):
			if _planet_instance.is_connected("planet_loaded", _on_planet_loaded):
				_planet_instance.disconnect("planet_loaded", _on_planet_loaded)
	
	# Unregister from SeedManager
	if has_node("/root/SeedManager") and SeedManager.has_signal("seed_changed"):
		if SeedManager.is_connected("seed_changed", _on_seed_changed):
			SeedManager.disconnect("seed_changed", _on_seed_changed)

func set_grid_position(x: int, y: int) -> void:
	grid_x = x
	grid_y = y
	use_grid_position = true
	_update_seed_value()
	
	# Update position if using grid
	if use_grid_position and has_node("/root/GridManager") and _planet_instance and is_instance_valid(_planet_instance):
		var new_pos = GridManager.cell_to_world(Vector2i(grid_x, grid_y))
		_planet_instance.global_position = new_pos
	
	if debug_mode:
		print("PlanetSpawner: Grid position set to ", grid_x, ",", grid_y)

func _update_seed_value() -> void:
	if has_node("/root/SeedManager"):
		# Get base seed from SeedManager
		var base_seed = SeedManager.get_seed()
		
		# Add grid position to create unique seeds per grid cell
		if use_grid_position:
			_seed_value = base_seed + (grid_x * 1000) + (grid_y * 100)
		else:
			# Use position-based seed if not using grid
			var pos_hash = (int(global_position.x) * 13) + (int(global_position.y) * 7)
			_seed_value = base_seed + pos_hash
	else:
		# Fallback when SeedManager isn't available
		_seed_value = hash(str(grid_x) + str(grid_y) + str(Time.get_unix_time_from_system()))
	
	if debug_mode:
		print("PlanetSpawner: Seed value updated to ", _seed_value)

func spawn_terran_planet(theme_name: String = "random") -> Node2D:
	return spawn_specific_planet("terran", theme_name)

func spawn_gaseous_planet() -> Node2D:
	return spawn_specific_planet("gaseous")

# Spawn a planet with specific category and theme
func spawn_specific_planet(category_name: String = "random", theme_name: String = "random") -> Node2D:
	# Start timing generation for performance monitoring
	_generation_time = Time.get_ticks_msec()
	generation_started.emit()
	
	if debug_mode:
		print("PlanetSpawner: Generating ", category_name, " planet with theme ", theme_name)
	
	# Determine category enum value
	var category_enum: int
	if category_name == "random":
		category_enum = planet_category
	else:
		category_name = category_name.to_lower()
		category_enum = PlanetCategory.TERRAN if category_name == "terran" else PlanetCategory.GASEOUS
	
	# Determine theme enum value
	var theme_enum: int = -1  # -1 means random
	if theme_name != "random":
		theme_name = theme_name.to_lower()
		if THEME_MAP.has(theme_name):
			theme_enum = THEME_MAP[theme_name]
	
	# Special case for gaseous planets (only gas_giant theme available)
	if category_enum == PlanetCategory.GASEOUS:
		theme_enum = PlanetTheme.GAS_GIANT
	
	# Update internal state
	planet_category = category_enum
	if category_enum == PlanetCategory.TERRAN and theme_enum >= 0:
		# +1 because 0 is "Random" in the export enum
		terran_theme = theme_enum + 1
	
	# Clean up any existing planet
	if _planet_instance and is_instance_valid(_planet_instance):
		if _planet_instance.has_signal("planet_loaded"):
			if _planet_instance.is_connected("planet_loaded", _on_planet_loaded):
				_planet_instance.disconnect("planet_loaded", _on_planet_loaded)
		_planet_instance.queue_free()
		_planet_instance = null
	
	# If threading is enabled and supported
	if use_threading and OS.has_feature("threads") and Engine.get_version_info().major >= 4:
		return _spawn_planet_threaded(category_enum, theme_enum)
	else:
		return _spawn_planet_direct(category_enum, theme_enum)

# Threaded planet generation
func _spawn_planet_threaded(category_enum: int, theme_enum: int) -> Node2D:
	# Create planet scene instance immediately
	var planet_scene = load("res://scenes/world/planet.tscn")
	_planet_instance = planet_scene.instantiate()
	add_child(_planet_instance)
	
	# Set z-index for rendering order
	_planet_instance.z_index = z_index_base
	
	# Position based on grid if needed
	if use_grid_position and has_node("/root/GridManager"):
		var grid_manager = get_node("/root/GridManager")
		if grid_manager is WorldGrid:
			if grid_manager.is_valid_cell(Vector2i(grid_x, grid_y)):
				var spawn_position = grid_manager.get_cell_center(Vector2i(grid_x, grid_y))
				_planet_instance.global_position = spawn_position
				
				# Register the cell as occupied in grid manager
				grid_manager.register_cell(Vector2i(grid_x, grid_y), "planet")
				
				if debug_mode:
					print("PlanetSpawner: Positioned at grid cell ", grid_x, ",", grid_y, 
						" world position: ", spawn_position)
			else:
				push_warning("Invalid grid position: " + str(grid_x) + "," + str(grid_y))
	
	# Set up a placeholder visual
	var placeholder = ColorRect.new()
	placeholder.name = "Placeholder"
	
	# Color the placeholder based on theme
	var theme_color = THEME_COLORS[theme_enum if theme_enum >= 0 else PlanetTheme.LUSH]
	placeholder.color = theme_color.darkened(0.3) # Darken to indicate it's loading
	
	var radius = 128 if category_enum == PlanetCategory.TERRAN else 256
	placeholder.size = Vector2(radius * 2, radius * 2)
	placeholder.position = Vector2(-radius, -radius)
	_planet_instance.add_child(placeholder)
	
	# Start the generation thread
	_is_loading = true
	
	# Create a new thread if needed
	if _thread == null:
		_thread = Thread.new()
	elif _thread.is_started():
		_thread.wait_to_finish()
	
	# Start thread with generation parameters
	var params = {
		"category_enum": category_enum,
		"theme_enum": theme_enum,
		"seed_value": _seed_value
	}
	
	# Connect to planet's loaded signal
	if _planet_instance.has_signal("planet_loaded"):
		if not _planet_instance.is_connected("planet_loaded", _on_planet_loaded):
			_planet_instance.connect("planet_loaded", _on_planet_loaded)
	
	# Start the thread
	_thread.start(Callable(self, "_thread_generate_planet").bind(params))
	
	return _planet_instance

# Thread function for planet generation
func _thread_generate_planet(params: Dictionary) -> void:
	var category_enum = params.category_enum
	var theme_enum = params.theme_enum
	var seed_value = params.seed_value
	
	# Create placeholder textures for now
	var textures = _create_placeholder_textures(category_enum, theme_enum, seed_value)
	
	# Can't update scene directly from thread, so call from main thread
	call_deferred("_finalize_thread_planet", textures, category_enum, theme_enum)

# Finalize planet generation from thread (called in main thread)
func _finalize_thread_planet(textures, category_enum: int, theme_enum: int) -> void:
	if _planet_instance and is_instance_valid(_planet_instance):
		# Remove placeholder
		var placeholder = _planet_instance.get_node_or_null("Placeholder")
		if placeholder:
			placeholder.queue_free()
		
		# Initialize the planet with parameters
		var planet_params = {
			"seed_value": _seed_value,
			"grid_x": grid_x,
			"grid_y": grid_y,
			"theme_override": theme_enum,
			"category_override": category_enum,
			"use_texture_cache": use_texture_cache,
			"textures": textures
		}
		
		# Initialize planet
		_planet_instance.initialize(planet_params)
		
		# Register with EntityManager if available
		if has_node("/root/EntityManager"):
			EntityManager.register_entity(_planet_instance, "planet")
		
		# Mark loading as complete
		_is_loading = false
		
		# Emit spawned signal
		planet_spawned.emit(_planet_instance)
		
		if debug_mode:
			var time_taken = (Time.get_ticks_msec() - _generation_time) / 1000.0
			print("PlanetSpawner: Planet generated in ", time_taken, " seconds")
	
	# Clean up thread
	_thread.wait_to_finish()
	
	# Signal that generation is complete
	generation_completed.emit()

# Direct (non-threaded) planet generation
func _spawn_planet_direct(category_enum: int, theme_enum: int) -> Node2D:
	var planet_scene = load("res://scenes/world/planet.tscn")
	_planet_instance = planet_scene.instantiate()
	add_child(_planet_instance)
	
	# Set z-index for rendering order
	_planet_instance.z_index = z_index_base
	
	# Set position
	if use_grid_position and has_node("/root/GridManager"):
		var grid_manager = get_node("/root/GridManager")
		if grid_manager is WorldGrid:
			if grid_manager.is_valid_cell(Vector2i(grid_x, grid_y)):
				var spawn_position = grid_manager.get_cell_center(Vector2i(grid_x, grid_y))
				_planet_instance.global_position = spawn_position
				
				# Register the cell as occupied in grid manager
				grid_manager.register_cell(Vector2i(grid_x, grid_y), "planet")
				
				if debug_mode:
					print("PlanetSpawner: Positioned at grid cell ", grid_x, ",", grid_y, 
						" world position: ", spawn_position)
			else:
				push_warning("Invalid grid position: " + str(grid_x) + "," + str(grid_y))
	
	# Create textures
	var textures = _create_placeholder_textures(category_enum, theme_enum, _seed_value)
	
	# Initialize planet
	var planet_params = {
		"seed_value": _seed_value,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"theme_override": theme_enum,
		"category_override": category_enum,
		"use_texture_cache": use_texture_cache,
		"textures": textures
	}
	
	# Connect to planet's loaded signal
	if _planet_instance.has_signal("planet_loaded"):
		if not _planet_instance.is_connected("planet_loaded", _on_planet_loaded):
			_planet_instance.connect("planet_loaded", _on_planet_loaded)
	
	_planet_instance.initialize(planet_params)
	
	# Register with EntityManager
	if has_node("/root/EntityManager"):
		EntityManager.register_entity(_planet_instance, "planet")
	
	# Emit spawned signal
	planet_spawned.emit(_planet_instance)
	
	# Signal that generation is complete
	generation_completed.emit()
	
	if debug_mode:
		var time_taken = (Time.get_ticks_msec() - _generation_time) / 1000.0
		print("PlanetSpawner: Planet generated in ", time_taken, " seconds")
	
	return _planet_instance

func _on_planet_loaded(planet) -> void:
	# Now that planet and moons are fully loaded, emit signal again
	if planet == _planet_instance:
		planet_spawned.emit(_planet_instance)

# Fixed function with the parameter properly used
func _on_seed_changed(_new_seed: int) -> void:
	# Update seed value and regenerate if needed
	_update_seed_value()
	
	if debug_mode:
		print("PlanetSpawner: Seed changed to ", _seed_value)

# Create placeholder textures with proper theming
func _create_placeholder_textures(category_enum: int, theme_enum: int, seed_value: int) -> Array:
	# Return an array with [planet_texture, atmosphere_texture, size]
	var size = 512 if category_enum == PlanetCategory.GASEOUS else 256
	
	# If theme is random and we're terran, pick a theme based on seed
	if theme_enum < 0 and category_enum == PlanetCategory.TERRAN:
		var rng = RandomNumberGenerator.new()
		rng.seed = seed_value
		theme_enum = rng.randi() % PlanetTheme.GAS_GIANT
	elif category_enum == PlanetCategory.GASEOUS:
		theme_enum = PlanetTheme.GAS_GIANT
	
	# Get the color for this theme
	var color = THEME_COLORS.get(theme_enum, Color(0.7, 0.7, 0.7))
	
	# Create planet texture
	var planet_image = Image.create(size, size, true, Image.FORMAT_RGBA8)
	var radius = size / 2
	
	for y in range(size):
		for x in range(size):
			var distance = Vector2(x - radius, y - radius).length()
			
			if distance <= radius:
				# Create a shaded sphere effect
				var normal_x = (x - radius) / float(radius)
				var normal_y = (y - radius) / float(radius)
				var normal_z = sqrt(1.0 - min(normal_x * normal_x + normal_y * normal_y, 1.0))
				
				var light_dir = Vector3(-0.5, -0.5, 0.7).normalized()
				var normal = Vector3(normal_x, normal_y, normal_z)
				
				var light_intensity = max(0.0, normal.dot(light_dir))
				var ambient = 0.3
				var final_light = ambient + light_intensity * 0.7
				
				var pixel_color = Color(
					color.r * final_light,
					color.g * final_light,
					color.b * final_light,
					1.0
				)
				planet_image.set_pixel(x, y, pixel_color)
			else:
				planet_image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	var planet_texture = ImageTexture.create_from_image(planet_image)
	
	# Create atmosphere texture (slightly larger than planet)
	var atm_size = size + 40
	var atm_image = Image.create(atm_size, atm_size, true, Image.FORMAT_RGBA8)
	var atm_radius = atm_size / 2
	var inner_radius = radius - 5
	
	for y in range(atm_size):
		for x in range(atm_size):
			var distance = Vector2(x - atm_radius, y - atm_radius).length()
			
			if distance <= atm_radius and distance >= inner_radius:
				# Create fading atmosphere
				var t = (distance - inner_radius) / (atm_radius - inner_radius)
				var alpha = 1.0 - t * t
				
				var atm_color = Color(
					color.r * 0.9,
					color.g * 0.9,
					color.b * 1.1,
					alpha * 0.3
				)
				atm_image.set_pixel(x, y, atm_color)
			else:
				atm_image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	var atm_texture = ImageTexture.create_from_image(atm_image)
	
	return [planet_texture, atm_texture, size]

# Static function to get planet category
static func get_planet_category(theme: int) -> int:
	# Currently only GAS_GIANT is GASEOUS, everything else is TERRAN
	if theme == PlanetTheme.GAS_GIANT:
		return PlanetCategory.GASEOUS
	return PlanetCategory.TERRAN
