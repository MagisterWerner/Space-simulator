extends Node2D

@export var explosion_duration: float = 0.5
@export var max_radius: float = 60.0
@export var color: Color = Color(1.0, 0.5, 0.0, 1.0)
@export var num_particles: int = 40

var circle_sprite: Sprite2D
var particles: CPUParticles2D
var flash_sprite: Sprite2D

func _ready():
	# Set z-index to ensure explosion is visible
	z_index = 15
	
	# Create the circle expansion
	_create_circle_sprite()
	
	# Create explosion particles
	_create_particles()
	
	# Create the flash effect
	_create_flash_sprite()
	
	# Animate the explosion
	_animate_explosion()

func _create_circle_sprite():
	circle_sprite = Sprite2D.new()
	circle_sprite.z_index = 1
	
	# Create a radial gradient texture for the circle
	var image = Image.create(128, 128, false, Image.FORMAT_RGBA8)
	for x in range(128):
		for y in range(128):
			var center = Vector2(64, 64)
			var dist = center.distance_to(Vector2(x, y))
			if dist < 64:
				var alpha = max(0, 1.0 - dist / 64.0)
				var pixel_color = color
				pixel_color.a = alpha * 0.7
				image.set_pixel(x, y, pixel_color)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	var texture = ImageTexture.create_from_image(image)
	circle_sprite.texture = texture
	
	# Start with small scale
	circle_sprite.scale = Vector2(0.1, 0.1)
	
	add_child(circle_sprite)

func _create_particles():
	particles = CPUParticles2D.new()
	particles.z_index = 2
	
	# Configure particles
	particles.amount = num_particles
	particles.lifetime = explosion_duration
	particles.explosiveness = 1.0
	particles.one_shot = true
	particles.local_coords = false
	particles.emitting = true
	
	# Direction and movement
	particles.direction = Vector2(0, 0)
	particles.spread = 180.0
	particles.gravity = Vector2(0, 0)
	particles.initial_velocity_min = 100.0
	particles.initial_velocity_max = 200.0
	
	# Appearance
	particles.color = color.lightened(0.2)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.0
	
	# Create a gradient for fade-out
	var gradient = Gradient.new()
	gradient.add_point(0.0, Color(color.r, color.g, color.b, 1.0))
	gradient.add_point(0.7, Color(color.r * 0.8, color.g * 0.5, color.b * 0.2, 0.8))
	gradient.add_point(1.0, Color(color.r * 0.6, color.g * 0.3, color.b * 0.1, 0.0))
	
	var ramp = GradientTexture1D.new()
	ramp.gradient = gradient
	particles.color_ramp = ramp
	
	add_child(particles)

func _create_flash_sprite():
	flash_sprite = Sprite2D.new()
	flash_sprite.z_index = 3
	
	# Create a simple white circle for the flash
	var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
	for x in range(64):
		for y in range(64):
			var center = Vector2(32, 32)
			var dist = center.distance_to(Vector2(x, y))
			if dist < 32:
				var alpha = 1.0 - dist / 32.0
				image.set_pixel(x, y, Color(1, 1, 1, alpha))
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	var texture = ImageTexture.create_from_image(image)
	flash_sprite.texture = texture
	
	# Start with small scale
	flash_sprite.scale = Vector2(0.5, 0.5)
	flash_sprite.modulate.a = 1.0
	
	add_child(flash_sprite)

func _animate_explosion():
	var tween = create_tween().set_parallel(true)
	
	# Animate circle expansion
	tween.tween_property(circle_sprite, "scale", Vector2(max_radius / 64.0, max_radius / 64.0), explosion_duration)
	tween.tween_property(circle_sprite, "modulate:a", 0.0, explosion_duration)
	
	# Animate flash
	tween.tween_property(flash_sprite, "scale", Vector2(1.5, 1.5), explosion_duration * 0.3)
	tween.tween_property(flash_sprite, "modulate:a", 0.0, explosion_duration * 0.4)
	
	# Remove the node after animation finishes
	tween.chain().tween_callback(queue_free).set_delay(0.1)
