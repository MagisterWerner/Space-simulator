# scripts/entities/asteroid_spawner.gd - Enhanced implementation with better placement and debug features
extends Node2D
class_name AsteroidSpawner

signal spawner_ready
signal field_generated(field_size, asteroid_count)
signal asteroid_spawned(asteroid)
signal all_asteroids_spawned

# Field properties
@export var grid_x: int = 0
@export var grid_y: int = 0
@export var local_seed_offset: int = 0

# Field configuration
@export_category("Field Configuration")
@export var field_radius: float = 400.0
@export var min_asteroids: int = 8
@export var max_asteroids: int = 15
@export var min_distance_between: float = 60.0
@export var size_variation: float = 0.4
@export var use_grid_position: bool = true
@export var world_space_generation: bool = true

# Asteroid properties
@export_category("Asteroid Properties")
@export var small_asteroid_chance: float = 0.3
@export var medium_asteroid_chance: float = 0.5
@export var large_asteroid_chance: float = 0.2
@export var max_rotation_speed: float = 0.5
@export var min_linear_speed: float = 5.0
@export var max_linear_speed: float = 30.0

# Asteroid scenes
@export_category("Scene References")
@export var asteroid_scene_path: String = "res://scenes/entities/asteroid.tscn"
@export var small_asteroid_scene_path: String = ""  # Optional override for small asteroids
@export var medium_asteroid_scene_path: String = "" # Optional override for medium asteroids
@export var large_asteroid_scene_path: String = ""  # Optional override for large asteroids

# Performance settings
@export_category("Performance")
@export var max_concurrent_spawns: int = 5
@export var spawn_batch_delay: float = 0.05

# Visual debugging
@export_category("Debug")
@export var debug_field_generation: bool = false
@export var debug_mode: bool = false
@export var debug_draw_field: bool = true
@export var debug_draw_asteroid_positions: bool = false
@export var debug_asteroid_collisions: bool = false

# Internal variables
var _seed_value: int = 0
var _asteroids: Array = []
var _asteroid_scenes: Dictionary = {}
var _spawned_count: int = 0
var _field_data: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _initialized: bool = false
var _remaining_to_spawn: Array = []
var _is_spawning: bool = false
var _spawn_timer: float = 0.0

# Texture cache (persistent across asteroid instances)
var _texture_cache: Dictionary = {}
const MAX_TEXTURE_CACHE_SIZE: int = 20

# Cached managers
var _game_settings = null
var _seed_manager = null
var _entity_manager = null
var _grid_manager = null
var _asteroid_generator = null
var _asteroid_generator_instance = null

# Debug visualization
var _debug_asteroid_positions: Array = []
var _debug_asteroids_drawn: bool = false
var _debug_color: Color = Color(1.0, 0.5, 0.0, 0.5)

func _ready() -> void:
	# Register as part of asteroid_fields group
	add_to_group("asteroid_fields")
	
	# Find required singletons
	_cache_singletons()
	
	# Load asteroid scenes
	_load_asteroid_scenes()
	
	# Initialize asteroid generator for texture generation
	_initialize_asteroid_generator()
	
	# Initialize with small delay to ensure systems are ready
	call_deferred("_initialize")

func _cache_singletons() -> void:
	_game_settings = get_node_or_null("/root/GameSettings")
	_seed_manager = get_node_or_null("/root/SeedManager")
	_entity_manager = get_node_or_null("/root/EntityManager")
	_grid_manager = get_node_or_null("/root/GridManager")
	
	# Connect to seed changes if available
	if _seed_manager and _seed_manager.has_signal("seed_changed"):
		if not _seed_manager.is_connected("seed_changed", _on_seed_changed):
			_seed_manager.connect("seed_changed", _on_seed_changed)
	
	# Debug mode from game settings
	if _game_settings:
		debug_mode = _game_settings.debug_mode and _game_settings.debug_entity_generation

