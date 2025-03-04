# physics_component.gd
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
	update_gravity_sources()

func _physics_process(delta):
	update_forces(delta)
	apply_forces(delta)
	
	entity.global_position += velocity * delta
	velocity = velocity.lerp(Vector2.ZERO, drag * delta)
	
	check_collisions()

func update_gravity_sources():
	gravity_sources.clear()
	gravity_sources.append_array(get_tree().get_nodes_in_group("planets"))

func update_forces(delta):
	forces.clear()
	
	if not affected_by_gravity:
		return
		
	for source in gravity_sources:
		if not is_instance_valid(source):
			continue
			
		var direction = source.global_position - entity.global_position
		var distance = direction.length()
		
		if distance <= 10:
			continue
			
		var force_magnitude = source.gravity_strength * mass / (distance * distance)
		forces.append(direction.normalized() * force_magnitude)

func apply_forces(delta):
	acceleration = Vector2.ZERO
	
	for force in forces:
		acceleration += force / mass
	
	velocity += acceleration * delta
	
	if velocity.length() > max_velocity:
		velocity = velocity.normalized() * max_velocity

func apply_impulse(impulse: Vector2):
	velocity += impulse / mass

func check_collisions():
	var physics_objects = get_tree().get_nodes_in_group("physics_objects")
	
	for obj in physics_objects:
		if obj == entity or not is_instance_valid(obj):
			continue
			
		var obj_physics = obj.get_node_or_null("PhysicsComponent")
		if not obj_physics:
			continue
			
		var distance = entity.global_position.distance_to(obj.global_position)
		var combined_radius = get_collision_radius() + obj_physics.get_collision_radius()
		
		if distance < combined_radius:
			handle_collision(obj, obj_physics)

func handle_collision(other_obj, other_physics):
	var direction = (entity.global_position - other_obj.global_position).normalized()
	
	velocity = velocity.bounce(direction) * bounce_factor
	other_physics.velocity = other_physics.velocity.bounce(-direction) * other_physics.bounce_factor
	
	entity.global_position += direction * 5
	
	emit_signal("collision_occurred", other_obj, entity.global_position)

func get_collision_radius() -> float:
	var sprite = entity.get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		return max(texture_size.x, texture_size.y) * sprite.scale.x / 2
	
	return 20.0
