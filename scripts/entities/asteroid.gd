# scripts/entities/asteroid.gd
extends RigidBody2D
class_name Asteroid

# Signal declarations
signal asteroid_destroyed(position, size, points)

# Core components and properties
@onready var health_component: HealthComponent = $HealthComponent
@onready var explosion_component: ExplodeDebrisComponent = $ExplodeDebrisComponent
@onready var sprite: Sprite2D = $Sprite2D
@onready var collision_shape: CollisionShape2D = $CollisionShape2D
@onready var collision_polygon: CollisionPolygon2D = $CollisionPolygon2D

# Asteroid properties
var size_category: String = "medium"
var points_value: int = 100
var base_scale: float = 1.0
var field_data = null
var explosion_scene_path: String = "res://scenes/explosion_effect.tscn"
var entity_id: int = 0
var seed_value: int = 0

# Physics properties - configurable
@export var min_linear_velocity: float = 5.0
@export var max_linear_velocity: float = 30.0
@export var min_angular_velocity: float = -1.5
@export var max_angular_velocity: float = 1.5
@export var mass_multiplier: float = 2.5
@export var damping_factor: float = 0.0
@export var generate_polygon_collision: bool = true
@export var collision_precision: int = 16
@export var collision_simplification: float = 1.5
@export var autogenerate_convex_shapes: bool = true

# Size-specific properties
var _size_properties = {
	"small": {"health": 15.0, "mass": 1.5, "scale": 0.5, "points": 50, "fragments": 0},
	"medium": {"health": 35.0, "mass": 3.0, "scale": 1.0, "points": 100, "fragments": 2},
	"large": {"health": 70.0, "mass": 6.0, "scale": 1.5, "points": 200, "fragments": 2}
}

# Hit flash effect
var _hit_flash_timer: float = 0.0
var _is_hit_flashing: bool = false
const HIT_FLASH_DURATION: float = 0.1
var _original_modulate: Color = Color.WHITE

# Physics body cache - for optimization
var _cached_thrust_direction: Vector2 = Vector2.ZERO
var _collision_polygon_points: PackedVector2Array

# Manager references
var _audio_manager = null
var _fragment_pool_manager = null
var _effect_pool_manager = null

# Debug properties
var debug_mode: bool = false
var debug_collision_shapes: bool = false

func _ready() -> void:
	# Basic setup
	add_to_group("asteroids")
	
	# Configure rigid body properties
	set_process(true)
	gravity_scale = 0.0
	linear_damp_mode = DAMP_MODE_COMBINE
	angular_damp_mode = DAMP_MODE_COMBINE
	linear_damp = damping_factor
	angular_damp = damping_factor
	custom_integrator = false
	
	# Connect signals
	if health_component:
		health_component.damaged.connect(_on_damaged)
		health_component.died.connect(_on_destroyed)
	
	# Store original modulate
	if sprite:
		_original_modulate = sprite.modulate

	# Make sure we're connected to tree_exiting for audio cleanup
	tree_exiting.connect(_on_tree_exiting)
	
	# Get manager references
	_audio_manager = get_node_or_null("/root/AudioManager")
	_fragment_pool_manager = get_node_or_null("/root/FragmentPoolManager")
	_effect_pool_manager = get_node_or_null("/root/EffectPoolManager")
	
	# Preload sounds
	_preload_sounds()

# Setting up from asteroid data
func setup_from_data(asteroid_data: AsteroidData) -> void:
	# Set core properties
	entity_id = asteroid_data.entity_id
	seed_value = asteroid_data.seed_value
	
	# Convert size category from enum to string
	var size_string = "medium"
	match asteroid_data.size_category:
		AsteroidData.SizeCategory.SMALL: size_string = "small"
		AsteroidData.SizeCategory.MEDIUM: size_string = "medium"
		AsteroidData.SizeCategory.LARGE: size_string = "large"
	
	# Set size category and scale
	size_category = size_string
	base_scale = asteroid_data.scale_factor
	
	# Set physical properties
	if sprite:
		sprite.scale = Vector2(base_scale, base_scale)
	
	# Update health based on size and asteroid data
	if health_component:
		health_component.max_health = asteroid_data.health
		health_component.current_health = asteroid_data.health
	
	# Set physics properties
	mass = asteroid_data.mass * mass_multiplier * base_scale
	points_value = asteroid_data.points_value
	
	# Apply movement
	linear_velocity = asteroid_data.linear_velocity
	angular_velocity = asteroid_data.angular_velocity
	
	# Set up collision shape using the data
	if asteroid_data.collision_points.size() > 0:
		_create_collision_from_points(asteroid_data.collision_points)
	else:
		# If no collision points provided, generate them
		call_deferred("_setup_collision_shape")
	
	# Apply texture if we have seed and sprite
	if sprite and asteroid_data.texture_seed > 0:
		_apply_texture_from_seed(asteroid_data.texture_seed, asteroid_data.variant)