func _initialize_asteroid_generator() -> void:
	var generator_script = load("res://scripts/generators/asteroid_generator.gd")
	if generator_script:
		_asteroid_generator = generator_script
		
		# Create instance for texture generation
		_asteroid_generator_instance = generator_script.new()
		add_child(_asteroid_generator_instance)
		
		if debug_mode:
			print("AsteroidSpawner: Asteroid generator initialized")
	else:
		push_error("AsteroidSpawner: Failed to load asteroid generator script")

func _load_asteroid_scenes() -> void:
	# Load main asteroid scene
	if ResourceLoader.exists(asteroid_scene_path):
		_asteroid_scenes["default"] = load(asteroid_scene_path)
		if debug_mode:
			print("AsteroidSpawner: Loaded main asteroid scene")
	else:
		push_error("AsteroidSpawner: Failed to load asteroid scene: " + asteroid_scene_path)
	
	# Load size-specific scenes if provided
	if small_asteroid_scene_path != "" and ResourceLoader.exists(small_asteroid_scene_path):
		_asteroid_scenes["small"] = load(small_asteroid_scene_path)
	
	if medium_asteroid_scene_path != "" and ResourceLoader.exists(medium_asteroid_scene_path):
		_asteroid_scenes["medium"] = load(medium_asteroid_scene_path)
	
	if large_asteroid_scene_path != "" and ResourceLoader.exists(large_asteroid_scene_path):
		_asteroid_scenes["large"] = load(large_asteroid_scene_path)

func _on_seed_changed(_new_seed: int) -> void:
	_update_seed_value()
	
	if _initialized:
		# Clear existing field and regenerate
		clear_field()
		generate_field()

func _initialize() -> void:
	if _initialized:
		return
	
	await get_tree().process_frame
	
	_update_seed_value()
	
	# Use position based on grid coordinates
	if use_grid_position:
		var new_pos = _calculate_spawn_position()
		global_position = new_pos
	
	# Generate the field
	generate_field()
	
	_initialized = true
	spawner_ready.emit()

func _update_seed_value() -> void:
	var base_seed: int
	
	if _game_settings:
		base_seed = _game_settings.get_seed()
	elif _seed_manager:
		base_seed = _seed_manager.get_seed()
	else:
		base_seed = int(Time.get_unix_time_from_system())
	
	if use_grid_position:
		# Deterministic seed based on grid position and offset
		_seed_value = base_seed + (grid_x * 1000) + (grid_y * 100) + local_seed_offset
	else:
		# Deterministic seed based on position hash and offset
		var pos_hash = (int(global_position.x) * 13) + (int(global_position.y) * 7)
		_seed_value = base_seed + pos_hash + local_seed_offset
	
	_rng.seed = _seed_value
	
	if debug_mode:
		print("AsteroidSpawner at (%d,%d): Seed updated to %d" % [grid_x, grid_y, _seed_value])

func set_grid_position(x: int, y: int) -> void:
	grid_x = x
	grid_y = y
	_update_seed_value()
	
	if use_grid_position:
		var new_pos = _calculate_spawn_position()
		global_position = new_pos
		
		if debug_mode:
			print("AsteroidSpawner: Set position to %s for grid cell (%d,%d)" % [new_pos, x, y])

func _calculate_spawn_position() -> Vector2:
	if use_grid_position:
		if _grid_manager:
			return _grid_manager.cell_to_world(Vector2i(grid_x, grid_y))
		elif _game_settings and _game_settings.has_method("get_cell_world_position"):
			return _game_settings.get_cell_world_position(Vector2i(grid_x, grid_y))
	
	return global_position

