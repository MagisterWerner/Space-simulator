extends Node2D
class_name HomingMissile

@export var speed = 400.0
@export var damage = 25.0
@export var lifetime = 5.0
@export var is_player_missile = true
@export var tracking_strength = 3.0
@export var turn_speed = 2.0
@export var explosion_radius = 60.0
@export var range = 1200.0

var direction = Vector2.RIGHT
var life_timer = 0.0
var distance_traveled = 0.0
var target = null
var previous_position = null
var trail_particles = null

# Called when the node enters the scene tree for the first time
func _ready():
	# Set properties
	z_index = 9
	life_timer = lifetime
	add_to_group("missiles")
	previous_position = global_position
	
	# Create trail particles
	_create_trail_particles()

# Called every frame
func _process(delta):
	# Update lifetime
	life_timer -= delta
	if life_timer <= 0:
		explode()
		return
	
	# Get previous position for distance calculation
	previous_position = global_position
	
	# Update target tracking
	_update_target()
	if target and is_instance_valid(target):
		_update_tracking(delta)
	
	# Move in the current direction
	position += direction * speed * delta
	
	# Calculate distance traveled
	distance_traveled += global_position.distance_to(previous_position)
	
	# Check if we've exceeded range
	if distance_traveled >= range:
		explode()
		return
	
	# Update rotation to match direction
	rotation = direction.angle()
	
	# Check for collisions
	_check_collisions()

func _update_target():
	# If we don't have a target or it's no longer valid, find a new one
	if !target or !is_instance_valid(target) or !target.visible:
		target = _find_closest_target()

func _find_closest_target():
	var target_groups = ["enemies", "asteroids"]
	if !is_player_missile:
		target_groups = ["player"]
	
	var closest_target = null
	var closest_distance = INF
	
	for group in target_groups:
		var potential_targets = get_tree().get_nodes_in_group(group)
		for potential_target in potential_targets:
			if is_instance_valid(potential_target) and potential_target.visible:
				var distance = global_position.distance_to(potential_target.global_position)
				if distance < closest_distance:
					closest_target = potential_target
					closest_distance = distance
	
	return closest_target

func _update_tracking(delta):
	# Calculate direction to target
	var to_target = target.global_position - global_position
	var distance = to_target.length()
	
	# Don't turn too sharply when already close
	var max_angle = min(turn_speed * delta, PI/2)
	
	# Calculate desired direction
	var target_direction = to_target.normalized()
	
	# Get current angle and target angle
	var current_angle = direction.angle()
	var target_angle = target_direction.angle()
	
	# Calculate the angle difference (accounting for wrapping)
	var angle_diff = fmod((target_angle - current_angle + PI), TAU) - PI
	
	# Limit the turn rate
	angle_diff = clamp(angle_diff, -max_angle, max_angle)
	
	# Apply the rotation
	direction = direction.rotated(angle_diff)
	
	# Increase speed when getting closer to target
	var proximity_factor = clamp(1.0 - (distance / range), 0.0, 1.0)
	speed = 400 + (proximity_factor * tracking_strength * 100)

func _check_collisions():
	# Check collision with entities based on missile ownership
	var collision_groups = ["enemies", "asteroids"] if is_player_missile else ["player"]
	
	for group in collision_groups:
		var entities = get_tree().get_nodes_in_group(group)
		for entity in entities:
			if is_instance_valid(entity) and entity.visible:
				if _is_colliding_with(entity):
					explode(entity)
					return

func _is_colliding_with(entity) -> bool:
	# Get entity collision rectangle
	var entity_rect
	if entity.has_method("get_collision_rect"):
		entity_rect = entity.get_collision_rect()
		# Convert rect to global coordinates
		entity_rect.position += entity.global_position
	else:
		# Fallback collision rect
		var size = 30
		entity_rect = Rect2(entity.global_position - Vector2(size/2, size/2), Vector2(size, size))
	
	# Get missile collision rectangle
	var missile_rect = get_collision_rect()
	
	# Check for intersection
	return entity_rect.intersects(missile_rect)

func get_collision_rect() -> Rect2:
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		var scaled_size = texture_size * sprite.scale
		return Rect2(global_position - scaled_size/2, scaled_size)
	else:
		# Fallback collision rect
		return Rect2(global_position - Vector2(10, 5), Vector2(20, 10))

