# scripts/entities/asteroid.gd - Enhanced for destructibility
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

# Physics properties - configurable
@export var min_linear_velocity: float = 5.0
@export var max_linear_velocity: float = 30.0
@export var min_angular_velocity: float = -1.5
@export var max_angular_velocity: float = 1.5
@export var mass_multiplier: float = 2.5  # Increased from 1.0 to make asteroids heavier
@export var damping_factor: float = 0.0  # Use this to set both linear and angular damp
@export var generate_polygon_collision: bool = true
@export var collision_precision: int = 16
@export var collision_simplification: float = 1.5
@export var autogenerate_convex_shapes: bool = true

# Size-specific properties
var _size_properties = {
	"small": {"health": 15.0, "mass": 1.5, "scale": 0.5, "points": 50, "fragments": 0},
	"medium": {"health": 35.0, "mass": 3.0, "scale": 1.0, "points": 100, "fragments": 2},
	"large": {"health": 70.0, "mass": 6.0, "scale": 1.5, "points": 200, "fragments": 2}  # Changed from 3 to 2 fragments
}

# Hit flash effect
var _hit_flash_timer: float = 0.0
var _is_hit_flashing: bool = false
const HIT_FLASH_DURATION: float = 0.1
var _original_modulate: Color = Color.WHITE

# Physics body cache - for optimization
var _cached_thrust_direction: Vector2 = Vector2.ZERO
var _collision_polygon_points: PackedVector2Array

# Audio reference 
var _audio_manager = null

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

	# Delayed collision shape generation (after texture is loaded)
	call_deferred("_setup_collision_shape")
	
	# Make sure we're connected to tree_exiting for audio cleanup
	tree_exiting.connect(_on_tree_exiting)
	
	# Get AudioManager reference
	_audio_manager = get_node_or_null("/root/AudioManager")
	
	# Preload asteroid sounds
	_preload_sounds()

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

# Setup with all needed values at once
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

# Generate polygon collision shape from texture
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
	if collision_polygon:
		collision_polygon.polygon = points
		# FIX: Use set_deferred for changing disabled state
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
		# FIX: Use set_deferred for changing disabled state
		collision_shape.set_deferred("disabled", true)
	
	# Create simplified collision shape if the polygon is complex
	if autogenerate_convex_shapes and points.size() > 8:
		_create_simplified_collision(points)

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

# Create simplified collision shape suitable for physics
func _create_simplified_collision(points: PackedVector2Array) -> void:
	# We'll use a single simplified convex polygon instead of trying
	# to do complex convex decomposition which is failing
	
	# First, check if we have enough points
	if points.size() < 3:
		_create_fallback_collision_shape()
		return
	
	# Simple convexification by using a subset of the points
	# This creates a simplified but usable collision shape
	var simplified_points = PackedVector2Array()
	
	# Take a smaller number of points for better physics stability
	var total_points = min(8, points.size())
	var step = max(1, points.size() / total_points)
	
	for i in range(0, points.size(), step):
		if simplified_points.size() < total_points:
			simplified_points.append(points[i])
	
	# Make sure we have enough points for a polygon
	if simplified_points.size() < 3:
		_create_fallback_collision_shape()
		return
	
	# Ensure the polygon is convex
	simplified_points = _make_convex_hull(simplified_points)
	
	# Use the simplified polygon for collision
	if collision_polygon:
		collision_polygon.polygon = simplified_points
		# FIX: Use set_deferred for changing disabled state
		collision_polygon.set_deferred("disabled", false)
	else:
		# Create new collision polygon if it doesn't exist
		var new_collision_polygon = CollisionPolygon2D.new()
		new_collision_polygon.name = "CollisionPolygon2D"
		new_collision_polygon.polygon = simplified_points
		add_child(new_collision_polygon)
		collision_polygon = new_collision_polygon
	
	# Disable the circle shape if we use a polygon
	if collision_shape:
		# FIX: Use set_deferred for changing disabled state
		collision_shape.set_deferred("disabled", true)
		