# Apply texture from seed
func _apply_texture_from_seed(texture_seed: int, variant: int) -> void:
	if not sprite:
		return
	
	# Find or create asteroid generator
	var generator = _find_or_create_generator()
	if not generator:
		return
	
	# Generate and apply texture
	generator.seed_value = texture_seed
	var texture = generator.create_asteroid_texture(variant)
	if texture:
		sprite.texture = texture

# Find or create asteroid generator
func _find_or_create_generator() -> Node:
	# Find existing generator in scene
	var generators = get_tree().get_nodes_in_group("planet_spawners")  # Asteroid generator is in this group
	for gen in generators:
		if gen.get_script() and gen.get_script().resource_path.find("asteroid_generator") != -1:
			return gen
	
	# Create new if not found
	var generator_script = load("res://scripts/generators/asteroid_generator.gd")
	if generator_script:
		var new_generator = generator_script.new()
		get_tree().current_scene.add_child(new_generator)
		return new_generator
	
	return null

# Create collision shape from provided points
func _create_collision_from_points(points: PackedVector2Array) -> void:
	if points.size() < 3:
		_create_fallback_collision_shape()
		return
	
	_collision_polygon_points = points
	
	# Use the points for collision
	if collision_polygon:
		collision_polygon.polygon = points
		collision_polygon.set_deferred("disabled", false)
	else:
		# Create new collision polygon if it doesn't exist
		var new_collision_polygon = CollisionPolygon2D.new()
		new_collision_polygon.name = "CollisionPolygon2D"
		new_collision_polygon.polygon = points
		add_child(new_collision_polygon)
		collision_polygon = new_collision_polygon
	
	# Disable the circle shape if we use a polygon
	if collision_shape:
		collision_shape.set_deferred("disabled", true)

func _preload_sounds() -> void:
	if _audio_manager:
		# Only preload explosion debris sound
		if not _audio_manager.is_sfx_loaded("explosion_debris"):
			_audio_manager.preload_sfx("explosion_debris", "res://assets/audio/explosion_debris.wav", 20)

# Process function for hit flash effect
func _process(delta: float) -> void:
	if _is_hit_flashing:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0:
			_is_hit_flashing = false
			if sprite:
				sprite.modulate = _original_modulate
			
			# Turn off process if no hit flashing needed
			if not _is_hit_flashing:
				set_process(false)

# Regular setup method (kept for backward compatibility)
func setup(size: String, variant: int, scale_value: float, rot_speed: float = 0.0, initial_vel: Vector2 = Vector2.ZERO) -> void:
	# Store properties
	size_category = size
	base_scale = scale_value
	
	# Set properties based on size category
	var size_props = _size_properties.get(size_category, _size_properties["medium"])
	
	# Apply scale
	if sprite:
		sprite.scale = Vector2(scale_value, scale_value)
	
	# Update health based on size
	if health_component:
		health_component.max_health = size_props["health"]
		health_component.current_health = health_component.max_health
	
	# Set physics properties - increased mass multiplier for all asteroids
	mass = size_props["mass"] * mass_multiplier * scale_value
	points_value = size_props["points"]
	
	# Apply initial movement - external initial velocity takes precedence
	if initial_vel != Vector2.ZERO:
		linear_velocity = initial_vel
	else:
		# Generate random velocity based on size
		var speed = randf_range(min_linear_velocity, max_linear_velocity)
		var angle = randf() * TAU
		linear_velocity = Vector2(cos(angle), sin(angle)) * speed
	
	# Apply random rotation
	if rot_speed != 0.0:
		angular_velocity = rot_speed
	else:
		angular_velocity = randf_range(min_angular_velocity, max_angular_velocity)
	
	# Make small asteroids move faster
	if size_category == "small":
		linear_velocity *= 1.5
	
	# Generate collision shapes after texture is ready (with retry)
	call_deferred("_setup_collision_shape")

# Generate collision shape based on texture
func _setup_collision_shape() -> void:
	# Wait for sprite texture to be ready
	if not sprite or not sprite.texture:
		await get_tree().process_frame
		if not sprite or not sprite.texture:
			# Fallback to circle shape if texture never loads
			_create_fallback_collision_shape()
			return

	if generate_polygon_collision:
		_generate_polygon_collision()
	else:
		_create_fallback_collision_shape()