func generate_field() -> void:
	if not _asteroid_scenes.has("default") and _asteroid_scenes.is_empty():
		push_error("AsteroidSpawner: Cannot generate field - no asteroid scenes loaded")
		return
	
	if debug_mode:
		print("AsteroidSpawner: Generating field at position: ", global_position)
	
	# Ensure we have clean state
	clear_field()
	
	# Calculate field parameters based on seed
	_field_data = _generate_field_data()
	
	if debug_mode:
		print("AsteroidSpawner: Field data generated with radius: %d and count: %d" % 
			  [_field_data.radius, _field_data.count])
	
	# Create asteroid spawn data
	var asteroid_positions = _generate_asteroid_positions(_field_data)
	
	# Store positions for debug drawing
	_debug_asteroid_positions = asteroid_positions.duplicate(true)
	_debug_asteroids_drawn = false
	
	if debug_mode:
		print("AsteroidSpawner: Generated %d asteroid positions" % asteroid_positions.size())
	
	# Queue asteroids for spawning
	_queue_asteroid_spawns(asteroid_positions)
	
	field_generated.emit(_field_data.radius, asteroid_positions.size())
	
	# Force immediate redraw for debug visualization
	if debug_draw_field or debug_draw_asteroid_positions:
		queue_redraw()

func _generate_field_data() -> Dictionary:
	# Regenerate RNG to ensure consistent results
	_rng.seed = _seed_value
	
	# Apply some variation to field radius
	var radius_factor = 1.0 + (_rng.randf() * 0.4 - 0.2)
	var actual_radius = field_radius * radius_factor
	
	# Determine asteroid count based on radius
	var area_factor = (actual_radius / field_radius) * (actual_radius / field_radius)
	var min_actual = int(min_asteroids * area_factor)
	var max_actual = int(max_asteroids * area_factor)
	var asteroid_count = _rng.randi_range(min_actual, max_actual)
	
	# Generate field shape factor
	var elongation = _rng.randf_range(0.0, 0.3)
	var rotation = _rng.randf() * TAU
	
	# Update debug color deterministically
	_debug_color = Color(
		_rng.randf_range(0.5, 1.0),
		_rng.randf_range(0.3, 0.7),
		_rng.randf_range(0.0, 0.3),
		0.5
	)
	
	return {
		"radius": actual_radius,
		"count": asteroid_count,
		"elongation": elongation,
		"rotation": rotation,
		"min_distance": min_distance_between
	}

func _generate_asteroid_positions(field_data: Dictionary) -> Array:
	var positions = []
	var field_radius = field_data.radius
	var asteroid_count = field_data.count
	var field_rotation = field_data.rotation
	var field_elongation = field_data.elongation
	var min_distance = field_data.min_distance
	
	# Regenerate RNG to ensure consistent results
	_rng.seed = _seed_value
	
	# Attempt to create asteroid positions
	var max_attempts = asteroid_count * 10
	var attempts = 0
	
	while positions.size() < asteroid_count and attempts < max_attempts:
		# Generate random position within field radius
		var distance = _rng.randf() * field_radius
		var angle = _rng.randf() * TAU
		
		# Apply field elongation and rotation
		var stretched_x = cos(angle) * (1.0 - field_elongation)
		var stretched_y = sin(angle)
		var rotated_x = stretched_x * cos(field_rotation) - stretched_y * sin(field_rotation)
		var rotated_y = stretched_x * sin(field_rotation) + stretched_y * cos(field_rotation)
		
		var pos = Vector2(rotated_x, rotated_y) * distance
		
		# Check if position is valid (not too close to other asteroids)
		var valid_position = true
		for existing_pos in positions:
			if existing_pos.position.distance_to(pos) < min_distance:
				valid_position = false
				break
		
		if valid_position:
			var size_category = _determine_size_category()
			var rotation_speed = _rng.randf_range(-max_rotation_speed, max_rotation_speed)
			
			# Scale factor depends on size category
			var base_scale = 1.0
			match size_category:
				"small": base_scale = 0.5
				"medium": base_scale = 1.0
				"large": base_scale = 1.5
			
			# Apply random variation to scale
			var actual_scale = base_scale * (1.0 + (_rng.randf() * size_variation * 2.0 - size_variation))
			
			# Generate random velocity
			var speed = _rng.randf_range(min_linear_speed, max_linear_speed)
			var vel_angle = _rng.randf() * TAU
			var velocity = Vector2(cos(vel_angle), sin(vel_angle)) * speed
			
			positions.append({
				"position": pos,
				"size": size_category,
				"scale": actual_scale,
				"rotation_speed": rotation_speed,
				"velocity": velocity,
				"variant": _rng.randi_range(0, 3), # Variant for texture selection
				"seed": _seed_value + positions.size() * 1000 + int(pos.x * 100) + int(pos.y * 100)
			})
		
		attempts += 1
	
	return positions

