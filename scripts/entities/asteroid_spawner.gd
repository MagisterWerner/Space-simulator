# scripts/entities/asteroid_spawner.gd - Optimized implementation
extends Node2D
class_name AsteroidSpawner

signal spawner_ready
signal field_generated(field_size, asteroid_count)

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

# Asteroid properties
@export_category("Asteroid Properties")
@export var small_asteroid_chance: float = 0.3
@export var medium_asteroid_chance: float = 0.5
@export var large_asteroid_chance: float = 0.2
@export var max_rotation_speed: float = 0.5

# Asteroid scenes and performance
@export_category("Scene References")
@export var asteroid_scene_path: String = "res://scenes/entities/asteroid.tscn"
@export_category("Performance")
@export var max_concurrent_spawns: int = 5
@export var spawn_batch_delay: float = 0.05

# Debug options
@export_category("Debug")
@export var debug_field_generation: bool = false

# Internal variables
var _seed_value: int = 0
var _asteroids: Array = []
var _asteroid_scene: PackedScene = null
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
var _asteroid_generator = null
var _asteroid_generator_instance = null

func _ready() -> void:
	# Find required singletons
	_cache_singletons()
	_load_asteroid_scene()
	
	# Initialize asteroid generator for texture generation
	_initialize_asteroid_generator()
	
	# Initialize with a small delay to ensure other systems are ready
	call_deferred("_initialize")
	
	# Register as part of asteroid_fields group
	add_to_group("asteroid_fields")

func _cache_singletons() -> void:
	_game_settings = get_node_or_null("/root/GameSettings")
	_seed_manager = get_node_or_null("/root/SeedManager")
	_entity_manager = get_node_or_null("/root/EntityManager")
	
	# Connect to seed changes if available
	if _seed_manager and _seed_manager.has_signal("seed_changed"):
		_seed_manager.connect("seed_changed", _on_seed_changed)

func _initialize_asteroid_generator() -> void:
	# Load the script first
	var generator_script = load("res://scripts/generators/asteroid_generator.gd")
	if generator_script:
		_asteroid_generator = generator_script
		
		# Create an actual instance for texture generation
		_asteroid_generator_instance = generator_script.new()
		add_child(_asteroid_generator_instance)
		
		if debug_field_generation:
			print("AsteroidSpawner: Asteroid generator initialized")
	else:
		push_error("AsteroidSpawner: Failed to load asteroid generator script")

func _load_asteroid_scene() -> void:
	if ResourceLoader.exists(asteroid_scene_path):
		_asteroid_scene = load(asteroid_scene_path)
		if debug_field_generation:
			print("AsteroidSpawner: Successfully loaded asteroid scene: " + asteroid_scene_path)
	else:
		push_error("AsteroidSpawner: Failed to load asteroid scene: " + asteroid_scene_path)
		
		# Try a fallback path
		var fallback_path = "res://scenes/entities/asteroid.tscn"
		if ResourceLoader.exists(fallback_path):
			if debug_field_generation:
				print("AsteroidSpawner: Using fallback path: " + fallback_path)
			_asteroid_scene = load(fallback_path)
		else:
			push_error("AsteroidSpawner: Fallback path not found either")

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
	
	if debug_field_generation:
		print("AsteroidSpawner: Seed updated to ", _seed_value)

func set_grid_position(x: int, y: int) -> void:
	grid_x = x
	grid_y = y
	_update_seed_value()
	
	if use_grid_position:
		var new_pos = _calculate_spawn_position()
		global_position = new_pos
		
		if debug_field_generation:
			print("AsteroidSpawner: Set position to ", new_pos, " for grid cell (", x, ",", y, ")")

func _calculate_spawn_position() -> Vector2:
	if use_grid_position:
		if _game_settings:
			return _game_settings.get_cell_world_position(Vector2i(grid_x, grid_y))
		elif get_node_or_null("/root/GridManager"):
			return get_node("/root/GridManager").cell_to_world(Vector2i(grid_x, grid_y))
	
	return global_position