# Helper function to create a convex hull
func _make_convex_hull(points: PackedVector2Array) -> PackedVector2Array:
	# Convert to regular array for sorting operations
	var points_array = Array(points)
	
	# Simple implementation of Graham scan algorithm for convex hull
	# First, find the point with lowest y-coordinate (and leftmost if tied)
	var start_idx = 0
	for i in range(1, points_array.size()):
		if points_array[i].y < points_array[start_idx].y or \
		   (points_array[i].y == points_array[start_idx].y and points_array[i].x < points_array[start_idx].x):
			start_idx = i
	
	# Swap the start point to the beginning
	var temp = points_array[0]
	points_array[0] = points_array[start_idx]
	points_array[start_idx] = temp
	
	# Sort the rest of the points by polar angle with respect to start
	var start_point = points_array[0]
	var rest_points = points_array.slice(1)
	
	# Sort using a custom sorting function (works on regular Arrays)
	rest_points.sort_custom(func(a, b): 
		var angle_a = atan2(a.y - start_point.y, a.x - start_point.x)
		var angle_b = atan2(b.y - start_point.y, b.x - start_point.x)
		return angle_a < angle_b
	)
	
	# Rebuild the array with the sorted points
	var sorted_points = [start_point]
	sorted_points.append_array(rest_points)
	
	# If we have fewer than 3 points, we can't make a convex hull
	if sorted_points.size() < 3:
		return PackedVector2Array(sorted_points)
	
	# Build the convex hull
	var hull = [sorted_points[0], sorted_points[1]]
	
	for i in range(2, sorted_points.size()):
		while hull.size() >= 2:
			var p1 = hull[hull.size() - 2]
			var p2 = hull[hull.size() - 1]
			var p3 = sorted_points[i]
			
			# Check if p3 makes a right turn
			var cross_product = (p2.x - p1.x) * (p3.y - p1.y) - (p2.y - p1.y) * (p3.x - p1.x)
			if cross_product >= 0:  # Non-right turn
				break
			
			# Remove the second-to-last point
			hull.pop_back()
		
		hull.append(sorted_points[i])
	
	# Convert back to PackedVector2Array for return
	return PackedVector2Array(hull)

# Get collision rectangle (for legacy compatibility)
func get_collision_rect() -> Rect2:
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size() * sprite.scale
		return Rect2(-texture_size/2, texture_size)
	else:
		# Fallback
		var size = 32 * base_scale
		return Rect2(-size/2, -size/2, size, size)

# Apply damage via health component
func take_damage(amount: float, source = null) -> bool:
	if health_component:
		return health_component.apply_damage(amount, "impact", source)
	return false

# Hit effect handler
func _on_damaged(amount: float, _type: String, _source: Node) -> void:
	# Play hit flash effect
	if sprite:
		sprite.modulate = Color(1.5, 1.5, 1.5, 1.0)  # White flash
		_is_hit_flashing = true
		_hit_flash_timer = HIT_FLASH_DURATION
		set_process(true)

# IMPROVED: Explosion and destruction handling with smart spawner detection
func _on_destroyed() -> void:
	# Use explosion component if available
	if explosion_component and explosion_component.has_method("explode"):
		explosion_component.explode()
	else:
		# Fallback explosion
		_create_explosion()
	
	# Create a sound player for the debris explosion sound
	_play_debris_sound()
	
	# Get fragment count from size properties
	var fragment_count = _size_properties[size_category]["fragments"]
	
	# Only proceed if we need to create fragments
	if fragment_count > 0:
		# Try different methods to find an asteroid spawner
		var asteroid_spawner = _find_asteroid_spawner()
		
		if asteroid_spawner and asteroid_spawner.has_method("handle_legacy_fragment_spawn"):
			# Use the spawner's method if available
			asteroid_spawner.handle_legacy_fragment_spawn(
				global_position,
				size_category,
				fragment_count,
				base_scale,
				linear_velocity
			)
		else:
			# If no spawner found, try direct creation using asteroid generator
			_spawn_fragments_directly()
	
	# Emit destroyed signal with position, size and points
	asteroid_destroyed.emit(global_position, size_category, points_value)
	
	# Notify EntityManager if registered
	if has_meta("entity_id") and has_node("/root/EntityManager") and EntityManager.has_method("deregister_entity"):
		EntityManager.deregister_entity(self)
	
	queue_free()

