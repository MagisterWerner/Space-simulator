# scripts/spawners/asteroid_spawner.gd
extends EntitySpawnerBase
class_name AsteroidSpawner

# Scene paths
const ASTEROID_SCENE = "res://scenes/entities/asteroid.tscn"
const ASTEROID_FIELD_SCENE = "res://scenes/world/asteroid_field.tscn"

# Texture cache to avoid regenerating textures
var _texture_cache = {}
const MAX_TEXTURE_CACHE_SIZE = 20

# References to generators
var _asteroid_generator = null
var _field_generator = null

# Track asteroid fields
var _asteroid_fields = {}

func _load_common_scenes() -> void:
	_load_scene("asteroid", ASTEROID_SCENE)
	_load_scene("asteroid_field", ASTEROID_FIELD_SCENE)
	
	# Initialize generators
	_asteroid_generator = load("res://scripts/generators/asteroid_generator.gd").new()
	add_child(_asteroid_generator)
	
	# Generate a texture seed for the asteroid generator
	if _asteroid_generator:
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		_asteroid_generator.seed_value = rng.randi_range(1, 1000000)

func spawn_entity(data: EntityData) -> Node:
	if not _initialized:
		await spawner_ready
	
	if data is AsteroidData:
		return spawn_asteroid(data)
	elif data is AsteroidFieldData:
		return spawn_asteroid_field(data)
	
	push_error("AsteroidSpawner: Unknown data type for spawning")
	return null

func spawn_asteroid(asteroid_data: AsteroidData) -> Node:
	if not _scene_cache.has("asteroid"):
		push_error("AsteroidSpawner: Missing asteroid scene")
		return null
	
	# Instantiate the asteroid
	var asteroid = _scene_cache["asteroid"].instantiate()
	add_child(asteroid)
	
	# Set position
	asteroid.global_position = asteroid_data.position
	
	# Convert size category to string
	var size_category_string = ""
	match asteroid_data.size_category:
		AsteroidData.SizeCategory.SMALL: size_category_string = "small"
		AsteroidData.SizeCategory.MEDIUM: size_category_string = "medium"
		AsteroidData.SizeCategory.LARGE: size_category_string = "large"
		_: size_category_string = "medium"
	
	# Generate and apply texture
	if _asteroid_generator and asteroid.get_node_or_null("Sprite2D"):
		var sprite = asteroid.get_node("Sprite2D")
		var texture = _get_or_generate_texture(asteroid_data)
		if texture:
			sprite.texture = texture
	
	# Setup asteroid with data
	if asteroid.has_method("setup"):
		asteroid.setup(
			size_category_string,
			asteroid_data.variant,
			asteroid_data.scale_factor,
			asteroid_data.rotation_speed,
			asteroid_data.linear_velocity
		)
	
	# Connect to asteroid destroyed signal
	if asteroid.has_signal("asteroid_destroyed") and not asteroid.is_connected("asteroid_destroyed", _on_asteroid_destroyed):
		asteroid.connect("asteroid_destroyed", _on_asteroid_destroyed)
	
	# Register with entity manager
	register_entity(asteroid, "asteroid", asteroid_data)
	
	return asteroid

func spawn_asteroid_field(field_data: AsteroidFieldData) -> Node:
	if not _scene_cache.has("asteroid_field"):
		# Create a simple Node2D as fallback
		var field = Node2D.new()
		field.name = "AsteroidField_" + str(field_data.entity_id)
		add_child(field)
		field.global_position = field_data.position
		
		# Spawn all asteroids
		for asteroid_data in field_data.asteroids:
			var asteroid = spawn_asteroid(asteroid_data)
			if asteroid:
				# Recalculate position relative to field
				asteroid.position = asteroid_data.position - field_data.position
				field.add_child(asteroid)
		
		# Register with entity manager
		register_entity(field, "asteroid_field", field_data)
		
		_asteroid_fields[field_data.entity_id] = field
		return field
	
	# Instantiate asteroid field scene
	var field = _scene_cache["asteroid_field"].instantiate()
	add_child(field)
	
	# Configure field
	field.global_position = field_data.position
	field.name = "AsteroidField_" + str(field_data.entity_id)
	
	# Configure field properties if methods exist
	if field.has_method("set_grid_position") and field_data.grid_cell != Vector2i(-1, -1):
		field.set_grid_position(field_data.grid_cell.x, field_data.grid_cell.y)
	
	# Add custom properties
	if has_property(field, "field_radius"):
		field.field_radius = field_data.field_radius
	
	if has_property(field, "min_asteroids"):
		field.min_asteroids = field_data.min_asteroids
	
	if has_property(field, "max_asteroids"):
		field.max_asteroids = field_data.max_asteroids
	
	# Generate field if it has the method
	if field.has_method("generate_field"):
		field.generate_field()
	else:
		# Manually spawn asteroids
		for asteroid_data in field_data.asteroids:
			var asteroid = spawn_asteroid(asteroid_data)
			if asteroid:
				# Move it to the field
				remove_child(asteroid)
				field.add_child(asteroid)
				asteroid.position = asteroid_data.position - field_data.position
	
	# Register with entity manager
	register_entity(field, "asteroid_field", field_data)
	
	_asteroid_fields[field_data.entity_id] = field
	return field

