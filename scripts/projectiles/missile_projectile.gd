# scripts/projectiles/missile_projectile.gd
extends Area2D
class_name MissileProjectile

signal hit_target(target)

# Core properties
@export var speed: float = 300.0
@export var damage: float = 50.0
@export var lifespan: float = 5.0

# Missile properties
@export var acceleration: float = 20.0
@export var max_speed: float = 600.0
@export var explosion_radius: float = 100.0
@export var explosion_damage: float = 30.0
@export var explosion_knockback: float = 200.0
@export var smoke_trail: bool = true

# Internal state
var velocity: Vector2 = Vector2.ZERO
var current_speed: float = 0.0
var lifetime: float = 0.0
var shooter: Node = null
var exploded: bool = false

# Timers
var _smoke_timer: float = 0.0
var _smoke_interval: float = 0.05

# Cached references
var _sprite: Sprite2D = null
var _engine_particles: CPUParticles2D = null
var _collision_shape: CollisionShape2D = null
var _audio_manager = null

func _ready() -> void:
	# Set up collision properties
	collision_layer = 8   # Projectile layer
	collision_mask = 5    # Asteroid/enemy layers
	
	# Get node references
	_sprite = get_node_or_null("Sprite2D")
	_engine_particles = get_node_or_null("EngineParticles")
	_collision_shape = get_node_or_null("CollisionShape2D")
	
	# Initialize velocity
	current_speed = speed
	velocity = Vector2(current_speed, 0).rotated(rotation)
	
	# Connect signals
	body_entered.connect(_on_body_entered)
	
	# Get audio manager
	if Engine.has_singleton("AudioManager"):
		_audio_manager = Engine.get_singleton("AudioManager")
		
		# Play launch sound
		if _audio_manager.has_method("play_sfx"):
			_audio_manager.play_sfx("missile_launch", global_position, randf_range(0.9, 1.1))

func _process(delta: float) -> void:
	if exploded:
		return
	
	# Update missile
	_update_missile(delta)
	
	# Handle smoke trail
	if smoke_trail:
		_update_smoke_trail(delta)
	
	# Update lifetime
	lifetime += delta
	if lifetime >= lifespan:
		explode()

func _physics_process(delta: float) -> void:
	if exploded:
		return
		
	# Apply position change based on velocity
	position += velocity * delta

func _update_missile(delta: float) -> void:
	# Accelerate missile
	current_speed = min(current_speed + acceleration * delta, max_speed)
	
	# Update velocity based on current rotation and speed
	velocity = Vector2(current_speed, 0).rotated(rotation)
	
	# Update engine particles if they exist
	if _engine_particles and not _engine_particles.emitting:
		_engine_particles.emitting = true

func _update_smoke_trail(delta: float) -> void:
	_smoke_timer += delta
	
	if _smoke_timer >= _smoke_interval:
		_smoke_timer = 0.0
		_emit_smoke_particle()

# Create a smoke particle at current position
func _emit_smoke_particle() -> void:
	var smoke = CPUParticles2D.new()
	smoke.global_position = global_position
	smoke.emitting = true
	smoke.one_shot = true
	smoke.explosiveness = 1.0
	smoke.amount = 1
	smoke.lifetime = 0.8
	
	# Configure particle properties
	smoke.direction = Vector2(-1, 0)  # Opposite to missile direction
	smoke.spread = 15.0
	smoke.gravity = Vector2.ZERO
	smoke.initial_velocity_min = 5.0
	smoke.initial_velocity_max = 10.0
	smoke.scale_amount_min = 2.0
	smoke.scale_amount_max = 4.0
	
	# Create gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(0.7, 0.7, 0.7, 0.7))
	gradient.add_point(0.5, Color(0.5, 0.5, 0.5, 0.4))
	gradient.add_point(1.0, Color(0.2, 0.2, 0.2, 0.0))
	smoke.color_ramp = gradient
	
	get_tree().current_scene.add_child(smoke)
	
	# Auto-remove after lifetime
	get_tree().create_timer(1.0).timeout.connect(func():
		if is_instance_valid(smoke):
			smoke.queue_free()
	)

# Handle missile hit
func _on_body_entered(body: Node2D) -> void:
	if body == shooter or exploded:
		return
	
	hit_target.emit(body)
	explode()

# Explode the missile
func explode() -> void:
	if exploded:
		return
		
	exploded = true
	
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
	
	# Disable collision
	if _collision_shape:
		_collision_shape.set_deferred("disabled", true)
	
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)
	
	# Apply area damage (after we've disabled our own collision)
	call_deferred("_apply_area_damage")
	
	# Remove after explosion finishes
	get_tree().create_timer(0.8).timeout.connect(queue_free)