# Find an asteroid spawner using multiple methods
func _find_asteroid_spawner() -> Node:
	# Method 1: Check if parent is a spawner
	var parent = get_parent()
	if parent and parent.has_method("handle_legacy_fragment_spawn"):
		return parent
	
	# Method 2: Search for spawners in the asteroid_fields group
	var spawners = get_tree().get_nodes_in_group("asteroid_fields")
	if not spawners.is_empty():
		return spawners[0]  # Use the first spawner found
	
	# Method 3: Look for specific paths
	var specific_paths = [
		"/root/Main/AsteroidSpawner",
		"/root/Main/AsteroidField",
		"/root/Main/World/AsteroidSpawner"
	]
	
	for path in specific_paths:
		var node = get_node_or_null(path)
		if node and node.has_method("handle_legacy_fragment_spawn"):
			return node
	
	# Not found
	return null

# Spawn fragments directly using an asteroid generator
func _spawn_fragments_directly() -> void:
	# Skip for small asteroids
	if size_category == "small":
		return
	
	# Find or create asteroid generator
	var generator = _find_or_create_generator()
	if not generator:
		print("Failed to find or create asteroid generator")
		return
	
	# Load the default asteroid scene
	var asteroid_scene = load("res://scenes/entities/asteroid.tscn")
	if not asteroid_scene:
		print("Failed to load asteroid scene")
		return
	
	var rng = RandomNumberGenerator.new()
	rng.seed = hash(global_position.x + global_position.y + Time.get_ticks_msec())
	
	if size_category == "large":
		# Spawn 1 medium and 1 small asteroid
		_spawn_fragment_with_generator(asteroid_scene, generator, "medium", 0.7, 0, 2, rng)
		_spawn_fragment_with_generator(asteroid_scene, generator, "small", 0.5, 1, 2, rng)
	elif size_category == "medium":
		# Spawn 2 small asteroids
		_spawn_fragment_with_generator(asteroid_scene, generator, "small", 0.6, 0, 2, rng)
		_spawn_fragment_with_generator(asteroid_scene, generator, "small", 0.6, 1, 2, rng)

# Find or create an asteroid generator
func _find_or_create_generator() -> Node:
	# Method 1: Look for generators in the scene
	var generators = get_tree().get_nodes_in_group("planet_spawners")  # Asteroid generator is in this group
	for gen in generators:
		if gen.get_script() and gen.get_script().resource_path.find("asteroid_generator") != -1:
			return gen
	
	# Method 2: Try to create a new generator
	var generator_script = load("res://scripts/generators/asteroid_generator.gd")
	if generator_script:
		var new_generator = generator_script.new()
		get_tree().current_scene.add_child(new_generator)
		return new_generator
	
	return null

# Spawn a fragment with texture generation
func _spawn_fragment_with_generator(scene: PackedScene, generator: Node, fragment_size: String, scale_factor: float, index: int, total_fragments: int, rng: RandomNumberGenerator) -> void:
	# Generate fragment position with angle based on index and total fragments
	var angle = (TAU / total_fragments) * index + rng.randf_range(-0.3, 0.3)
	var distance = rng.randf_range(10, 30) * base_scale
	var pos = global_position + Vector2(cos(angle), sin(angle)) * distance
	
	# Create the asteroid
	var asteroid = scene.instantiate()
	get_tree().current_scene.add_child(asteroid)
	asteroid.global_position = pos
	
	# Generate rotation speed
	var rot_speed = rng.randf_range(-1.5, 1.5) 
	
	# Calculate fragment velocity - inherit parent velocity plus explosion force
	var explosion_speed = rng.randf_range(30.0, 60.0)
	var explosion_dir = Vector2(cos(angle), sin(angle))
	var new_velocity = linear_velocity + explosion_dir * explosion_speed
	
	# Generate a unique seed for this fragment
	var fragment_seed = hash(str(global_position) + str(index) + str(Time.get_ticks_msec()))
	
	# Generate texture with the generator
	if generator and generator.has_method("create_asteroid_texture"):
		# Set the seed for deterministic generation
		if "seed_value" in generator:
			generator.seed_value = fragment_seed
		
		# Generate the texture
		var texture = generator.create_asteroid_texture()
		
		# Apply the texture to the asteroid
		if asteroid.has_node("Sprite2D") and texture:
			var sprite = asteroid.get_node("Sprite2D")
			sprite.texture = texture
			
			# Calculate appropriate scale based on size
			var size_value = 16  # Default for small
			if fragment_size == "medium":
				size_value = 32
			elif fragment_size == "large":
				size_value = 64
			
			# Set sprite scale
			sprite.scale = Vector2(size_value, size_value) / texture.get_width() * base_scale * scale_factor
	
	# Set up the asteroid
	if asteroid.has_method("setup"):
		asteroid.setup(
			fragment_size,
			rng.randi_range(0, 3),   # Random variant
			base_scale * scale_factor,
			rot_speed,
			new_velocity
		)
	
	# Register with entity manager
	if has_node("/root/EntityManager") and EntityManager.has_method("register_entity"):
		EntityManager.register_entity(asteroid, "asteroid")

