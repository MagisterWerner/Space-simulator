# scripts/projectiles/missile_projectile.gd
extends "res://scripts/entities/projectile.gd"
class_name MissileProjectile

# Missile properties
@export var acceleration: float = 150.0
@export var max_speed: float = 500.0
@export var turn_rate: float = 2.0
@export var smoke_trail: bool = true
@export var explosion_radius: float = 100.0
@export var explosion_damage: float = 30.0
@export var explosion_knockback: float = 300.0

# Targeting properties
@export var homing_enabled: bool = true
@export var lead_target: bool = true
@export var lead_factor: float = 1.5
@export var max_distance_to_target: float = 1500.0

# Internal state
var target: Node2D = null
var current_speed: float = 0.0
var exploded: bool = false
var _target_last_position: Vector2 = Vector2.ZERO
var _target_velocity: Vector2 = Vector2.ZERO
var _target_update_timer: float = 0.0
var _smoke_timer: float = 0.0
var _smoke_interval: float = 0.05
var _initial_acceleration_time: float = 0.5
var _initial_acceleration_timer: float = 0.0
var _engine_particles: GPUParticles2D = null
var _smoke_trail_points: Array = []

# Cached references
var _audio_manager = null
var _sprite: Sprite2D = null

func _ready() -> void:
	super._ready()
	
	# Setup components
	_setup_components()
	
	# Get engine particles
	_engine_particles = get_node_or_null("EngineParticles")
	
	# Store initial speed
	current_speed = speed
	
	# Connect signals
	body_entered.connect(_on_missile_hit_body)
	
	# Get audio manager
	if Engine.has_singleton("AudioManager"):
		_audio_manager = Engine.get_singleton("AudioManager")
	
	# Play rocket sound
	if _audio_manager and _audio_manager.has_method("play_sfx"):
		_audio_manager.play_sfx("missile_launch", global_position, randf_range(0.9, 1.1))

func _setup_components() -> void:
	# Cache sprite reference
	_sprite = get_node_or_null("Sprite2D")
	
	# Setup smoke trail
	if smoke_trail:
		_setup_smoke_trail()

func _setup_smoke_trail() -> void:
	# We'll create smoke particles at points along the missile's path
	_smoke_trail_points.clear()

func _process(delta: float) -> void:
	if exploded:
		return
	
	# Update timers
	_update_timers(delta)
	
	# Update target tracking
	_update_target_tracking(delta)
	
	# Handle missile movement
	_update_missile_movement(delta)
	
	# Handle smoke trail
	if smoke_trail:
		_update_smoke_trail(delta)
	
	# Update position using velocity from parent class
	position += velocity * delta

func _update_timers(delta: float) -> void:
	_smoke_timer += delta
	
	# Initial acceleration phase
	if _initial_acceleration_timer < _initial_acceleration_time:
		_initial_acceleration_timer += delta

func _update_target_tracking(delta: float) -> void:
	# Skip if no target or homing disabled
	if not target or not homing_enabled or not is_instance_valid(target):
		return
	
	# Check if target is still in range
	if global_position.distance_to(target.global_position) > max_distance_to_target:
		target = null
		return
	
	# Calculate target velocity (used for leading the target)
	_target_update_timer += delta
	if _target_update_timer >= 0.1:
		# Update every 0.1 seconds
		_target_update_timer = 0.0
		
		if _target_last_position != Vector2.ZERO:
			_target_velocity = (target.global_position - _target_last_position) / 0.1
		
		_target_last_position = target.global_position

func _update_missile_movement(delta: float) -> void:
	# Accelerate missile
	if _initial_acceleration_timer < _initial_acceleration_time:
		# Slower acceleration at the start
		current_speed += acceleration * delta * 0.5
	else:
		current_speed += acceleration * delta
	
	current_speed = min(current_speed, max_speed)
	
	if target and homing_enabled and is_instance_valid(target):
		# Calculate direction to target
		var target_pos = target.global_position
		
		# Lead target if enabled
		if lead_target and _target_velocity != Vector2.ZERO:
			var dist_to_target = global_position.distance_to(target_pos)
			var time_to_impact = dist_to_target / current_speed
			target_pos += _target_velocity * time_to_impact * lead_factor
		
		var direction_to_target = global_position.direction_to(target_pos)
		var current_direction = Vector2(cos(rotation), sin(rotation))
		
		# Calculate the angle to turn
		var angle_to_target = current_direction.angle_to(direction_to_target)
		
		# Apply turn rate limit
		var max_turn = turn_rate * delta
		angle_to_target = clamp(angle_to_target, -max_turn, max_turn)
		
		# Rotate missile
		rotation += angle_to_target
	
	# Update velocity based on current rotation and speed
	velocity = Vector2(current_speed, 0).rotated(rotation)

func _update_smoke_trail(delta: float) -> void:
	if _smoke_timer >= _smoke_interval:
		_smoke_timer = 0.0
		_emit_smoke_particle()

# Create a smoke particle at current position
func _emit_smoke_particle() -> void:
	var smoke = GPUParticles2D.new()
	smoke.global_position = global_position
	smoke.emitting = true
	smoke.one_shot = true
	smoke.explosiveness = 1.0
	smoke.amount = 1
	smoke.lifetime = 1.0
	smoke.process_material = _create_smoke_material()
	get_tree().current_scene.add_child(smoke)
	
	# Auto-remove after lifetime
	var timer = Timer.new()
	timer.wait_time = 1.2
	timer.one_shot = true
	timer.timeout.connect(func(): smoke.queue_free())
	smoke.add_child(timer)
	timer.start()

