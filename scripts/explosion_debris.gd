extends Node2D
class_name ExplosionDebris

@export var explosion_duration: float = 0.8  # Slightly longer for debris
@export var max_radius: float = 120.0
@export var num_dust_particles: int = 40
@export var num_debris_small_particles: int = 60
@export var num_debris_medium_particles: int = 30
@export var num_debris_large_particles: int = 15
@export var num_smoke_particles: int = 80

var dust_particles: CPUParticles2D
var debris_small_particles: CPUParticles2D
var debris_medium_particles: CPUParticles2D
var debris_large_particles: CPUParticles2D
var smoke_particles: CPUParticles2D
var sound_system = null

func _ready():
	z_index = 15
	
	# Get sound system reference
	sound_system = get_node_or_null("/root/SoundSystem")
	
	# Create dust cloud particles
	_create_dust_particles()
	
	# Create small debris particles
	_create_debris_small_particles()
	
	# Create medium debris particles
	_create_debris_medium_particles()
	
	# Create large debris particles
	_create_debris_large_particles()
	
	# Create smoke particles
	_create_smoke_particles()
	
	# Create explosion sound
	_create_explosion_sound()
	
	# Animate the explosion
	_animate_explosion()

func _create_dust_particles():
	dust_particles = CPUParticles2D.new()
	dust_particles.z_index = 5
	
	# Configure dust particles
	dust_particles.amount = num_dust_particles
	dust_particles.lifetime = explosion_duration * 0.6
	dust_particles.explosiveness = 0.9
	dust_particles.one_shot = true
	dust_particles.local_coords = false
	dust_particles.emitting = true
	
	# Direction and movement
	dust_particles.direction = Vector2(0, 0)
	dust_particles.spread = 180.0
	dust_particles.gravity = Vector2(0, 10)  # Subtle gravity
	dust_particles.initial_velocity_min = 30.0
	dust_particles.initial_velocity_max = 80.0
	
	# Appearance - rock dust color
	dust_particles.color = Color(0.7, 0.65, 0.6)
	dust_particles.scale_amount_min = 3.0
	dust_particles.scale_amount_max = 5.0
	
	# Create a gradient for dust fade-out
	var dust_gradient = Gradient.new()
	dust_gradient.add_point(0.0, Color(0.7, 0.65, 0.6, 0.9))
	dust_gradient.add_point(0.5, Color(0.65, 0.6, 0.55, 0.7))
	dust_gradient.add_point(1.0, Color(0.6, 0.55, 0.5, 0.0))
	
	var dust_ramp = GradientTexture1D.new()
	dust_ramp.gradient = dust_gradient
	dust_particles.color_ramp = dust_ramp
	
	add_child(dust_particles)

func _create_debris_small_particles():
	debris_small_particles = CPUParticles2D.new()
	debris_small_particles.z_index = 4
	
	# Configure small debris particles
	debris_small_particles.amount = num_debris_small_particles
	debris_small_particles.lifetime = explosion_duration * 0.8
	debris_small_particles.explosiveness = 1.0
	debris_small_particles.one_shot = true
	debris_small_particles.local_coords = false
	debris_small_particles.emitting = true
	
	# Direction and movement - fast small debris
	debris_small_particles.direction = Vector2(0, 0)
	debris_small_particles.spread = 360.0
	debris_small_particles.gravity = Vector2(0, 120)  # More affected by gravity
	debris_small_particles.initial_velocity_min = 250.0
	debris_small_particles.initial_velocity_max = 450.0
	
	# Appearance - small rock fragments
	debris_small_particles.color = Color(0.5, 0.45, 0.4)
	debris_small_particles.scale_amount_min = 1.0
	debris_small_particles.scale_amount_max = 2.0
	
	# Create a gradient for debris fade-out
	var debris_gradient = Gradient.new()
	debris_gradient.add_point(0.0, Color(0.5, 0.45, 0.4, 1.0))
	debris_gradient.add_point(0.8, Color(0.45, 0.4, 0.35, 0.8))
	debris_gradient.add_point(1.0, Color(0.4, 0.35, 0.3, 0.0))
	
	var debris_ramp = GradientTexture1D.new()
	debris_ramp.gradient = debris_gradient
	debris_small_particles.color_ramp = debris_ramp
	
	add_child(debris_small_particles)

func _create_debris_medium_particles():
	debris_medium_particles = CPUParticles2D.new()
	debris_medium_particles.z_index = 3
	
	# Configure medium debris particles
	debris_medium_particles.amount = num_debris_medium_particles
	debris_medium_particles.lifetime = explosion_duration * 0.9
	debris_medium_particles.explosiveness = 0.9
	debris_medium_particles.one_shot = true
	debris_medium_particles.local_coords = false
	debris_medium_particles.emitting = true
	
	# Direction and movement - medium speed debris
	debris_medium_particles.direction = Vector2(0, 0)
	debris_medium_particles.spread = 360.0
	debris_medium_particles.gravity = Vector2(0, 150)
	debris_medium_particles.initial_velocity_min = 150.0
	debris_medium_particles.initial_velocity_max = 300.0
	
	# Appearance - medium rock chunks
	debris_medium_particles.color = Color(0.45, 0.4, 0.35)
	debris_medium_particles.scale_amount_min = 2.5
	debris_medium_particles.scale_amount_max = 4.0
	
	# Create a gradient for debris fade-out
	var debris_gradient = Gradient.new()
	debris_gradient.add_point(0.0, Color(0.45, 0.4, 0.35, 1.0))
	debris_gradient.add_point(0.7, Color(0.4, 0.35, 0.3, 0.9))
	debris_gradient.add_point(1.0, Color(0.35, 0.3, 0.25, 0.0))
	
	var debris_ramp = GradientTexture1D.new()
	debris_ramp.gradient = debris_gradient
	debris_medium_particles.color_ramp = debris_ramp
	
	add_child(debris_medium_particles)

