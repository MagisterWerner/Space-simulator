extends Component
class_name PhysicsComponent

signal collision_occurred(with_object, collision_point)

@export var mass: float = 1.0
@export var drag: float = 0.1
@export var max_velocity: float = 1000.0
@export var bounce_factor: float = 0.5
@export var affected_by_gravity: bool = true

var velocity: Vector2 = Vector2.ZERO
var acceleration: Vector2 = Vector2.ZERO
var forces: Array[Vector2] = []
var gravity_sources: Array = []

func _initialize():
	# Find gravity sources in the scene
	update_gravity_sources()

func _physics_process(delta):
	# Calculate forces (like gravity) and apply physics
	update_forces(delta)
	
	# Apply acceleration based on forces
	apply_forces(delta)
	
	# Apply velocity to position
	entity.global_position += velocity * delta
	
	# Apply drag to gradually slow down
	velocity = velocity.lerp(Vector2.ZERO, drag * delta)
	
	# Check for collisions with other physics objects
	check_collisions()

func update_gravity_sources():
	gravity_sources.clear()
	
	# Find all planets (or other gravity sources) in the scene
	var planets = get_tree().get_nodes_in_group("planets")
	gravity_sources.append_array(planets)

func update_forces(delta):
	forces.clear()
	
	# Apply gravitational forces from planets and other gravity sources
	if affected_by_gravity:
		for source in gravity_sources:
			if is_instance_valid(source):
				# Calculate direction to gravity source
				var direction = source.global_position - entity.global_position
				var distance = direction.length()
				
				# Apply inverse square law (F = G * m1 * m2 / r²)
				# G is handled in the gravity_strength property of the source
				if distance > 10:  # Avoid division by very small numbers
					var force_magnitude = source.gravity_strength * mass / (distance * distance)
					var force = direction.normalized() * force_magnitude
					forces.append(force)

func apply_forces(delta):
	# Reset acceleration
	acceleration = Vector2.ZERO
	
	# Sum up all forces (F = ma, so a = F/m)
	for force in forces:
		acceleration += force / mass
	
	# Apply acceleration to velocity
	velocity += acceleration * delta
	
	# Clamp velocity to maximum
	if velocity.length() > max_velocity:
		velocity = velocity.normalized() * max_velocity

func apply_impulse(impulse: Vector2):
	# Apply an instantaneous force (changes velocity directly)
	velocity += impulse / mass

func check_collisions():
	# This would be expanded based on your collision system
	# For now, just check other physics objects
	var physics_objects = get_tree().get_nodes_in_group("physics_objects")
	
	for obj in physics_objects:
		if obj != entity and is_instance_valid(obj):
			var obj_physics = obj.get_node_or_null("PhysicsComponent")
			if obj_physics:
				# Simple circle-based collision detection
				var distance = entity.global_position.distance_to(obj.global_position)
				var combined_radius = get_collision_radius() + obj_physics.get_collision_radius()
				
				if distance < combined_radius:
					# Calculate collision response
					handle_collision(obj, obj_physics)

func handle_collision(other_obj, other_physics):
	# Basic elastic collision response
	var direction = (entity.global_position - other_obj.global_position).normalized()
	
	# Exchange momentum (simplified)
	var temp_velocity = velocity
	velocity = velocity.bounce(direction) * bounce_factor
	other_physics.velocity = other_physics.velocity.bounce(-direction) * other_physics.bounce_factor
	
	# Move objects apart to prevent sticking
	entity.global_position += direction * 5
	
	# Emit collision signal
	emit_signal("collision_occurred", other_obj, entity.global_position)

func get_collision_radius() -> float:
	# Default collision radius from sprite
	var sprite = entity.get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		return max(texture_size.x, texture_size.y) * sprite.scale.x / 2
	
	# Fallback
	return 20.0