# Create primitive collision shape as fallback
func _create_fallback_collision_shape() -> void:
	if not sprite:
		return
	
	var radius = 16.0 * base_scale  # Default radius based on scale
	
	if sprite.texture:
		radius = (sprite.texture.get_width() / 2) * sprite.scale.x * 0.9
	
	if collision_shape and collision_shape.shape is CircleShape2D:
		# Already has a circle shape, just update radius
		collision_shape.shape.radius = radius
		# FIX: Use set_deferred for changing disabled state
		collision_shape.set_deferred("disabled", false)
	else:
		# Create new circle shape
		var circle = CircleShape2D.new()
		circle.radius = radius
		
		if collision_shape:
			collision_shape.shape = circle
			# FIX: Use set_deferred for changing disabled state
			collision_shape.set_deferred("disabled", false)
		else:
			# Create new collision shape if it doesn't exist
			var new_shape = CollisionShape2D.new()
			new_shape.name = "CollisionShape2D"
			new_shape.shape = circle
			add_child(new_shape)
			collision_shape = new_shape
	
	# Disable the polygon if we're using a circle
	if collision_polygon:
		# FIX: Use set_deferred for changing disabled state
		collision_polygon.set_deferred("disabled", true)

# Generate polygon collision from sprite
func _generate_polygon_collision() -> void:
	if not sprite or not sprite.texture:
		_create_fallback_collision_shape()
		return
	
	var bitmap = BitMap.new()
	bitmap.create_from_image_alpha(sprite.texture.get_image(), 0.5)
	
	var polygon_points = bitmap.opaque_to_polygons(Rect2(Vector2.ZERO, sprite.texture.get_size()), collision_simplification)
	
	if polygon_points.is_empty():
		_create_fallback_collision_shape()
		return
	
	# Use the most complex polygon for better collision accuracy
	var most_complex_polygon_index = 0
	var most_complex_point_count = 0
	
	for i in range(polygon_points.size()):
		if polygon_points[i].size() > most_complex_point_count:
			most_complex_point_count = polygon_points[i].size()
			most_complex_polygon_index = i
	
	var points = polygon_points[most_complex_polygon_index]
	
	# If too many points, simplify by sampling every Nth point
	if points.size() > collision_precision:
		var simplified_points = PackedVector2Array()
		var step = int(points.size() / collision_precision)
		step = max(1, step)
		
		for i in range(0, points.size(), step):
			simplified_points.append(points[i])
		
		points = simplified_points
	
	# Center the points around origin
	var texture_size = sprite.texture.get_size()
	var texture_center = texture_size / 2
	
	for i in range(points.size()):
		# Offset to center and scale to match sprite scale
		points[i] = (points[i] - texture_center) * sprite.scale.x
	
	# Store the points for later
	_collision_polygon_points = points
	
	# Use the simplified polygon for collision
	_create_collision_from_points(points)

# Event handlers
func _on_damaged(amount: float, _type: String, _source: Node) -> void:
	# Play hit flash effect
	if sprite:
		sprite.modulate = Color(1.5, 1.5, 1.5, 1.0)  # White flash
		_is_hit_flashing = true
		_hit_flash_timer = HIT_FLASH_DURATION
		set_process(true)

func _on_destroyed() -> void:
	# Use explosion component if available
	if explosion_component and explosion_component.has_method("explode"):
		explosion_component.explode()
	else:
		# Fallback explosion
		_create_explosion()
	
	# Play debris sound
	_play_debris_sound()
	
	# Get fragment count from size properties
	var fragment_count = _size_properties[size_category]["fragments"]
	
	# Only proceed if we need to create fragments
	if fragment_count > 0:
		# Use the fragment pool manager if available
		if _fragment_pool_manager and _fragment_pool_manager.has_method("spawn_fragments_for_asteroid"):
			# Convert size category from string to enum
			var size_enum
			match size_category:
				"small": size_enum = AsteroidData.SizeCategory.SMALL
				"medium": size_enum = AsteroidData.SizeCategory.MEDIUM
				"large": size_enum = AsteroidData.SizeCategory.LARGE
				_: size_enum = AsteroidData.SizeCategory.MEDIUM
			
			# Create temporary asteroid data
			var temp_data = AsteroidData.new(
				entity_id, # use our entity ID
				global_position,
				seed_value,
				size_enum
			)
			temp_data.scale_factor = base_scale
			temp_data.linear_velocity = linear_velocity
			
			# Use pool to spawn fragments
			_fragment_pool_manager.spawn_fragments_for_asteroid(temp_data)
		else:
			# Fallback to direct creation if fragment pool not available
			_spawn_fragments_directly()
	
	# Create visual explosion effect using pool if available
	if _effect_pool_manager:
		var scale_multiplier = 1.0
		if size_category == "large":
			scale_multiplier = 1.5
		elif size_category == "small":
			scale_multiplier = 0.7
			
		_effect_pool_manager.explosion(global_position, size_category, 0, base_scale * scale_multiplier)
	
	# Emit destroyed signal with position, size and points
	asteroid_destroyed.emit(global_position, size_category, points_value)
	
	# Notify EntityManager if registered
	if has_meta("entity_id") and has_node("/root/EntityManager") and EntityManager.has_method("deregister_entity"):
		EntityManager.deregister_entity(self)
	
	queue_free()