# Create smoke particle material
func _create_smoke_material() -> ParticleProcessMaterial:
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	material.direction = Vector3(-1, 0, 0)  # Opposite to missile direction
	material.spread = 15.0
	material.gravity = Vector3(0, 0, 0)
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 15.0
	material.scale_min = 5.0
	material.scale_max = 10.0
	material.color = Color(0.7, 0.7, 0.7, 0.7)
	material.color_ramp = _create_smoke_gradient()
	return material

# Create color gradient for smoke
func _create_smoke_gradient() -> Gradient:
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.7, 0.7, 0.7, 0.7))
	gradient.add_point(0.5, Color(0.5, 0.5, 0.5, 0.4))
	gradient.add_point(1.0, Color(0.2, 0.2, 0.2, 0.0))
	return gradient

# Handle missile hit
func _on_missile_hit_body(body: Node2D) -> void:
	if body == shooter or exploded:
		return
	
	explode()

# Explode the missile
func explode() -> void:
	if exploded:
		return
		
	exploded = true
	
	# Apply area damage
	_apply_area_damage()
	
	# Create explosion effect
	_create_explosion_effect()
	
	# Play explosion sound
	if _audio_manager and _audio_manager.has_method("play_sfx"):
		_audio_manager.play_sfx("explosion", global_position, randf_range(0.9, 1.1))
	
	# Hide missile graphics
	if _sprite:
		_sprite.visible = false
	
	if _engine_particles:
		_engine_particles.emitting = false
	
	# Don't destroy immediately, allow explosion effect to play
	set_deferred("monitorable", false)
	set_deferred("monitoring", false)
	
	# Remove after explosion finishes
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = 1.0
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	timer.start()

# Apply area damage to all bodies in explosion radius
func _apply_area_damage() -> void:
	var space_state = get_world_2d().direct_space_state
	var query = PhysicsShapeQueryParameters2D.new()
	
	var shape = CircleShape2D.new()
	shape.radius = explosion_radius
	
	query.shape = shape
	query.transform = Transform2D(0, global_position)
	query.collision_mask = collision_mask
	query.exclude = [self]
	if shooter:
		query.exclude.append(shooter)
	
	var results = space_state.intersect_shape(query)
	
	for result in results:
		var collider = result.collider
		
		if collider == shooter:
			continue
		
		# Calculate damage based on distance from explosion center
		var distance = global_position.distance_to(collider.global_position)
		var damage_factor = 1.0 - min(1.0, distance / explosion_radius)
		var damage_amount = explosion_damage * damage_factor
		
		# Apply damage if health component exists
		if collider.has_node("HealthComponent"):
			var health = collider.get_node("HealthComponent")
			if health is HealthComponent:
				health.apply_damage(damage_amount, "explosion", shooter)
		
		# Apply knockback if it's a physics body
		if collider is RigidBody2D:
			var knockback_direction = (collider.global_position - global_position).normalized()
			var knockback_force = knockback_direction * explosion_knockback * damage_factor
			collider.apply_central_impulse(knockback_force)

# Create explosion visual effect
func _create_explosion_effect() -> void:
	var explosion = Node2D.new()
	explosion.name = "Explosion"
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	
	# Add particles
	var particles = GPUParticles2D.new()
	particles.name = "ExplosionParticles"
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 50
	particles.lifetime = 0.8
	particles.process_material = _create_explosion_material()
	explosion.add_child(particles)
	
	# Add light
	var light = PointLight2D.new()
	light.name = "ExplosionLight"
	light.color = Color(1.0, 0.7, 0.2)
	light.energy = 2.0
	light.texture = _create_light_texture()
	light.texture_scale = 4.0
	explosion.add_child(light)
	
	# Animate the light
	var tween = light.create_tween()
	tween.tween_property(light, "energy", 0.0, 0.5)
	tween.parallel().tween_property(light, "texture_scale", 1.0, 0.5)
	
	# Remove explosion after it finishes
	var timer = Timer.new()
	explosion.add_child(timer)
	timer.wait_time = 1.0
	timer.one_shot = true
	timer.timeout.connect(func(): explosion.queue_free())
	timer.start()

# Create explosion particle material
func _create_explosion_material() -> ParticleProcessMaterial:
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	material.emission_sphere_radius = 10.0
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.gravity = Vector3(0, 0, 0)
	material.initial_velocity_min = 100.0
	material.initial_velocity_max = 200.0
	material.damping_min = 150.0
	material.damping_max = 200.0
	material.scale_min = 5.0
	material.scale_max = 10.0
	material.color = Color(1.0, 0.5, 0.1, 1.0)
	material.color_ramp = _create_explosion_gradient()
	return material

# Create color gradient for explosion
func _create_explosion_gradient() -> Gradient:
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 1.0, 0.3, 1.0))
	gradient.add_point(0.2, Color(1.0, 0.5, 0.1, 1.0))
	gradient.add_point(0.5, Color(0.8, 0.2, 0.1, 0.8))
	gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))
	return gradient

# Create light texture
func _create_light_texture() -> Texture2D:
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 1))
	
	# Create a circular gradient
	for x in range(32):
		for y in range(32):
			var dist = Vector2(x - 16, y - 16).length()
			var alpha = 1.0 - min(1.0, dist / 16.0)
			var color = Color(1, 1, 1, alpha)
			image.set_pixel(x, y, color)
	
	return ImageTexture.create_from_image(image)

# Set target for homing missile
func set_target(new_target: Node2D) -> void:
	target = new_target
	if target:
		_target_last_position = target.global_position

# Set turn rate for homing
func set_turn_rate(rate: float) -> void:
	turn_rate = rate

# Set acceleration
func set_acceleration(accel: float) -> void:
	acceleration = accel

# Set explosion radius
func set_explosion_radius(radius: float) -> void:
	explosion_radius = radius

# Set explosion damage
func set_explosion_damage(dmg: float) -> void:
	explosion_damage = dmg
