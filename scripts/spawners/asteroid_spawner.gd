extends EntitySpawnerBase
class_name AsteroidSpawner

# Scene paths
const ASTEROID_SCENE = "res://scenes/entities/asteroid.tscn"
const ASTEROID_FIELD_SCENE = "res://scenes/world/asteroid_field.tscn"

# Texture cache to avoid regenerating textures
var _texture_cache = {}
const MAX_TEXTURE_CACHE_SIZE = 20

# Track asteroid fields
var _asteroid_fields = {}

# Generator reference (for texture generation only)
var _texture_generator = null

func _load_common_scenes() -> void:
	_load_scene("asteroid", ASTEROID_SCENE)
	_load_scene("asteroid_field", ASTEROID_FIELD_SCENE)
	
	# Only keep the texture generator
	_texture_generator = load("res://scripts/generators/asteroid_generator.gd").new()
	add_child(_texture_generator)

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
	
	# Apply pre-generated texture if available
	if _texture_generator and asteroid.get_node_or_null("Sprite2D"):
		var sprite = asteroid.get_node("Sprite2D")
		var texture = _get_asteroid_texture(asteroid_data)
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
	
	# Spawn the asteroids from the field data
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

# Handle asteroid destruction for fragment spawning
func _on_asteroid_destroyed(position: Vector2, size: String, _points: int) -> void:
	# This now simply emits an event for the fragment spawner to handle
	if _event_manager:
		_event_manager.emit_or_create("asteroid_destroyed", [position, size])

# Get or generate asteroid texture
func _get_asteroid_texture(asteroid_data: AsteroidData) -> Texture2D:
	var cache_key = str(asteroid_data.texture_seed) + "_" + str(asteroid_data.variant)
	
	# Check cache first
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key]
	
	# Generate texture
	var texture = null
	if _texture_generator:
		_texture_generator.seed_value = asteroid_data.texture_seed
		texture = _texture_generator.create_asteroid_texture()
		
		# Cache the texture
		if texture:
			_texture_cache[cache_key] = texture
			
			# Manage cache size
			if _texture_cache.size() > MAX_TEXTURE_CACHE_SIZE:
				var oldest_key = _texture_cache.keys()[0]
				_texture_cache.erase(oldest_key)
	
	return texture

# Clear cached textures
func clear_texture_cache() -> void:
	_texture_cache.clear()
