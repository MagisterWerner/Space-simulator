class_name Missile
extends Node2D

@export var speed = 400
@export var damage = 25
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

func _ready():
	# Set properties
	z_index = 9
	life_timer = lifetime
	add_to_group("missiles")
	previous_position = global_position
	
	# Create trail particles
	_create_trail_particles()

func _process(delta):
	# Update lifetime
	life_timer -= delta
	if life_timer <= 0:
		explode()
		return
	
	# Get previous position for distance calculation
	previous_position = global_position
	
	# Update target tracking
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
	
	queue_redraw()

func _draw():
	# This is a fallback in case the Sprite2D child isn't present
	if not has_node("Sprite2D"):
		var color = Color(0.2, 0.8, 1.0) if is_player_missile else Color(1.0, 0.3, 0.2)
		draw_rect(Rect2(-10, -3, 20, 6), color)

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

func _create_trail_particles():
	# Add particles node for the trail
	trail_particles = CPUParticles2D.new()
	trail_particles.name = "TrailParticles"
	trail_particles.z_index = -1  # Behind missile
	
	# Configure the particles
	trail_particles.amount = 20
	trail_particles.lifetime = 0.4
	trail_particles.explosiveness = 0.0
	trail_particles.local_coords = false
	trail_particles.direction = Vector2(-1, 0)  # Emit backward
	trail_particles.spread = 20.0
	trail_particles.gravity = Vector2(0, 0)
	trail_particles.initial_velocity = 50.0
	trail_particles.scale_amount = 2.0
	trail_particles.scale_amount_random = 1.0
	trail_particles.color = Color(1.0, 0.5, 0.0, 0.8) if is_player_missile else Color(1.0, 0.2, 0.0, 0.8)
	trail_particles.color_ramp = _create_color_ramp()
	
	add_child(trail_particles)

func _create_color_ramp():
	# Create a color ramp for the particles
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 0.5, 0.8))
	gradient.add_point(0.5, Color(1, 0.5, 0, 0.4))
	gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0))
	
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	
	return ramp

func explode():
	# Create explosion effect
	_create_explosion()
	
	# Apply damage to entities in explosion radius
	_apply_explosion_damage()
	
	# Remove the missile
	queue_free()

func _create_explosion():
	# Create explosion particles
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
	explosion.initial_velocity = 150.0
	explosion.initial_velocity_random = 0.5
	explosion.scale_amount = 3.0
	explosion.scale_amount_random = 1.0
	explosion.color = Color(1.0, 0.8, 0.2) if is_player_missile else Color(1.0, 0.3, 0.1)
	explosion.color_ramp = _create_color_ramp()
	
	# Add to the scene
	get_tree().current_scene.add_child(explosion)
	
	# Remove after animation completes
	var timer = Timer.new()
	explosion.add_child(timer)
	timer.wait_time = 1.0
	timer.one_shot = true
	timer.start()
	timer.timeout.connect(func(): explosion.queue_free())

func _apply_explosion_damage():
	# Get all entities that can take damage
	var entities = []
	entities.append_array(get_tree().get_nodes_in_group("enemies"))
	entities.append_array(get_tree().get_nodes_in_group("player"))
	entities.append_array(get_tree().get_nodes_in_group("asteroids"))
	
	# Apply damage to entities within explosion radius
	for entity in entities:
		if is_instance_valid(entity):
			# Skip if this is a friendly projectile and entity is the player
			if is_player_missile and entity.is_in_group("player"):
				continue
				
			# Skip if this is an enemy projectile and entity is an enemy
			if !is_player_missile and entity.is_in_group("enemies"):
				continue
				
			# Check distance to entity
			var distance = global_position.distance_to(entity.global_position)
			if distance <= explosion_radius:
				# Calculate damage falloff based on distance
				var damage_factor = 1.0 - (distance / explosion_radius)
				var actual_damage = damage * damage_factor
				
				# Apply damage
				if entity.has_method("take_damage"):
					entity.take_damage(actual_damage)

func hit_target():
	explode()