func _determine_size_category() -> String:
	var roll = _rng.randf()
	
	if roll < small_asteroid_chance:
		return "small"
	elif roll < small_asteroid_chance + medium_asteroid_chance:
		return "medium"
	else:
		return "large"

func _queue_asteroid_spawns(asteroid_data: Array) -> void:
	_remaining_to_spawn = asteroid_data.duplicate()
	_is_spawning = true
	
	if debug_mode:
		print("AsteroidSpawner: Queued %d asteroids for spawning" % _remaining_to_spawn.size())

func _process(delta: float) -> void:
	if _is_spawning:
		_spawn_timer += delta
		
		if _spawn_timer >= spawn_batch_delay:
			_spawn_timer = 0.0
			_spawn_asteroid_batch()

func _spawn_asteroid_batch() -> void:
	var batch_size = min(max_concurrent_spawns, _remaining_to_spawn.size())
	
	for i in range(batch_size):
		if _remaining_to_spawn.is_empty():
			_is_spawning = false
			all_asteroids_spawned.emit()
			return
		
		var data = _remaining_to_spawn.pop_front()
		_spawn_asteroid(data)
	
	if _remaining_to_spawn.is_empty():
		_is_spawning = false
		if debug_mode:
			print("AsteroidSpawner: All asteroids spawned. Total count: %d" % _spawned_count)
		all_asteroids_spawned.emit()

func _spawn_asteroid(data: Dictionary) -> void:
	# Select appropriate scene
	var asteroid_scene
	
	# Try size-specific scene first
	if _asteroid_scenes.has(data.size):
		asteroid_scene = _asteroid_scenes[data.size]
	else:
		# Fallback to default
		asteroid_scene = _asteroid_scenes["default"]
	
	# Verify we have a valid scene
	if not asteroid_scene:
		if debug_mode:
			print("AsteroidSpawner: Cannot spawn asteroid - scene not loaded")
		return
	
	var asteroid = asteroid_scene.instantiate()
	
	# Determine if asteroid should be a direct child or world child
	if world_space_generation:
		# Add to scene tree directly for independent physics
		get_tree().current_scene.add_child(asteroid)
		
		# Position in world space
		asteroid.global_position = global_position + data.position
	else:
		# Add as child of asteroid field node (local space)
		add_child(asteroid)
		asteroid.position = data.position
	
	# Ensure z-index is set for visibility
	asteroid.z_index = 3
	
	# Generate texture if needed
	if _asteroid_generator_instance and asteroid.get_node_or_null("Sprite2D"):
		_configure_asteroid_texture(asteroid, data)
	
	# Setup asteroid physics properties
	if asteroid.has_method("setup"):
		# New interface with velocity
		asteroid.setup(
			data.size, 
			data.variant, 
			data.scale, 
			data.rotation_speed,
			data.velocity
		)
	else:
		# Legacy interface without velocity
		if asteroid.has_method("setup"):
			asteroid.setup(data.size, data.variant, data.scale, data.rotation_speed)
	
	# Set debug collision shapes flag
	if debug_asteroid_collisions and asteroid.has_member("debug_collision_shapes"):
		asteroid.debug_collision_shapes = true
	
	# Store reference
	_asteroids.append(asteroid)
	_spawned_count += 1
	
	# Register with entity manager
	if _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(asteroid, "asteroid")
	
	# Emit signal
	asteroid_spawned.emit(asteroid)