# Apply area damage to all bodies in explosion radius
func _apply_area_damage() -> void:
	# Create a temporary Area2D for explosion radius detection
	var explosion_area = Area2D.new()
	explosion_area.collision_layer = 0
	explosion_area.collision_mask = collision_mask
	
	# Create collision shape
	var collision_shape = CollisionShape2D.new()
	var shape = CircleShape2D.new()
	shape.radius = explosion_radius
	collision_shape.shape = shape
	
	# Add to scene temporarily
	explosion_area.add_child(collision_shape)
	get_tree().current_scene.add_child(explosion_area)
	explosion_area.global_position = global_position
	
	# Wait one physics frame to ensure collision detection works
	await get_tree().physics_frame
	
	# Get overlapping bodies
	var bodies = explosion_area.get_overlapping_bodies()
	
	# Apply damage to each body
	for body in bodies:
		if body == shooter:
			continue
		
		# Calculate damage based on distance from explosion center
		var distance = global_position.distance_to(body.global_position)
		var damage_factor = 1.0 - min(1.0, distance / explosion_radius)
		var damage_amount = explosion_damage * damage_factor
		
		# Apply damage
		if body.has_node("HealthComponent"):
			var health = body.get_node("HealthComponent")
			if health and health.has_method("apply_damage"):
				health.apply_damage(damage_amount, "explosion", shooter)
		elif body.has_method("take_damage"):
			body.take_damage(damage_amount, shooter)
		
		# Apply knockback to physics bodies
		if body is RigidBody2D:
			var knockback_direction = (body.global_position - global_position).normalized()
			var knockback_force = knockback_direction * explosion_knockback * damage_factor
			body.apply_central_impulse(knockback_force)
	
	# Clean up
	explosion_area.queue_free()

# Create explosion visual effect
func _create_explosion_effect() -> void:
	# Create parent node for explosion effects
	var explosion = Node2D.new()
	explosion.name = "ExplosionEffect"
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = global_position
	
	# Create explosion particles
	var particles = CPUParticles2D.new()
	explosion.add_child(particles)
	
	# Configure particle properties
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = 30
	particles.lifetime = 0.6
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 30.0
	particles.initial_velocity_max = 80.0
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 6.0
	
	# Create gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.9, 0.3, 1.0))
	gradient.add_point(0.2, Color(1.0, 0.5, 0.1, 1.0))
	gradient.add_point(0.6, Color(0.6, 0.2, 0.1, 0.6))
	gradient.add_point(1.0, Color(0.2, 0.1, 0.1, 0.0))
	particles.color_ramp = gradient
	
	# Create area of effect visualization - using a simpler, more reliable approach
	var aoe_visual = ColorRect.new()
	aoe_visual.name = "AreaOfEffectVisual"
	explosion.add_child(aoe_visual)
	
	# Make sure it's placed correctly
	aoe_visual.z_index = -1
	aoe_visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Size and position the visualization
	var size = explosion_radius * 2
	aoe_visual.size = Vector2(size, size)
	aoe_visual.position = Vector2(-explosion_radius, -explosion_radius)
	
	# Set initial color (extremely transparent)
	aoe_visual.color = Color(1.0, 0.5, 0.1, 0.07)
	
	# Create a simple circle shape using a shader
	var shader = Shader.new()
	shader.code = """
	shader_type canvas_item;
	
	uniform vec4 inner_color : source_color = vec4(1.0, 0.4, 0.1, 0.07);
	
	void fragment() {
		float dist = length(UV - vec2(0.5));
		
		// Create a simple circle with no outline
		if (dist > 0.5) {
			// Outside the circle
			COLOR.a = 0.0;
		} else {
			// Inside - with soft edge
			float edge_softness = 0.03;
			float edge_factor = smoothstep(0.5 - edge_softness, 0.5, dist);
			COLOR = inner_color;
			COLOR.a = inner_color.a * (1.0 - edge_factor);
		}
	}
	"""
	
	var material = ShaderMaterial.new()
	material.shader = shader
	aoe_visual.material = material
	
	# Animate the fade-out (half the time)
	var aoe_tween = aoe_visual.create_tween()
	aoe_tween.tween_property(aoe_visual, "modulate:a", 0.0, 0.4)
	aoe_tween.tween_callback(aoe_visual.queue_free)
	
	# Create light effect
	var light = PointLight2D.new()
	explosion.add_child(light)
	light.texture = _create_light_texture()
	light.color = Color(1.0, 0.6, 0.2)
	light.energy = 1.0
	light.texture_scale = 2.0
	
	# Animate light
	var tween = light.create_tween()
	tween.tween_property(light, "energy", 0.0, 0.5)
	tween.parallel().tween_property(light, "texture_scale", 0.5, 0.5)
	
	# Auto-remove after lifetime
	var timer = Timer.new()
	explosion.add_child(timer)
	timer.wait_time = 0.8
	timer.one_shot = true
	timer.timeout.connect(func(): explosion.queue_free())
	timer.start()

# Create light texture
func _create_light_texture() -> Texture2D:
	var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	
	# Create a circular gradient
	for x in range(64):
		for y in range(64):
			var dist = Vector2(x - 32, y - 32).length()
			var alpha = 1.0 - min(1.0, dist / 32.0)
			var color = Color(1, 1, 1, alpha)
			image.set_pixel(x, y, color)
	
	return ImageTexture.create_from_image(image)

# API methods for configuration
func set_explosion_properties(radius: float, damage_amount: float) -> void:
	explosion_radius = radius
	explosion_damage = damage_amount

func set_acceleration(accel: float) -> void:
	acceleration = accel

func set_damage(value: float) -> void:
	damage = value
	# Set explosion damage to be proportional to direct hit damage
	explosion_damage = value * 0.6

func set_speed(value: float) -> void:
	speed = value
	current_speed = value
	# Update velocity immediately
	if is_inside_tree():
		velocity = Vector2(current_speed, 0).rotated(rotation)

func set_lifespan(value: float) -> void:
	lifespan = value

func set_shooter(node: Node) -> void:
	shooter = node
