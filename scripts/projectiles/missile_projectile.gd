extends RigidBody2D
class_name MissileProjectile

signal missile_exploded(position)
signal target_hit(target, damage)

# Missile properties
@export_category("Missile Properties")
@export var damage: float = 30.0
@export var speed: float = 400.0
@export var max_speed: float = 600.0
@export var acceleration: float = 100.0
@export var turn_rate: float = 3.0
@export var lifetime: float = 5.0
@export var proximity_radius: float = 15.0
@export var explosion_radius: float = 80.0
@export var explosion_damage: float = 20.0
@export var explosion_falloff: bool = true
@export var explosive_force: float = 500.0

@export_category("Appearance")
@export var exhaust_color: Color = Color(1.0, 0.5, 0.0, 0.8)
@export var exhaust_width: float = 2.0
@export var trail_length: int = 15
@export var trail_width: float = 4.0
@export var trail_fade: float = 0.95

@export_category("Homing")
@export var homing: bool = true
@export var target_group: String = "enemies"
@export var acquire_distance: float = 600.0
@export var re_acquire_cooldown: float = 0.5
@export var prediction_factor: float = 0.5

@export_category("Effects")
@export var explosion_scene: PackedScene
@export var explosion_sound: String = "explosion_fire"
@export var launch_sound: String = "missile_launch"

# Runtime properties
var launcher = null
var original_target = null
var current_target = null
var elapsed_time: float = 0.0
var is_exploded: bool = false
var hitbox_layer: int = 1
var hitbox_mask: int = 1
var acquired_targets: Array = []
var re_acquire_timer: float = 0.0
var hit_something: bool = false
var is_active: bool = false

# Audio manager reference (optional)
var _audio_manager = null

# Trail rendering
var _trail_points: Array = []
var _current_exhaust_points: Array = []
var _target_direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	# Initialize physics
	collision_layer = 4  # Projectile layer
	collision_mask = 3   # Hit world and enemies, but not player
	contact_monitor = true
	max_contacts_reported = 4
	gravity_scale = 0.0
	
	# Store original collision settings
	hitbox_layer = collision_layer
	hitbox_mask = collision_mask
	
	# Connect collision signal
	body_entered.connect(_on_body_entered)
	
	# Get audio manager reference
	_audio_manager = get_node_or_null("/root/AudioManager")
	
	# Set up lifetime timer
	var timer = Timer.new()
	timer.wait_time = lifetime
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(_on_lifetime_expired)
	add_child(timer)
	
	# Initialize trail
	for i in range(trail_length):
		_trail_points.append(Vector2.ZERO)
	
	# Initialize exhaust
	_current_exhaust_points = [Vector2.ZERO, Vector2.ZERO]
	
	# Deactivate initially
	is_active = false
	set_physics_process(false)
	
	# Play launch sound
	call_deferred("_play_launch_sound")

func activate() -> void:
	is_active = true
	set_physics_process(true)
	
	# Apply initial velocity
	linear_velocity = transform.x * speed

func _play_launch_sound() -> void:
	if _audio_manager and not launch_sound.is_empty():
		_audio_manager.play_sfx(launch_sound, global_position, 1.0)

func _process(delta: float) -> void:
	# Only render when active
	if is_active:
		queue_redraw()

func _physics_process(delta: float) -> void:
	if is_exploded or not is_active:
		return
	
	elapsed_time += delta
	
	# Update target acquisition
	_update_target(delta)
	
	# Update missile guidance
	_update_guidance(delta)
	
	# Check for proximity detonation
	_check_proximity_detonation()
	
	# Update trail
	_update_trail()

func _update_target(delta: float) -> void:
	# Manage re-acquisition timer
	if re_acquire_timer > 0:
		re_acquire_timer -= delta
	
	# Update target if needed
	if homing and (current_target == null or not is_instance_valid(current_target)) and re_acquire_timer <= 0:
		# Try to acquire original target first
		if original_target and is_instance_valid(original_target):
			current_target = original_target
		else:
			# Try to find a new target
			current_target = _find_nearest_target()
		
		# Reset timer regardless of success
		re_acquire_timer = re_acquire_cooldown

func _update_guidance(delta: float) -> void:
	# Calculate desired direction
	var desired_direction = transform.x
	var target_position = Vector2.ZERO
	
	if homing and current_target and is_instance_valid(current_target):
		# Get current target position
		target_position = current_target.global_position
		
		# Predict target movement if it has velocity
		if "linear_velocity" in current_target:
			var target_velocity = current_target.linear_velocity
			var distance = global_position.distance_to(target_position)
			var time_to_target = distance / speed
			target_position += target_velocity * time_to_target * prediction_factor
		
		# Calculate direction to target
		desired_direction = (target_position - global_position).normalized()
	
	# Store for rendering
	_target_direction = desired_direction
	
	# Rotate missile towards desired direction
	var current_direction = transform.x.normalized()
	var angle_diff = current_direction.angle_to(desired_direction)
	
	# Apply limited rotation
	var rotation_amount = sign(angle_diff) * min(abs(angle_diff), turn_rate * delta)
	rotate(rotation_amount)
	
	# Apply forward acceleration
	var forward_velocity = transform.x * acceleration * delta
	linear_velocity += forward_velocity
	
	# Clamp to max speed
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

