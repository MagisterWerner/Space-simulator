# scripts/entities/missile_projectile.gd
extends Node2D
class_name MissileProjectile

signal hit_target(target)

@export var speed: float = 300.0
@export var damage: float = 50.0
@export var lifespan: float = 5.0
@export var acceleration: float = 20.0
@export var max_speed: float = 600.0
@export var explosion_radius: float = 100.0
@export var explosion_damage: float = 30.0

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 0.0
var shooter: Node = null
var current_speed: float = 0.0
var direction: Vector2 = Vector2.RIGHT
var is_exploding: bool = false
var sound_player_id: int = -1

# Child components
var collision_detector: Area2D
var trail_effect: CPUParticles2D
var light_effect: PointLight2D

func _ready() -> void:
	# Set initial velocity
	current_speed = speed
	velocity = direction * current_speed
	
	# Create child components
	_setup_collision_detector()
	_setup_trail_effect()
	_setup_light_effect()
	
	# Start missile sound
	if Engine.has_singleton("AudioManager"):
		# Try to clear any existing missile sounds first
		AudioManager.stop_sfx("missile")
		# Play new missile sound
		var player = AudioManager.play_sfx("missile", global_position)
		if player and is_instance_valid(player):
			sound_player_id = player.get_instance_id()

func _process(delta: float) -> void:
	# Skip processing if exploding
	if is_exploding:
		return
		
	# Update lifetime and check for expiration
	lifetime += delta
	if lifetime >= lifespan:
		call_deferred("explode")
		return
	
	# Apply acceleration
	current_speed = min(current_speed + acceleration * delta, max_speed)
	
	# Apply final velocity
	velocity = direction * current_speed
	position += velocity * delta
	
	# Update sound position
	if Engine.has_singleton("AudioManager") and sound_player_id != -1:
		# If AudioManager has a method to update sound position
		if AudioManager.has_method("update_sfx_position"):
			AudioManager.update_sfx_position(sound_player_id, global_position)

func set_direction(new_direction: Vector2) -> void:
	direction = new_direction.normalized()
	rotation = direction.angle()

func set_damage(value: float) -> void:
	damage = value

func set_speed(value: float) -> void:
	speed = value
	current_speed = speed

func set_lifespan(value: float) -> void:
	lifespan = value

func set_shooter(node: Node) -> void:
	shooter = node

func set_explosion_properties(radius: float, explosion_dmg: float) -> void:
	explosion_radius = radius
	explosion_damage = explosion_dmg

func set_acceleration(value: float) -> void:
	acceleration = value

func _setup_collision_detector() -> void:
	# Create a collision detector as a child
	collision_detector = Area2D.new()
	collision_detector.name = "CollisionDetector"
	add_child(collision_detector)
	
	# Add collision shape
	var shape = CollisionShape2D.new()
	var circle = CircleShape2D.new()
	circle.radius = 10.0
	shape.shape = circle
	collision_detector.add_child(shape)
	
	# Connect signal
	collision_detector.body_entered.connect(_on_collision_detector_body_entered)
	
	# Disable and then re-enable after a short delay to prevent hitting shooter
	collision_detector.set_deferred("monitoring", false)
	collision_detector.set_deferred("monitorable", false)
	
	get_tree().create_timer(0.1).timeout.connect(func():
		collision_detector.set_deferred("monitoring", true)
		collision_detector.set_deferred("monitorable", true)
	)

func _on_collision_detector_body_entered(body: Node) -> void:
	# Skip if already exploding or body is shooter
	if is_exploding or body == shooter:
		return
	
	# Handle direct hit damage
	var health = body.get_node_or_null("HealthComponent")
	if health and health.has_method("apply_damage"):
		health.apply_damage(damage, "missile", shooter)
		hit_target.emit(body)
	
	# Trigger explosion
	call_deferred("explode")

func explode() -> void:
	# Prevent multiple explosions
	if is_exploding:
		return
		
	is_exploding = true
	
	# Stop missile sound
	_stop_missile_sound()
	
	# Create separate explosion entity
	if get_tree() and get_tree().current_scene:
		var explosion_scene = load("res://scripts/entities/missile_explosion.gd")
		if explosion_scene:
			var explosion = explosion_scene.new()
			explosion.global_position = global_position
			explosion.explosion_radius = explosion_radius
			explosion.explosion_damage = explosion_damage
			explosion.shooter = shooter
			get_tree().current_scene.add_child(explosion)
	
	# Queue for deletion
	queue_free()

func _stop_missile_sound() -> void:
	if Engine.has_singleton("AudioManager"):
		# Try multiple approaches to ensure sound stops
		
		# 1. Stop by ID if we have one
		if sound_player_id != -1 and AudioManager.has_method("stop_sfx_by_id"):
			AudioManager.stop_sfx_by_id(sound_player_id)
			
		# 2. Stop by sound name
		AudioManager.stop_sfx("missile")

func _setup_trail_effect() -> void:
	trail_effect = CPUParticles2D.new()
	add_child(trail_effect)
	
	# Basic particle settings
	trail_effect.emitting = true
	trail_effect.amount = 30
	trail_effect.lifetime = 0.8
	trail_effect.local_coords = false
	trail_effect.explosiveness = 0.0
	trail_effect.randomness = 0.1
	
	# Motion parameters
	trail_effect.direction = Vector2(-1, 0)  # Emit backward
	trail_effect.spread = 10
	trail_effect.gravity = Vector2(0, 0)
	trail_effect.initial_velocity_min = 20
	trail_effect.initial_velocity_max = 40
	
	# Appearance
	trail_effect.scale_amount_min = 2.0
	trail_effect.scale_amount_max = 3.0
	
	# Create gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.7, 0.2, 1.0))  # Bright orange at start
	gradient.add_point(0.5, Color(1.0, 0.3, 0.1, 0.8))  # Red-orange in middle
	gradient.add_point(1.0, Color(0.3, 0.2, 0.1, 0))    # Fade out at end
	trail_effect.color_ramp = gradient

func _setup_light_effect() -> void:
	# Create a light effect that follows the missile
	light_effect = PointLight2D.new()
	add_child(light_effect)
	
	# Set light properties
	light_effect.energy = 0.8
	light_effect.range_layer_min = -100
	light_effect.range_layer_max = 100
	light_effect.texture_scale = 0.5
	
	# Create light texture
	var light_img = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	light_img.fill(Color(0, 0, 0, 0))
	
	# Draw radial gradient for light
	for x in range(128):
		for y in range(128):
			var dx = x - 64
			var dy = y - 64
			var dist = sqrt(dx * dx + dy * dy)
			
			if dist <= 64:
				var intensity = 1.0 - (dist / 64.0)
				intensity = pow(intensity, 2)  # Make falloff more pronounced
				light_img.set_pixel(x, y, Color(1.0, 0.7, 0.3, intensity))
	
	var light_texture = ImageTexture.create_from_image(light_img)
	light_effect.texture = light_texture
	
	# Add flickering effect
	var tween = create_tween()
	tween.set_loops()
	tween.tween_property(light_effect, "energy", 1.0, 0.2)
	tween.tween_property(light_effect, "energy", 0.7, 0.2)