# Generate asteroid fragments when an asteroid is destroyed
func _on_asteroid_destroyed(position: Vector2, size: String, _points: int) -> void:
	if size == "small":
		return # Small asteroids don't generate fragments
	
	# Create fragments
	spawn_fragments_at(position, size)

# Spawn fragments at a position with given parameters
func spawn_fragments_at(position: Vector2, size: String, variant: int = 0, parent_velocity: Vector2 = Vector2.ZERO) -> Array:
	var fragments = []
	
	# Determine how many fragments to spawn
	var fragment_count = 2  # Default for medium
	var fragment_sizes = []
	
	if size == "large":
		fragment_count = 2
		fragment_sizes = ["medium", "small"]
	else:  # Medium
		fragment_count = 2
		fragment_sizes = ["small", "small"]
	
	# Set up random generator for variations
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Create the fragments
	for i in range(fragment_count):
		# Calculate positions with slight randomization
		var angle = (TAU / fragment_count) * i + rng.randf_range(-0.3, 0.3)
		var distance = rng.randf_range(10, 30)
		var fragment_pos = position + Vector2(cos(angle), sin(angle)) * distance
		
		# Create unique id and seed
		var fragment_id = rng.randi_range(1000, 9999) + i
		var fragment_seed = rng.randi_range(1, 1000000) + i
		
		# Determine fragment size
		var fragment_size_category = AsteroidData.SizeCategory.SMALL
		if i < fragment_sizes.size() and fragment_sizes[i] == "medium":
			fragment_size_category = AsteroidData.SizeCategory.MEDIUM
		
		# Create asteroid data
		var asteroid_data = AsteroidData.new(
			fragment_id,
			fragment_pos,
			fragment_seed,
			fragment_size_category
		)
		
		# Set physical properties
		asteroid_data.variant = variant
		
		# Scale based on size
		var scale_factor = 0.5  # For small
		if fragment_size_category == AsteroidData.SizeCategory.MEDIUM:
			scale_factor = 0.7
		asteroid_data.scale_factor = scale_factor * rng.randf_range(0.9, 1.1)
		
		# Calculate velocity (parent velocity + explosion force)
		var explosion_dir = Vector2(cos(angle), sin(angle))
		var explosion_speed = rng.randf_range(30.0, 60.0)
		asteroid_data.linear_velocity = parent_velocity + explosion_dir * explosion_speed
		
		# Set rotation
		asteroid_data.rotation_speed = rng.randf_range(-1.5, 1.5)
		
		# Spawn the asteroid
		var fragment = spawn_asteroid(asteroid_data)
		if fragment:
			fragments.append(fragment)
	
	# Play explosion sound if available
	if _audio_manager:
		_audio_manager.play_sfx("explosion_debris", position)
	
	return fragments

# Get or generate asteroid texture
func _get_or_generate_texture(asteroid_data: AsteroidData) -> Texture2D:
	var cache_key = str(asteroid_data.texture_seed) + "_" + str(asteroid_data.variant)
	
	# Check cache first
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	
	# Generate texture
	var texture = null
	if _asteroid_generator:
		_asteroid_generator.seed_value = asteroid_data.texture_seed
		texture = _asteroid_generator.create_asteroid_texture()
		
		# Cache the texture
		if texture:
			_texture_cache[cache_key] = texture
			
			# Manage cache size
			if _texture_cache.size() > MAX_TEXTURE_CACHE_SIZE:
				var oldest_key = _texture_cache.keys()[0]
				_texture_cache.erase(oldest_key)
	
	return texture

# Utility function to create an asteroid field at a specific grid cell
func spawn_asteroid_field_at_cell(cell: Vector2i) -> Node:
	# Create a new field data
	var entity_id = 1
	if _entity_manager and _entity_manager.has_method("get_next_entity_id"):
		entity_id = _entity_manager.get_next_entity_id()
	
	# Calculate world position from cell
	var position = _get_cell_world_position(cell)
	
	# Create seed
	var seed_value = 0
	if _game_settings:
		var base_seed = _game_settings.get_seed()
		seed_value = base_seed + (cell.x * 1000) + (cell.y * 100) + 5000  # Offset for asteroid fields
	
	# Create and configure field data
	var field_generator = AsteroidDataGenerator.new(seed_value)
	var field_data = field_generator.generate_asteroid_field(entity_id, position, seed_value)
	
	# Set grid cell
	field_data.grid_cell = cell
	
	# Generate asteroids for the field
	field_generator.populate_asteroid_field(field_data, null)
	
	# Spawn the field
	return spawn_asteroid_field(field_data)

# Clear cached textures
func clear_texture_cache() -> void:
	_texture_cache.clear()