# Fallback explosion creation
func _create_explosion() -> void:
	# Skip if effect pool manager is available
	if _effect_pool_manager:
		return
		
	# Create a simple explosion effect
	var particles = CPUParticles2D.new()
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 50
	particles.lifetime = 0.5
	particles.local_coords = false
	particles.direction = Vector2.ZERO
	particles.spread = 180
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 100
	particles.initial_velocity_max = 300
	
	# Scale based on asteroid size
	var scale_multiplier = 1.0
	if size_category == "large":
		scale_multiplier = 1.5
		particles.amount = 75
	elif size_category == "small":
		scale_multiplier = 0.7
		particles.amount = 30
	
	particles.scale_amount = base_scale * scale_multiplier
	
	# Create gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.7, 0.3, 1.0))
	gradient.add_point(0.5, Color(1.0, 0.3, 0.1, 0.8))
	gradient.add_point(1.0, Color(0.2, 0.2, 0.2, 0))
	particles.color_ramp = gradient
	
	get_parent().add_child(particles)
	particles.global_position = global_position
	
	# Auto-cleanup
	get_tree().create_timer(2.0).timeout.connect(particles.queue_free)

# Play sound for asteroid destruction
func _play_debris_sound() -> void:
	if _audio_manager:
		_audio_manager.play_sfx("explosion_debris", global_position)

# Fallback fragment spawning if fragment pool unavailable
func _spawn_fragments_directly() -> void:
	# Try different methods to find an asteroid spawner
	var asteroid_spawner = _find_asteroid_spawner()
	
	if asteroid_spawner and asteroid_spawner.has_method("_spawn_fragments"):
		# Use the spawner's method if available
		asteroid_spawner._spawn_fragments(
			global_position,
			size_category,
			_size_properties[size_category]["fragments"],
			base_scale,
			linear_velocity
		)
	else:
		# Direct creation of simple fragments if no spawner
		_create_simple_fragments()

# Find asteroid spawner
func _find_asteroid_spawner() -> Node:
	# Try to find existing spawner
	var spawners = get_tree().get_nodes_in_group("spawners")
	for spawner in spawners:
		if spawner.get_script() and (
			spawner.get_script().resource_path.find("asteroid_spawner.gd") != -1 or
			spawner.get_script().resource_path.find("fragment_spawner.gd") != -1
		):
			return spawner
	return null

# Create simple fragments in case no spawner or pool is available
func _create_simple_fragments() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var fragment_count = _size_properties[size_category]["fragments"]
	if fragment_count <= 0:
		return
		
	for i in range(fragment_count):
		var fragment = Node2D.new()
		fragment.name = "SimpleFragment_" + str(i)
		
		# Setup visible representation
		var sprite = Sprite2D.new()
		sprite.name = "Sprite"
		
		# Use a circle as a simple shape if no texture
		if not sprite.texture:
			var radius = 8 if size_category == "large" else 5
			var img = Image.create(radius * 2, radius * 2, false, Image.FORMAT_RGBA8)
			img.fill(Color(0.5, 0.5, 0.5, 1.0))
			
			# Draw a circle
			for x in range(radius * 2):
				for y in range(radius * 2):
					var dist = Vector2(x - radius, y - radius).length()
					if dist <= radius:
						img.set_pixel(x, y, Color(0.7, 0.7, 0.7, 1.0))
			
			sprite.texture = ImageTexture.create_from_image(img)
		
		fragment.add_child(sprite)
		get_parent().add_child(fragment)
		
		# Position and initial velocity
		var angle = (TAU / fragment_count) * i + rng.randf_range(-0.3, 0.3)
		var distance = rng.randf_range(10, 30)
		fragment.global_position = global_position + Vector2(cos(angle), sin(angle)) * distance
		
		# Setup animation to fade out
		var tween = create_tween()
		tween.tween_property(sprite, "modulate", Color(1, 1, 1, 0), 1.0)
		tween.tween_callback(fragment.queue_free)
		
		# Add simple movement
		var anim = fragment.create_tween()
		var explosion_dir = Vector2(cos(angle), sin(angle))
		var target_pos = fragment.global_position + explosion_dir * rng.randf_range(50, 100)
		anim.tween_property(fragment, "global_position", target_pos, 1.0)

func _on_tree_exiting() -> void:
	# Clean up any references
	# This ensures no memory leaks from signals
	if sprite:
		_original_modulate = Color.WHITE
