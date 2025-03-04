# missile.gd
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
	z_index = 9
	life_timer = lifetime
	add_to_group("missiles")
	previous_position = global_position
	_create_trail_particles()

func _process(delta):
	life_timer -= delta
	if life_timer <= 0:
		explode()
		return
	
	previous_position = global_position
	
	if target and is_instance_valid(target):
		_update_tracking(delta)
	
	position += direction * speed * delta
	distance_traveled += global_position.distance_to(previous_position)
	
	if distance_traveled >= range:
		explode()
		return
	
	rotation = direction.angle()
	queue_redraw()

func _update_tracking(delta):
	var to_target = target.global_position - global_position
	var distance = to_target.length()
	
	var max_angle = min(turn_speed * delta, PI/2)
	var target_direction = to_target.normalized()
	
	var current_angle = direction.angle()
	var target_angle = target_direction.angle()
	
	var angle_diff = fmod((target_angle - current_angle + PI), TAU) - PI
	angle_diff = clamp(angle_diff, -max_angle, max_angle)
	
	direction = direction.rotated(angle_diff)
	
	var proximity_factor = clamp(1.0 - (distance / range), 0.0, 1.0)
	speed = 400 + (proximity_factor * tracking_strength * 100)

func _create_trail_particles():
	trail_particles = CPUParticles2D.new()
	trail_particles.name = "TrailParticles"
	trail_particles.z_index = -1
	
	trail_particles.amount = 20
	trail_particles.lifetime = 0.4
	trail_particles.local_coords = false
	trail_particles.direction = Vector2(-1, 0)
	trail_particles.spread = 20.0
	trail_particles.gravity = Vector2.ZERO
	trail_particles.initial_velocity = 50.0
	trail_particles.scale_amount = 2.0
	trail_particles.scale_amount_random = 1.0
	trail_particles.color = Color(1.0, 0.5, 0.0, 0.8) if is_player_missile else Color(1.0, 0.2, 0.0, 0.8)
	trail_particles.color_ramp = _create_color_ramp()
	
	add_child(trail_particles)

func _create_color_ramp():
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1, 1, 0.5, 0.8))
	gradient.add_point(0.5, Color(1, 0.5, 0, 0.4))
	gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0))
	
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	
	return ramp

func explode():
	_create_explosion()
	_apply_explosion_damage()
	queue_free()

func _create_explosion():
	var explosion = CPUParticles2D.new()
	explosion.position = global_position
	explosion.z_index = 20
	explosion.emitting = true
	explosion.one_shot = true
	explosion.explosiveness = 1.0
	explosion.amount = 40
	explosion.lifetime = 0.6
	explosion.local_coords = false
	explosion.direction = Vector2.ZERO
	explosion.spread = 180.0
	explosion.gravity = Vector2.ZERO
	explosion.initial_velocity = 150.0
	explosion.initial_velocity_random = 0.5
	explosion.scale_amount = 3.0
	explosion.scale_amount_random = 1.0
	explosion.color = Color(1.0, 0.8, 0.2) if is_player_missile else Color(1.0, 0.3, 0.1)
	explosion.color_ramp = _create_color_ramp()
	
	get_tree().current_scene.add_child(explosion)
	
	var timer = Timer.new()
	explosion.add_child(timer)
	timer.wait_time = 1.0
	timer.one_shot = true
	timer.start()
	timer.timeout.connect(func(): explosion.queue_free())

func _apply_explosion_damage():
	var entities = []
	entities.append_array(get_tree().get_nodes_in_group("enemies"))
	entities.append_array(get_tree().get_nodes_in_group("player"))
	entities.append_array(get_tree().get_nodes_in_group("asteroids"))
	
	for entity in entities:
		if !is_instance_valid(entity):
			continue
			
		if is_player_missile and entity.is_in_group("player"):
			continue
			
		if !is_player_missile and entity.is_in_group("enemies"):
			continue
			
		var distance = global_position.distance_to(entity.global_position)
		if distance <= explosion_radius:
			var damage_factor = 1.0 - (distance / explosion_radius)
			var actual_damage = damage * damage_factor
			
			if entity.has_method("take_damage"):
				entity.take_damage(actual_damage)

func hit_target():
	explode()

func _draw():
	if has_node("Sprite2D"):
		return
		
	var color = Color(0.2, 0.8, 1.0) if is_player_missile else Color(1.0, 0.3, 0.2)
	draw_rect(Rect2(-10, -3, 20, 6), color)
