# scripts/projectiles/laser_projectile.gd
extends "res://scripts/entities/projectile.gd"
class_name LaserProjectile

# Laser specific properties
@export var laser_color: Color = Color(1.0, 0.2, 0.2, 1.0)
@export var laser_width: float = 2.0
@export var laser_glow_strength: float = 0.8
@export var trail_length: int = 10

# Visual components
var _trail: Line2D = null
var _light: PointLight2D = null
var _sprite: Sprite2D = null
var _particles: GPUParticles2D = null

# Trail history
var _trail_points: Array = []
var _max_trail_points: int = 10

func _ready() -> void:
	super._ready()
	
	# Setup visual components
	_setup_visual_components()
	
	# Adjust collision shape
	var collision_shape = get_node_or_null("CollisionShape2D")
	if collision_shape and collision_shape is CollisionShape2D:
		var shape = collision_shape.shape
		if shape is RectangleShape2D:
			shape.size.x = laser_width + 2
			shape.size.y = laser_width + 2
	
	# Connect additional signals
	body_entered.connect(_on_laser_hit_body)

func _setup_visual_components() -> void:
	# Setup sprite if it exists
	_sprite = get_node_or_null("Sprite2D")
	if _sprite:
		_sprite.modulate = laser_color
	
	# Create trail effect
	_setup_trail()
	
	# Setup light
	_setup_light()
	
	# Setup particles
	_setup_particles()

func _setup_trail() -> void:
	if not _trail:
		_trail = Line2D.new()
		_trail.name = "LaserTrail"
		_trail.width = laser_width
		_trail.default_color = laser_color
		_trail.joint_mode = Line2D.LINE_JOINT_ROUND
		_trail.begin_cap_mode = Line2D.LINE_CAP_ROUND
		_trail.end_cap_mode = Line2D.LINE_CAP_ROUND
		_trail.z_index = -1  # Behind the projectile
		add_child(_trail)
		
		# Initialize trail points
		_trail_points.clear()
		for i in range(_max_trail_points):
			_trail_points.append(Vector2.ZERO)
			_trail.add_point(Vector2.ZERO)

func _setup_light() -> void:
	if not _light:
		_light = PointLight2D.new()
		_light.name = "LaserGlow"
		_light.color = laser_color
		_light.energy = laser_glow_strength
		_light.texture = _create_light_texture()
		_light.texture_scale = laser_width * 0.5
		add_child(_light)

func _setup_particles() -> void:
	if not _particles:
		_particles = GPUParticles2D.new()
		_particles.name = "LaserParticles"
		_particles.amount = 10
		_particles.lifetime = 0.5
		_particles.local_coords = false
		_particles.emitting = true
		_particles.process_material = _create_particle_material()
		add_child(_particles)

func _process(delta: float) -> void:
	super._process(delta)
	
	# Update trail effect
	_update_trail()

# Update the trail effect by shifting positions
func _update_trail() -> void:
	if not _trail:
		return
	
	# Shift trail points
	for i in range(_trail_points.size() - 1, 0, -1):
		_trail_points[i] = _trail_points[i - 1]
	
	# Set the first point to current position
	_trail_points[0] = Vector2.ZERO  # Local coordinates
	
	# Update line points
	for i in range(_trail_points.size()):
		if i < _trail.get_point_count():
			_trail.set_point_position(i, _trail_points[i])

# Create a simple light texture
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

# Create particle material
func _create_particle_material() -> ParticleProcessMaterial:
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	material.direction = Vector3(0, 0, 0)
	material.spread = 180.0
	material.gravity = Vector3(0, 0, 0)
	material.initial_velocity_min = 5.0
	material.initial_velocity_max = 15.0
	material.scale_min = 1.0
	material.scale_max = 2.0
	material.color = laser_color
	material.color_ramp = _create_color_gradient()
	return material

# Create color gradient for particles
func _create_color_gradient() -> Gradient:
	var gradient = Gradient.new()
	gradient.add_point(0.0, laser_color)
	gradient.add_point(1.0, Color(laser_color.r, laser_color.g, laser_color.b, 0.0))
	return gradient

# Handle laser hit
func _on_laser_hit_body(body: Node2D) -> void:
	if body == shooter:
		return
	
	# Create impact effect on hit
	_create_impact_effect(body)

# Create laser impact effect at hit position
func _create_impact_effect(body: Node2D) -> void:
	# Create particles at impact point
	var impact_particles = GPUParticles2D.new()
	impact_particles.global_position = global_position
	impact_particles.emitting = true
	impact_particles.one_shot = true
	impact_particles.explosiveness = 0.8
	impact_particles.amount = 15
	impact_particles.lifetime = 0.5
	impact_particles.process_material = _create_impact_material()
	get_tree().current_scene.add_child(impact_particles)
	
	# Auto-remove particles after they finish
	var timer = Timer.new()
	impact_particles.add_child(timer)
	timer.wait_time = 0.6
	timer.one_shot = true
	timer.timeout.connect(func(): impact_particles.queue_free())
	timer.start()

# Create impact particle material
func _create_impact_material() -> ParticleProcessMaterial:
	var material = ParticleProcessMaterial.new()
	material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	material.direction = Vector3(-1, 0, 0)  # Opposite to laser direction
	material.spread = 30.0
	material.gravity = Vector3(0, 0, 0)
	material.initial_velocity_min = 20.0
	material.initial_velocity_max = 50.0
	material.scale_min = 1.0
	material.scale_max = 3.0
	material.color = laser_color
	material.color_ramp = _create_color_gradient()
	return material

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
	
	if _particles and _particles.process_material:
		_particles.process_material.color = color

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
			shape.size.x = width + 2
			shape.size.y = width + 2
