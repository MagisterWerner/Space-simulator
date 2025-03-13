# scripts/effects/explosion_effect.gd
extends Node2D
class_name ExplosionEffect

@export var lifetime: float = 0.7
@export var explosion_scale: float = 1.0

# Particles
var _particles: CPUParticles2D
var _light: PointLight2D
var _audio_manager = null

func _ready() -> void:
	# Create particles
	_setup_particles()
	
	# Create light
	_setup_light()
	
	# Play sound
	if Engine.has_singleton("AudioManager"):
		_audio_manager = Engine.get_singleton("AudioManager")
		_audio_manager.play_sfx("explosion", global_position, randf_range(0.9, 1.1))
	
	# Set up timer for auto-removal
	var timer = get_tree().create_timer(lifetime)
	timer.timeout.connect(queue_free)

func _setup_particles() -> void:
	_particles = CPUParticles2D.new()
	add_child(_particles)
	
	# Configure particles
	_particles.emitting = true
	_particles.one_shot = true
	_particles.explosiveness = 1.0
	_particles.amount = int(30 * explosion_scale)
	_particles.lifetime = lifetime * 0.9
	
	# Particle properties
	_particles.direction = Vector2.ZERO
	_particles.spread = 180.0
	_particles.gravity = Vector2.ZERO
	_particles.initial_velocity_min = 30.0 * explosion_scale
	_particles.initial_velocity_max = 80.0 * explosion_scale
	_particles.scale_amount_min = 3.0 * explosion_scale
	_particles.scale_amount_max = 6.0 * explosion_scale
	_particles.damping_min = 10.0
	_particles.damping_max = 20.0
	
	# Create gradient
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(1.0, 0.9, 0.3, 1.0))
	gradient.add_point(0.2, Color(1.0, 0.5, 0.1, 1.0))
	gradient.add_point(0.6, Color(0.6, 0.2, 0.1, 0.6))
	gradient.add_point(1.0, Color(0.2, 0.1, 0.1, 0.0))
	_particles.color_ramp = gradient

func _setup_light() -> void:
	_light = PointLight2D.new()
	add_child(_light)
	
	# Configure light
	_light.texture = _create_light_texture()
	_light.color = Color(1.0, 0.6, 0.2)
	_light.energy = 1.0
	_light.texture_scale = 3.0 * explosion_scale
	
	# Animate light
	var tween = create_tween()
	tween.tween_property(_light, "energy", 0.0, lifetime * 0.8)
	tween.parallel().tween_property(_light, "texture_scale", 1.0 * explosion_scale, lifetime * 0.8)

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

# Static function to create an explosion at a position
static func create_explosion(position: Vector2, scale: float = 1.0) -> ExplosionEffect:
	var explosion_scene = load("res://scenes/effects/explosion_effect.tscn")
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = position
		explosion.explosion_scale = scale
		
		var current_scene = Engine.get_main_loop().current_scene
		current_scene.add_child(explosion)
		return explosion
	
	# Fallback if scene doesn't exist
	var explosion = ExplosionEffect.new()
	explosion.global_position = position
	explosion.explosion_scale = scale
	
	var current_scene = Engine.get_main_loop().current_scene
	current_scene.add_child(explosion)
	return explosion