func _create_trail_particles():
	# Add particles node for the trail
	trail_particles = CPUParticles2D.new()
	trail_particles.name = "TrailParticles"
	trail_particles.z_index = -1  # Behind missile
	trail_particles.position = Vector2(-10, 0)  # Emit from back of missile
	
	# Configure the particles
	trail_particles.amount = 20
	trail_particles.lifetime = 0.4
	trail_particles.explosiveness = 0.0
	trail_particles.local_coords = false
	trail_particles.direction = Vector2(-1, 0)  # Emit backward
	trail_particles.spread = 20.0
	trail_particles.gravity = Vector2(0, 0)
	trail_particles.initial_velocity_min = 40.0
	trail_particles.initial_velocity_max = 60.0
	trail_particles.scale_amount_min = 1.5
	trail_particles.scale_amount_max = 2.5
	trail_particles.color = Color(1.0, 0.5, 0.0, 0.8) if is_player_missile else Color(1.0, 0.2, 0.0, 0.8)
	
	# Add color ramp for fade-out effect
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 0.5, 0.8))
	gradient.add_point(0.5, Color(1, 0.5, 0, 0.4))
	gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0))
	
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	trail_particles.color_ramp = ramp
	
	add_child(trail_particles)

func explode(direct_hit_entity = null):
	# Apply direct damage to the hit entity
	if direct_hit_entity and direct_hit_entity.has_method("take_damage"):
		direct_hit_entity.take_damage(damage)
	
	# Apply area damage to all entities within explosion radius
	_apply_explosion_damage()
	
	# Create explosion visual effect
	_create_explosion_effect()
	
	# Remove the missile
	queue_free()

func _apply_explosion_damage():
	# Get all entities that can take damage
	var entities = []
	if is_player_missile:
		entities.append_array(get_tree().get_nodes_in_group("enemies"))
		entities.append_array(get_tree().get_nodes_in_group("asteroids"))
	else:
		entities.append_array(get_tree().get_nodes_in_group("player"))
	
	# Apply damage to entities within explosion radius
	for entity in entities:
		if is_instance_valid(entity) and entity.visible:
			var distance = global_position.distance_to(entity.global_position)
			if distance <= explosion_radius:
				# Calculate damage falloff based on distance
				var damage_factor = 1.0 - (distance / explosion_radius)
				var actual_damage = damage * damage_factor
				
				# Apply damage
				if entity.has_method("take_damage"):
					entity.take_damage(actual_damage)

func _create_explosion_effect():
	# Check if explosion effect scene exists
	var explosion_scene_path = "res://scenes/explosion_effect.tscn"
	if ResourceLoader.exists(explosion_scene_path):
		var explosion_scene = load(explosion_scene_path)
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().current_scene.add_child(explosion)
	else:
		# Fallback: Create basic explosion particles if scene doesn't exist
		var explosion = CPUParticles2D.new()
		explosion.position = global_position
		explosion.z_index = 20
		explosion.emitting = true
		explosion.one_shot = true
		explosion.explosiveness = 1.0
		explosion.amount = 40
		explosion.lifetime = 0.6
		explosion.local_coords = false
		explosion.direction = Vector2(0, 0)
		explosion.spread = 180.0
		explosion.gravity = Vector2(0, 0)
		explosion.initial_velocity_min = 120.0
		explosion.initial_velocity_max = 180.0
		explosion.scale_amount_min = 2.0
		explosion.scale_amount_max = 4.0
		explosion.color = Color(1.0, 0.8, 0.2) if is_player_missile else Color(1.0, 0.3, 0.1)
		
		# Create color gradient for particles
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(1, 1, 0.5, 1.0))
		gradient.add_point(0.5, Color(1, 0.3, 0, 0.8))
		gradient.add_point(1.0, Color(0.3, 0.1, 0.1, 0))
		
		var ramp = GradientTexture1D.new()
		ramp.gradient = gradient
		explosion.color_ramp = ramp
		
		# Add to the scene
		get_tree().current_scene.add_child(explosion)
		
		# Remove after animation completes
		var timer = Timer.new()
		explosion.add_child(timer)
		timer.wait_time = 1.0
		timer.one_shot = true
		timer.start()
		timer.timeout.connect(func(): explosion.queue_free())

func _draw():
	# Draw missile if no sprite is attached
	if not has_node("Sprite2D"):
		var color = Color(0.2, 0.8, 1.0) if is_player_missile else Color(1.0, 0.3, 0.2)
		
		# Draw missile body
		draw_rect(Rect2(-10, -3, 20, 6), color)
		
		# Draw missile tip
		var points = PackedVector2Array([
			Vector2(10, 0),
			Vector2(5, -5),
			Vector2(5, 5)
		])
		draw_colored_polygon(points, color.lightened(0.2))