func _configure_asteroid_texture(asteroid: Node, data: Dictionary) -> void:
	var sprite = asteroid.get_node("Sprite2D")
	var texture = null
	
	# Use the unique asteroid seed for stable texture generation
	var asteroid_seed = data.seed
	
	# Try to load from cache first
	var cache_key = str(asteroid_seed)
	if _texture_cache.has(cache_key):
		texture = _texture_cache[cache_key]
	else:
		# Apply the seed to generator
		_asteroid_generator_instance.seed_value = asteroid_seed
		
		# Generate new texture
		texture = _asteroid_generator_instance.create_asteroid_texture()
		
		# Cache with limit check
		if _texture_cache.size() >= MAX_TEXTURE_CACHE_SIZE:
			# Remove oldest entry (first key)
			var first_key = _texture_cache.keys()[0]
			_texture_cache.erase(first_key)
		
		_texture_cache[cache_key] = texture
	
	# Apply texture to asteroid
	sprite.texture = texture
	
	# Adjust scale based on asteroid size
	var size_value = 16  # Default small size
	match data.size:
		"small": size_value = 16
		"medium": size_value = 32
		"large": size_value = 64
	
	# Scale sprite based on size and data scale
	sprite.scale = Vector2(size_value, size_value) / texture.get_width() * data.scale

# MODIFIED METHOD: Now handles specific fragment types for different asteroid sizes
func _spawn_fragments(position: Vector2, size_category: String, count: int, parent_scale: float, parent_velocity: Vector2 = Vector2.ZERO) -> void:
	# Don't spawn fragments for small asteroids
	if size_category == "small":
		return
	
	if debug_mode:
		print("AsteroidSpawner: Spawning fragments for " + size_category + " asteroid")
	
	# Special handling for large asteroids - spawn 1 medium and 1 small
	if size_category == "large":
		# Spawn medium fragment
		_spawn_single_fragment("medium", position, parent_scale * 0.7, 0, 2, parent_velocity)
		
		# Spawn small fragment
		_spawn_single_fragment("small", position, parent_scale * 0.5, 1, 2, parent_velocity)
		return
	
	# Medium asteroids - spawn 2 small fragments
	elif size_category == "medium":
		for i in range(2):
			_spawn_single_fragment("small", position, parent_scale * 0.6, i, 2, parent_velocity)
		return

# New helper function to spawn a single fragment with specific size
func _spawn_single_fragment(fragment_size: String, position: Vector2, scale: float, index: int, total_fragments: int, parent_velocity: Vector2) -> void:
	# Select appropriate scene
	var asteroid_scene
	
	# Try size-specific scene first
	if _asteroid_scenes.has(fragment_size):
		asteroid_scene = _asteroid_scenes[fragment_size]
	else:
		# Fallback to default
		asteroid_scene = _asteroid_scenes["default"]
	
	if not asteroid_scene:
		return
	
	# Generate fragment position with angle based on index and total fragments
	var angle = (TAU / total_fragments) * index + _rng.randf_range(-0.3, 0.3)
	var distance = _rng.randf_range(10, 30) * scale
	var pos = position + Vector2(cos(angle), sin(angle)) * distance
	
	var asteroid = asteroid_scene.instantiate()
	
	# Add to world directly for best physics
	get_tree().current_scene.add_child(asteroid)
	asteroid.global_position = pos
	
	# Generate rotation
	var rot_speed = _rng.randf_range(-max_rotation_speed, max_rotation_speed) * 1.5
	
	# Calculate fragment velocity - inherit parent velocity plus explosion force
	var explosion_speed = _rng.randf_range(30.0, 60.0)
	var explosion_dir = Vector2(cos(angle), sin(angle))
	var velocity = parent_velocity + explosion_dir * explosion_speed
	
	# Generate unique seed for fragment
	var fragment_seed = _seed_value + index + _spawned_count * 10 + int(pos.x * 10) + int(pos.y * 10)
	
	# Configure texture
	if _asteroid_generator_instance and asteroid.get_node_or_null("Sprite2D"):
		var sprite = asteroid.get_node("Sprite2D")
		var texture = null
		
		# Check cache first
		var cache_key = str(fragment_seed)
		if _texture_cache.has(cache_key):
			texture = _texture_cache[cache_key]
		else:
			# Apply seed to generator
			_asteroid_generator_instance.seed_value = fragment_seed
			
			# Generate texture
			texture = _asteroid_generator_instance.create_asteroid_texture()
			
			# Cache with limit check
			if _texture_cache.size() >= MAX_TEXTURE_CACHE_SIZE:
				# Remove oldest entry
				var first_key = _texture_cache.keys()[0]
				_texture_cache.erase(first_key)
			
			_texture_cache[cache_key] = texture
		
		# Apply texture
		sprite.texture = texture
		
		# Get appropriate size value based on fragment size
		var size_value = 16  # Default for small
		if fragment_size == "medium":
			size_value = 32
		
		# Scale based on texture size
		sprite.scale = Vector2(size_value, size_value) / texture.get_width() * scale
	
	# Setup fragment with new velocity argument
	if asteroid.has_method("setup"):
		asteroid.setup(
			fragment_size,
			_rng.randi_range(0, 3),
			scale,
			rot_speed,
			velocity
		)
	
	# Add to active asteroids
	_asteroids.append(asteroid)
	_spawned_count += 1
	
	# Register with entity manager
	if _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(asteroid, "asteroid")
	
	# Emit signal
	asteroid_spawned.emit(asteroid)