func generate_field() -> void:
	if not _asteroid_scene:
		push_error("AsteroidSpawner: Cannot generate field - asteroid scene not loaded")
		return
	
	if debug_field_generation:
		print("AsteroidSpawner: Generating field at position: ", global_position)
	
	# Ensure we have clean state
	clear_field()
	
	# Calculate field parameters based on seed
	_field_data = _generate_field_data()
	
	if debug_field_generation:
		print("AsteroidSpawner: Field data generated with radius: ", _field_data.radius, 
			  " and count: ", _field_data.count)
	
	# Create asteroid spawn data
	var asteroid_positions = _generate_asteroid_positions(_field_data)
	
	if debug_field_generation:
		print("AsteroidSpawner: Generated ", asteroid_positions.size(), " asteroid positions")
	
	# Queue asteroids for spawning
	_queue_asteroid_spawns(asteroid_positions)
	
	field_generated.emit(_field_data.radius, asteroid_positions.size())

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
			
			positions.append({
				"position": pos,
				"size": size_category,
				"scale": actual_scale,
				"rotation_speed": rotation_speed,
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
	
	if debug_field_generation:
		print("AsteroidSpawner: Queued ", _remaining_to_spawn.size(), " asteroids for spawning")

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
			return
		
		var data = _remaining_to_spawn.pop_front()
		_spawn_asteroid(data)
	
	if _remaining_to_spawn.is_empty():
		_is_spawning = false
		if debug_field_generation:
			print("AsteroidSpawner: All asteroids spawned. Total count: ", _spawned_count)

func _spawn_asteroid(data: Dictionary) -> void:
	# Verify we have a valid scene
	if not _asteroid_scene:
		if debug_field_generation:
			print("AsteroidSpawner: Cannot spawn asteroid - scene not loaded")
		return
	
	var asteroid = _asteroid_scene.instantiate()
	add_child(asteroid)
	
	# Position relative to field center
	asteroid.position = data.position
	
	# Ensure z-index is set for visibility
	asteroid.z_index = 3
	
	# Use the unique asteroid seed for stable texture generation
	var asteroid_seed = data.seed
	
	# Check if we already have this texture in cache
	if _asteroid_generator_instance:
		# Apply the seed to generator
		_asteroid_generator_instance.seed_value = asteroid_seed
		
		# Set sprite texture
		if asteroid.get_node_or_null("Sprite2D"):
			var sprite = asteroid.get_node("Sprite2D")
			var texture = null
			
			# Check cache first
			var cache_key = str(asteroid_seed)
			if _texture_cache.has(cache_key):
				texture = _texture_cache[cache_key]
			else:
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
	
	# Setup asteroid properties
	if asteroid.has_method("setup"):
		asteroid.setup(data.size, data.variant, data.scale, data.rotation_speed)
		if debug_field_generation:
			print("AsteroidSpawner: Setup asteroid with size: ", data.size, 
				  ", scale: ", data.scale, ", rot speed: ", data.rotation_speed)
	
	# Store reference
	_asteroids.append(asteroid)
	_spawned_count += 1
	
	# Register with entity manager if available
	if _entity_manager and _entity_manager.has_method("register_entity"):
		_entity_manager.register_entity(asteroid, "asteroid")

func _spawn_fragments(position: Vector2, size_category: String, count: int, parent_scale: float) -> void:
	# Don't spawn fragments for small asteroids
	if size_category == "small":
		return
	
	# Determine fragment size
	var fragment_size = "small"
	if size_category == "large":
		fragment_size = "medium"
	
	if debug_field_generation:
		print("AsteroidSpawner: Spawning ", count, " fragments of size ", fragment_size)
	
	for i in range(count):
		var angle = (TAU / count) * i + _rng.randf_range(-0.3, 0.3)
		var distance = _rng.randf_range(10, 30) * parent_scale
		var pos = position + Vector2(cos(angle), sin(angle)) * distance
		
		var asteroid = _asteroid_scene.instantiate()
		add_child(asteroid)
		
		# Position at fragment location
		asteroid.global_position = pos
		
		# Give random velocity - normally you'd use physics for this
		var rot_speed = _rng.randf_range(-max_rotation_speed, max_rotation_speed) * 1.5
		var scale = parent_scale * (0.6 if fragment_size == "medium" else 0.4)
		
		# Generate unique seed for fragment
		var fragment_seed = _seed_value + i + _spawned_count * 10 + int(pos.x * 10) + int(pos.y * 10)
		
		# Set sprite texture
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
			
			# Get appropriate size
			var size_value = fragment_size == "medium" if 32 else 16
			
			# Scale based on texture size
			sprite.scale = Vector2(size_value, size_value) / texture.get_width() * scale
		
		# Setup fragment
		if asteroid.has_method("setup"):
			asteroid.setup(fragment_size, _rng.randi_range(0, 3), scale, rot_speed)
		
		# Add to active asteroids
		_asteroids.append(asteroid)
		_spawned_count += 1
		
		# Register with entity manager if available
		if _entity_manager and _entity_manager.has_method("register_entity"):
			_entity_manager.register_entity(asteroid, "asteroid")

func clear_field() -> void:
	if debug_field_generation:
		print("AsteroidSpawner: Clearing field with ", _asteroids.size(), " asteroids")
	
	for asteroid in _asteroids:
		if is_instance_valid(asteroid):
			# Deregister from entity manager
			if _entity_manager and _entity_manager.has_method("deregister_entity"):
				_entity_manager.deregister_entity(asteroid)
			
			# Remove from scene
			asteroid.queue_free()
	
	_asteroids.clear()
	_spawned_count = 0
	_remaining_to_spawn.clear()
	_is_spawning = false

func get_asteroid_count() -> int:
	return _asteroids.size()

func get_field_info() -> Dictionary:
	return {
		"position": global_position,
		"radius": _field_data.get("radius", field_radius),
		"asteroid_count": _spawned_count,
		"grid_position": Vector2i(grid_x, grid_y)
	}