func _create_debris_large_particles():
	debris_large_particles = CPUParticles2D.new()
	debris_large_particles.z_index = 2
	
	# Configure large debris particles
	debris_large_particles.amount = num_debris_large_particles
	debris_large_particles.lifetime = explosion_duration
	debris_large_particles.explosiveness = 0.95
	debris_large_particles.one_shot = true
	debris_large_particles.local_coords = false
	debris_large_particles.emitting = true
	
	# Direction and movement - slower large chunks
	debris_large_particles.direction = Vector2(0, 0)
	debris_large_particles.spread = 360.0
	debris_large_particles.gravity = Vector2(0, 200)  # Heavy chunks fall faster
	debris_large_particles.initial_velocity_min = 100.0
	debris_large_particles.initial_velocity_max = 200.0
	
	# Appearance - large rock chunks
	debris_large_particles.color = Color(0.4, 0.35, 0.3)
	debris_large_particles.scale_amount_min = 4.0
	debris_large_particles.scale_amount_max = 6.0
	
	# Create a gradient for debris fade-out
	var debris_gradient = Gradient.new()
	debris_gradient.add_point(0.0, Color(0.4, 0.35, 0.3, 1.0))
	debris_gradient.add_point(0.6, Color(0.35, 0.3, 0.25, 0.9))
	debris_gradient.add_point(1.0, Color(0.3, 0.25, 0.2, 0.0))
	
	var debris_ramp = GradientTexture1D.new()
	debris_ramp.gradient = debris_gradient
	debris_large_particles.color_ramp = debris_ramp
	
	add_child(debris_large_particles)

func _create_smoke_particles():
	smoke_particles = CPUParticles2D.new()
	smoke_particles.z_index = 1
	
	# Configure smoke particles - dusty gray smoke
	smoke_particles.amount = num_smoke_particles
	smoke_particles.lifetime = explosion_duration * 1.2
	smoke_particles.explosiveness = 0.7
	smoke_particles.one_shot = true
	smoke_particles.local_coords = false
	smoke_particles.emitting = true
	
	# Direction and movement - slow rising dusty smoke
	smoke_particles.direction = Vector2(0, -1)
	smoke_particles.spread = 90.0
	smoke_particles.gravity = Vector2(0, -5)  # Very subtle lift
	smoke_particles.initial_velocity_min = 10.0
	smoke_particles.initial_velocity_max = 30.0
	
	# Appearance - dusty gray smoke
	smoke_particles.color = Color(0.5, 0.48, 0.45, 0.7)
	smoke_particles.scale_amount_min = 3.0
	smoke_particles.scale_amount_max = 6.0
	
	# Create a gradient for smoke fade-out
	var smoke_gradient = Gradient.new()
	smoke_gradient.add_point(0.0, Color(0.5, 0.48, 0.45, 0.7))
	smoke_gradient.add_point(0.4, Color(0.45, 0.43, 0.4, 0.5))
	smoke_gradient.add_point(1.0, Color(0.4, 0.38, 0.35, 0.0))
	
	var smoke_ramp = GradientTexture1D.new()
	smoke_ramp.gradient = smoke_gradient
	smoke_particles.color_ramp = smoke_ramp
	
	add_child(smoke_particles)

func _create_explosion_sound():
	# Use sound manager to play a random explosion sound
	if sound_system:
		sound_system.play_explosion(global_position)

func _animate_explosion():
	var tween = create_tween().set_parallel(true)
	
	# Animate dust particles
	var dust_duration = explosion_duration * 0.6
	tween.tween_property(dust_particles, "scale", Vector2(1.5, 1.5), dust_duration)
	tween.tween_property(dust_particles, "modulate:a", 0.0, dust_duration)
	
	# Animate small debris particles (quick fade)
	tween.tween_property(debris_small_particles, "scale", Vector2(1.2, 1.2), explosion_duration * 0.4)
	tween.tween_property(debris_small_particles, "modulate:a", 0.0, explosion_duration * 0.8)
	
	# Animate medium debris particles
	tween.tween_property(debris_medium_particles, "scale", Vector2(1.1, 1.1), explosion_duration * 0.5)
	tween.tween_property(debris_medium_particles, "modulate:a", 0.0, explosion_duration * 0.9)
	
	# Animate large debris particles
	tween.tween_property(debris_large_particles, "scale", Vector2(1.0, 1.0), explosion_duration * 0.6)
	tween.tween_property(debris_large_particles, "modulate:a", 0.0, explosion_duration)
	
	# Animate smoke particles (slowest to fade)
	tween.tween_property(smoke_particles, "scale", Vector2(1.8, 1.8), explosion_duration * 0.8)
	tween.tween_property(smoke_particles, "modulate:a", 0.0, explosion_duration * 1.2)
	
	# Remove the node after animation finishes
	tween.chain().tween_callback(queue_free).set_delay(0.2)