func clear_field() -> void:
	if debug_mode:
		print("AsteroidSpawner: Clearing field with %d asteroids" % _asteroids.size())
	
	# Stop any pending spawns
	_is_spawning = false
	_remaining_to_spawn.clear()
	
	# Remove all existing asteroids
	for asteroid in _asteroids:
		if is_instance_valid(asteroid):
			# Deregister from entity manager
			if _entity_manager and _entity_manager.has_method("deregister_entity"):
				_entity_manager.deregister_entity(asteroid)
			
			# Remove from scene
			asteroid.queue_free()
	
	_asteroids.clear()
	_spawned_count = 0
	
	# Force immediate redraw for debug visualization
	if debug_draw_field or debug_draw_asteroid_positions:
		_debug_asteroid_positions.clear()
		_debug_asteroids_drawn = false
		queue_redraw()

func get_asteroid_count() -> int:
	return _asteroids.size()

func get_field_info() -> Dictionary:
	return {
		"position": global_position,
		"radius": _field_data.get("radius", field_radius),
		"asteroid_count": _spawned_count,
		"grid_position": Vector2i(grid_x, grid_y)
	}

func _draw() -> void:
	if not debug_mode:
		return
	
	if debug_draw_field:
		# Draw field radius
		var radius = _field_data.get("radius", field_radius)
		draw_circle(Vector2.ZERO, radius, Color(_debug_color.r, _debug_color.g, _debug_color.b, 0.1))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, _debug_color, 2.0)
		
		# Draw grid coordinates
		var font_size = 16
		var text = "Grid: (%d,%d)" % [grid_x, grid_y]
		draw_string(ThemeDB.fallback_font, Vector2(-32, -radius - 10), text)
	
	if debug_draw_asteroid_positions and not _debug_asteroid_positions.is_empty():
		# Draw planned asteroid positions
		for data in _debug_asteroid_positions:
			var pos = data.position
			var size = data.size
			var radius = 8
			
			match size:
				"small": radius = 6
				"medium": radius = 10
				"large": radius = 16
			
			draw_circle(pos, radius, Color(1, 1, 1, 0.3))
			draw_arc(pos, radius, 0, TAU, 16, Color(1, 1, 1, 0.8), 1.0)

# Static method to clear texture cache - no instance references
static func clear_texture_cache() -> void:
	# For static methods, we can't access instance variables or methods
	# So we'll rely on SeedManager to propagate the cache clearing
	if Engine.has_singleton("SeedManager"):
		# This will trigger a clean-up across the game
		SeedManager.call_deferred("_clear_additional_caches")
	
	# We don't have direct access to texture_cache from static context
	# That's handled in the generator script instead
