# scripts/projectiles/laser_projectile.gd
extends Area2D
class_name LaserProjectile

signal hit_target(target)

@export var speed: float = 1000.0
@export var damage: float = 10.0
@export var lifespan: float = 2.0
@export var pierce_targets: bool = false
@export var pierce_count: int = 0  # 0 means no piercing, > 0 is number of targets that can be pierced
@export var laser_color: Color = Color(1.0, 0.2, 0.2, 1.0)
@export var laser_width: float = 2.0
@export var impact_effect_scene: PackedScene = null

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 0.0
var shooter: Node = null
var hit_targets: Array = []

# Visual components 
var _sprite: Sprite2D = null
var _trail: Line2D = null
var _light: PointLight2D = null

func _ready() -> void:
	# Set up collision properties
	collision_layer = 8  # Projectile layer
	collision_mask = 4   # Asteroid layer (layer 3)
	
	# Pre-calculate velocity once
	velocity = Vector2.RIGHT.rotated(rotation) * speed
	
	# Connect collision signal
	body_entered.connect(_on_body_entered)
	
	# Set up visuals
	_setup_visual_components()
	
	# Cache sprite reference
	_sprite = get_node_or_null("Sprite2D")
	if _sprite:
		_sprite.modulate = laser_color

func _setup_visual_components() -> void:
	# Setup trail effect
	_setup_trail()
	
	# Setup light effect for better visibility
	_setup_light()
	
	# Update collision shape based on laser width
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape and collision_shape is CollisionShape2D:
		var shape = collision_shape.shape
		if shape is RectangleShape2D:
			shape.size.x = 16.0  # Length along X axis
			shape.size.y = laser_width  # Width along Y axis

func _setup_trail() -> void:
	# Remove any existing trail
	if has_node("LaserTrail"):
		get_node("LaserTrail").queue_free()
	
	# Create new trail
	_trail = Line2D.new()
	_trail.name = "LaserTrail"
	_trail.width = laser_width
	_trail.default_color = laser_color
	_trail.joint_mode = Line2D.LINE_JOINT_ROUND
	_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
	_trail.z_index = -1  # Behind the projectile
	add_child(_trail)
	
	# Set up trail points - pointing back along local X axis
	_trail.add_point(Vector2(-20, 0))  # Tail of laser
	_trail.add_point(Vector2(0, 0))    # Head of laser at projectile position

func _setup_light() -> void:
	# Remove any existing light
	if has_node("LaserGlow"):
		get_node("LaserGlow").queue_free()
	
	# Create new light
	_light = PointLight2D.new()
	_light.name = "LaserGlow"
	_light.color = laser_color
	_light.energy = 0.8
	_light.texture = _create_light_texture()
	_light.texture_scale = laser_width * 0.5
	add_child(_light)

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

func _process(delta: float) -> void:
	# Apply movement
	position += velocity * delta
	
	# Update lifetime - queue_free at end
	lifetime += delta
	if lifetime >= lifespan:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	# Skip already hit bodies and shooter
	if body == shooter or hit_targets.has(body):
		return
	
	# Process asteroid collisions
	if body.is_in_group("asteroids"):
		# Apply damage to asteroid via its HealthComponent or take_damage method
		var damage_applied = false
		
		# Try to get health component directly
		var health = body.get_node_or_null("HealthComponent")
		if health and health.has_method("apply_damage"):
			health.apply_damage(damage, "laser", shooter)
			damage_applied = true
		# Alternatively try direct take_damage method
		elif body.has_method("take_damage"):
			body.take_damage(damage, shooter)
			damage_applied = true
			
		if damage_applied:
			hit_target.emit(body)
			hit_targets.append(body)
			
			# Create impact effect
			_create_impact_effect(body)
			
			# Check if we should pierce through this target
			if not pierce_targets:
				queue_free()
				return
				
			# Limited piercing
			if pierce_count > 0:
				pierce_count -= 1
				if pierce_count <= 0:
					queue_free()
	
	# Process other types of collisions
	elif body.has_node("HealthComponent"):
		var health = body.get_node("HealthComponent")
		if health and health.has_method("apply_damage"):
			health.apply_damage(damage, "laser", shooter)
			hit_target.emit(body)
			hit_targets.append(body)
		
		# Create impact effect
		_create_impact_effect(body)
		
		# Handle piercing logic
		if not pierce_targets:
			queue_free()
		elif pierce_count > 0:
			pierce_count -= 1
			if pierce_count <= 0:
				queue_free()

# Create laser impact effect at hit position
func _create_impact_effect(body: Node2D) -> void:
	# Create particles at impact point
	var impact_particles = CPUParticles2D.new()
	impact_particles.global_position = global_position
	impact_particles.emitting = true
	impact_particles.one_shot = true
	impact_particles.explosiveness = 0.8
	impact_particles.amount = 15
	impact_particles.lifetime = 0.5
	impact_particles.direction = Vector2(-1, 0)  # Opposite to laser direction
	impact_particles.spread = 30.0
	impact_particles.initial_velocity_min = 20.0
	impact_particles.initial_velocity_max = 50.0
	impact_particles.scale_amount_min = 1.0
	impact_particles.scale_amount_max = 3.0
	
	# Set particle direction based on projectile rotation
	impact_particles.rotation = rotation + PI  # Opposite direction
	
	# Create color gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, laser_color)
	gradient.add_point(1.0, Color(laser_color.r, laser_color.g, laser_color.b, 0.0))
	impact_particles.color_ramp = gradient
	
	get_tree().current_scene.add_child(impact_particles)
	
	# Auto-remove particles after they finish
	var timer = Timer.new()
	impact_particles.add_child(timer)
	timer.wait_time = 0.6
	timer.one_shot = true
	timer.timeout.connect(func(): impact_particles.queue_free())
	timer.start()
	
	# Play impact sound if available
	if Engine.has_singleton("AudioManager"):
		AudioManager.play_sfx("laser_impact", global_position, randf_range(0.9, 1.1))

# Set direction method - use this to ensure proper movement direction
func set_direction(direction: Vector2) -> void:
	# Apply the rotation to match the direction vector
	rotation = direction.angle()
	
	# Set velocity to move in that direction
	velocity = direction.normalized() * speed

# Set the laser color
func set_laser_color(color: Color) -> void:
	laser_color = color
	
	# Update visuals
	if _sprite:
		_sprite.modulate = color
	
	if _trail:
		_trail.default_color = color
	
	if _light:
		_light.color = color

# Set the laser width
func set_laser_width(width: float) -> void:
	laser_width = width
	
	if _trail:
		_trail.width = width
	
	if _light:
		_light.texture_scale = width * 0.5
	
	# Update collision shape
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape and collision_shape is CollisionShape2D:
		var shape = collision_shape.shape
		if shape is RectangleShape2D:
			shape.size.y = width  # Width is on Y axis when rotated correctly

# Set other properties with efficient method signatures
func set_damage(value: float) -> void:
	damage = value

func set_speed(value: float) -> void:
	speed = value
	# Update velocity with new speed
	if is_inside_tree():
		velocity = velocity.normalized() * speed

func set_lifespan(value: float) -> void:
	lifespan = value

func set_shooter(node: Node) -> void:
	shooter = node

func set_piercing(value: bool, count: int = 0) -> void:
	pierce_targets = value
	pierce_count = count