func _check_proximity_detonation() -> void:
	if proximity_radius <= 0 or is_exploded:
		return
	
	# Check all potential targets
	var targets = get_tree().get_nodes_in_group(target_group)
	for target in targets:
		if target and is_instance_valid(target) and target != launcher:
			var distance = global_position.distance_to(target.global_position)
			if distance <= proximity_radius:
				explode()
				return

func _update_trail() -> void:
	# Shift points down the array
	for i in range(trail_length - 1, 0, -1):
		_trail_points[i] = _trail_points[i-1]
	
	# Add current position as newest point
	_trail_points[0] = Vector2.ZERO
	
	# Update exhaust points
	_current_exhaust_points[0] = Vector2(-10, -exhaust_width / 2).rotated(PI)
	_current_exhaust_points[1] = Vector2(-10, exhaust_width / 2).rotated(PI)

func _draw() -> void:
	if not is_active:
		return
	
	# Draw missile trail
	var points = []
	var colors = []
	
	# Create gradient trail
	for i in range(trail_length):
		if _trail_points[i] != Vector2.ZERO:
			var alpha = pow(trail_fade, i)
			var width = trail_width * (1.0 - float(i) / trail_length)
			colors.append(Color(exhaust_color.r, exhaust_color.g, exhaust_color.b, alpha))
			points.append(_trail_points[i])
	
	# Draw trail line
	if points.size() >= 2:
		draw_polyline_colors(points, colors, trail_width, true)
	
	# Draw exhaust flame
	if _current_exhaust_points.size() >= 2:
		draw_colored_polygon(_current_exhaust_points, exhaust_color)

func _on_body_entered(body: Node) -> void:
	if is_exploded or hit_something:
		return
	
	hit_something = true
	
	# Apply damage to target if it has health
	var health_component = null
	if body.has_node("HealthComponent"):
		health_component = body.get_node("HealthComponent")
	elif body.has_method("take_damage"):
		body.take_damage(damage, "explosive", self)
		target_hit.emit(body, damage)
	elif health_component and health_component.has_method("apply_damage"):
		health_component.apply_damage(damage, "explosive", self)
		target_hit.emit(body, damage)
	
	# Always explode on impact
	explode()

func explode() -> void:
	if is_exploded:
		return
	
	is_exploded = true
	set_physics_process(false)
	collision_layer = 0
	collision_mask = 0
	visible = false
	
	# Apply area damage
	if explosion_radius > 0:
		_apply_explosion_damage()
	
	# Spawn explosion effect
	_spawn_explosion_effect()
	
	# Play explosion sound
	if _audio_manager and not explosion_sound.is_empty():
		_audio_manager.play_sfx(explosion_sound, global_position, 1.0)
	
	# Emit signal
	missile_exploded.emit(global_position)
	
	# Queue for deletion with small delay for sound to play
	await get_tree().create_timer(0.1).timeout
	queue_free()

func _apply_explosion_damage() -> void:
	# Get all bodies in explosion radius
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	var shape = CircleShape2D.new()
	shape.radius = explosion_radius
	
	query.shape = shape
	query.transform = global_transform
	query.collision_mask = hitbox_mask
	
	var results = space_state.intersect_shape(query)
	var hit_objects = []
	
	for result in results:
		var collider = result.collider
		if collider and is_instance_valid(collider) and collider != self and not hit_objects.has(collider):
			hit_objects.append(collider)
			
			# Calculate damage based on distance
			var distance = global_position.distance_to(collider.global_position)
			var damage_amount = explosion_damage
			
			if explosion_falloff and distance > 0:
				damage_amount *= 1.0 - min(1.0, distance / explosion_radius)
			
			# Apply damage
			var health_component = null
			if collider.has_node("HealthComponent"):
				health_component = collider.get_node("HealthComponent")
				health_component.apply_damage(damage_amount, "explosive", self)
			elif collider.has_method("take_damage"):
				collider.take_damage(damage_amount, "explosive", self)
			
			# Apply physics impulse for knockback
			if collider is RigidBody2D and explosive_force > 0:
				var dir = (collider.global_position - global_position).normalized()
				var impulse_power = explosive_force * (1.0 - min(1.0, distance / explosion_radius))
				collider.apply_central_impulse(dir * impulse_power)

func _spawn_explosion_effect() -> void:
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		get_tree().current_scene.add_child(explosion)
		explosion.global_position = global_position
		
		# Scale effect based on explosion size
		var scale_factor = explosion_radius / 40.0  # Assuming 40px is the base size
		explosion.scale = Vector2(scale_factor, scale_factor)

func _find_nearest_target() -> Node2D:
	var nearest_target = null
	var nearest_distance = acquire_distance
	
	# Find all potential targets
	var targets = get_tree().get_nodes_in_group(target_group)
	for target in targets:
		if target and is_instance_valid(target) and target != launcher:
			var distance = global_position.distance_to(target.global_position)
			if distance < nearest_distance:
				nearest_distance = distance
				nearest_target = target
	
	return nearest_target

# Set initial target and launcher
func set_target(target: Node2D, source = null) -> void:
	original_target = target
	current_target = target
	launcher = source
	
	# Add target to acquired targets list
	if target and not acquired_targets.has(target):
		acquired_targets.append(target)

func _on_lifetime_expired() -> void:
	explode()