# Play debris sound with special handling to ensure it plays completely
func _play_debris_sound() -> void:
	if _audio_manager:
		# Create a standalone player for the explosion debris sound
		var player = _audio_manager.play_sfx("explosion_debris", global_position, 1.0, 0.0)
		
		# Make sure sound can complete even after asteroid is gone
		if player:
			# Reparent the player to the scene instead of the asteroid
			if player.get_parent() == self:
				remove_child(player)
				get_tree().current_scene.add_child(player)
				player.global_position = global_position

# When tree exiting - ensure sound cleanup
func _on_tree_exiting() -> void:
	# No specific cleanup needed now that we're reparenting the sound
	pass

# Create explosion effect
func _create_explosion() -> void:
	# Check if explosion scene exists
	if ResourceLoader.exists(explosion_scene_path):
		var explosion_scene = load(explosion_scene_path)
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		
		# Size scale based on asteroid size
		var explosion_scale = 0.5
		match size_category:
			"medium": explosion_scale = 1.0
			"large": explosion_scale = 1.5
		
		explosion.scale = Vector2(explosion_scale, explosion_scale)
		get_tree().current_scene.add_child(explosion)
	else:
		# Fallback particles
		var particles = CPUParticles2D.new()
		
		# Configure particles
		particles.emitting = true
		particles.one_shot = true
		particles.explosiveness = 1.0
		particles.amount = 30
		particles.lifetime = 0.6
		particles.global_position = global_position
		particles.direction = Vector2.ZERO
		particles.spread = 180.0
		particles.gravity = Vector2.ZERO
		particles.initial_velocity_min = 100.0
		particles.initial_velocity_max = 150.0
		particles.scale_amount_min = 2.0
		particles.scale_amount_max = 4.0
		
		# Auto cleanup with timer
		get_tree().current_scene.add_child(particles)
		get_tree().create_timer(0.8).timeout.connect(func(): particles.queue_free())

# Apply force in direction
func apply_force_in_direction(direction: Vector2, force: float) -> void:
	apply_central_force(direction.normalized() * force)

# Apply impulse at point
func apply_impulse_at_point(impulse: Vector2, position: Vector2) -> void:
	apply_impulse(impulse, position - global_position)

# Debug draw override
func _draw() -> void:
	if not debug_collision_shapes or not sprite or not visible:
		return
	
	# Draw collision polygon if it exists
	if collision_polygon and not collision_polygon.disabled:
		draw_colored_polygon(collision_polygon.polygon, Color(0, 1, 0, 0.3))
		draw_polyline(collision_polygon.polygon, Color(0, 1, 0, 0.8), 1.0, true)
	
	# Draw collision shape if it exists
	if collision_shape and not collision_shape.disabled and collision_shape.shape is CircleShape2D:
		var radius = collision_shape.shape.radius
		draw_circle(Vector2.ZERO, radius, Color(0, 1, 0, 0.3))
		draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(0, 1, 0, 0.8), 1.0)
