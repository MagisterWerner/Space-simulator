# explosion_effect.gd
extends Node2D

# Explosion configuration
@export var explosion_duration: float = 0.5  # Total animation time
@export var max_radius: float = 120.0  # Maximum explosion radius
@export var base_color: Color = Color(1, 0.5, 0, 1)  # Orange-yellow explosion

# Component nodes
var circle_sprite: Sprite2D
var particles: GPUParticles2D
var flash_sprite: Sprite2D

func _ready():
	# Create circle expansion effect
	circle_sprite = Sprite2D.new()
	_setup_circle_sprite()
	add_child(circle_sprite)
	
	# Create particle explosion
	particles = GPUParticles2D.new()
	_setup_particles()
	add_child(particles)
	
	# Create bright flash
	flash_sprite = Sprite2D.new()
	_setup_flash_sprite()
	add_child(flash_sprite)
	
	# Start explosion animations
	_animate_explosion()

func _setup_circle_sprite():
	# Create a radial gradient texture for the explosion circle
	var image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))  # Transparent background
	
	# Create radial gradient
	for x in range(256):
		for y in range(256):
			var center = Vector2(128, 128)
			var dist = center.distance_to(Vector2(x, y))
			var alpha = max(0, 1 - dist / 128.0)
			var color = base_color.lightened(0.2)
			color.a = alpha * 0.7
			image.set_pixel(x, y, color)
	
	var texture = ImageTexture.create_from_image(image)
	circle_sprite.texture = texture
	circle_sprite.modulate.a = 0.7

func _setup_particles():
	# Configure particle system for explosion debris
	particles.process_material = ParticleProcessMaterial.new()
	var material = particles.process_material as ParticleProcessMaterial
	
	# Particle appearance
	material.color = base_color
	material.color_ramp = Gradient.new()
	material.color_ramp.add_point(0, base_color)
	material.color_ramp.add_point(1, Color(base_color.r, base_color.g, base_color.b, 0))
	
	# Particle movement
	material.spread = 180.0  # Full circle spread
	material.initial_velocity_min = 100.0
	material.initial_velocity_max = 300.0
	material.gravity = Vector3.ZERO
	
	# Particle lifecycle
	particles.amount = 50
	particles.lifetime = explosion_duration
	particles.explosiveness = 1.0  # Instant burst
	particles.one_shot = true

func _setup_flash_sprite():
	# Create a bright flash that quickly fades
	var image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(1, 1, 1, 0.5))
	var texture = ImageTexture.create_from_image(image)
	flash_sprite.texture = texture
	flash_sprite.modulate.a = 0.8

func _animate_explosion():
	# Animate circle expansion
	var tween = create_tween()
	tween.set_parallel(true)
	
	# Circle expansion
	tween.tween_property(circle_sprite, "scale", Vector2.ONE * (max_radius / 128.0), explosion_duration)
	tween.tween_property(circle_sprite, "modulate:a", 0.0, explosion_duration)
	
	# Flash scaling and fading
	tween.tween_property(flash_sprite, "scale", Vector2.ONE * 2, explosion_duration * 0.5)
	tween.tween_property(flash_sprite, "modulate:a", 0.0, explosion_duration)
	
	# Start particle emission
	particles.restart()
	
	# Remove the explosion effect after animation
	tween.tween_callback(queue_free).set_delay(explosion_duration)
