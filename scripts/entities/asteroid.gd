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
	"large": {"health": 70.0, "mass": 6.0, "scale": 1.5, "points": 200, "fragments": 3}
}

# Hit flash effect
var _hit_flash_timer: float = 0.0
var _is_hit_flashing: bool = false
const HIT_FLASH_DURATION: float = 0.1
var _original_modulate: Color = Color.WHITE

# Physics body cache - for optimization
var _cached_thrust_direction: Vector2 = Vector2.ZERO
var _collision_polygon_points: PackedVector2Array

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
		collision_polygon.disabled = false
	else:
		# Create new collision polygon if it doesn't exist
		var new_collision_polygon = CollisionPolygon2D.new()
		new_collision_polygon.name = "CollisionPolygon2D"
		new_collision_polygon.polygon = points
		add_child(new_collision_polygon)
		collision_polygon = new_collision_polygon
	
	# Disable the circle shape if we use a polygon
	if collision_shape:
		collision_shape.disabled = true
	
	# Create simplified collision shape if the polygon is complex
	if autogenerate_convex_shapes and points.size() > 8:
		_create_simplified_collision(points)

# Create primitive collision shape as fallback
func _create_fallback_collision_shape() -> void:
	if not sprite:
		return
	
	if collision_shape and collision_shape.shape is CircleShape2D:
		# Already has a circle shape, just update radius
		var radius = (sprite.texture.get_width() / 2) * sprite.scale.x * 0.9
		collision_shape.shape.radius = radius
	else:
		# Create new circle shape
		var circle = CircleShape2D.new()
		var radius = 16.0 * base_scale
		
		if sprite and sprite.texture:
			radius = (sprite.texture.get_width() / 2) * sprite.scale.x * 0.9
		
		circle.radius = radius
		
		if collision_shape:
			collision_shape.shape = circle
			collision_shape.disabled = false
		else:
			# Create new collision shape if it doesn't exist
			var new_shape = CollisionShape2D.new()
			new_shape.name = "CollisionShape2D"
			new_shape.shape = circle
			add_child(new_shape)
			collision_shape = new_shape
	
	# Disable the polygon if we're using a circle
	if collision_polygon:
		collision_polygon.disabled = true

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
		collision_polygon.disabled = false
	else:
		# Create new collision polygon if it doesn't exist
		var new_collision_polygon = CollisionPolygon2D.new()
		new_collision_polygon.name = "CollisionPolygon2D"
		new_collision_polygon.polygon = simplified_points
		add_child(new_collision_polygon)
		collision_polygon = new_collision_polygon
	
	# Disable the circle shape if we use a polygon
	if collision_shape:
		collision_shape.disabled = true
		
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
	
	# Play hit sound if audio manager is available
	if Engine.has_singleton("AudioManager"):
		AudioManager.play_sfx("asteroid_hit", global_position)

# Explosion and destruction handling
func _on_destroyed() -> void:
	# Use explosion component if available
	if explosion_component and explosion_component.has_method("explode"):
		explosion_component.explode()
	else:
		# Fallback explosion
		_create_explosion()
	
	# Spawn fragments based on size category
	var fragment_count = _size_properties[size_category]["fragments"]
	
	# Get asteroid spawner reference - try parent first as it might be the spawner
	var asteroid_spawner = get_parent()
	
	# Check if parent is actually an asteroid spawner
	if not (asteroid_spawner and asteroid_spawner.has_method("_spawn_fragments")):
		# Otherwise look for global asteroid spawner
		asteroid_spawner = get_node_or_null("/root/Main/AsteroidSpawner")
	
	# Spawn fragments if spawner found
	if asteroid_spawner and asteroid_spawner.has_method("_spawn_fragments") and fragment_count > 0:
		asteroid_spawner._spawn_fragments(
			global_position,
			size_category,
			fragment_count,
			base_scale,
			linear_velocity  # Pass current velocity for more realistic fragments
		)
	
	# Emit destroyed signal with position, size and points
	asteroid_destroyed.emit(global_position, size_category, points_value)
	
	# Notify EntityManager if registered
	if has_meta("entity_id") and has_node("/root/EntityManager") and EntityManager.has_method("deregister_entity"):
		EntityManager.deregister_entity(self)
	
	queue_free()

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
	
	# Play sound if audio manager is available
	if Engine.has_singleton("AudioManager"):
		AudioManager.play_sfx("explosion", global_position)

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
