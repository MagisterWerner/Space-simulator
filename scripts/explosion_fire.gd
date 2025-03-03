extends Node2D
class_name ExplosionFire

@export var explosion_duration: float = 0.6
@export var max_radius: float = 150.0
@export var num_center_fire_particles: int = 20
@export var num_core_fire_particles: int = 50
@export var num_core_smoke_particles: int = 100
@export var num_outer_smoke_particles: int = 150
@export var num_debris_particles: int = 30

var center_fire_particles: CPUParticles2D
var core_fire_particles: CPUParticles2D
var core_smoke_particles: CPUParticles2D
var outer_smoke_particles: CPUParticles2D
var debris_particles: CPUParticles2D
var sound_system = null

func _ready():
	z_index = 15
	
	# Get sound system reference
	sound_system = get_node_or_null("/root/SoundSystem")
	
	# Create center fire particles
	_create_center_fire_particles()
	
	# Create core fire particles
	_create_core_fire_particles()
	
	# Create core smoke particles
	_create_core_smoke_particles()
	
	# Create outer smoke particles
	_create_outer_smoke_particles()
	
	# Create debris particles
	_create_debris_particles()
	
	# Create explosion sound
	_create_explosion_sound()
	
	# Animate the explosion
	_animate_explosion()

func _create_center_fire_particles():
	center_fire_particles = CPUParticles2D.new()
	center_fire_particles.z_index = 5
	
	# Configure center fire particles
	center_fire_particles.amount = num_center_fire_particles
	center_fire_particles.lifetime = explosion_duration * 0.6  # Half smoke duration
	center_fire_particles.explosiveness = 0.9
	center_fire_particles.one_shot = true
	center_fire_particles.local_coords = false
	center_fire_particles.emitting = true
	
	# Direction and movement
	center_fire_particles.direction = Vector2(0, 0)
	center_fire_particles.spread = 180.0  # Very concentrated
	center_fire_particles.gravity = Vector2(0, -20)  # Very slow movement
	center_fire_particles.initial_velocity_min = 10.0
	center_fire_particles.initial_velocity_max = 30.0
	
	# Appearance
	center_fire_particles.color = Color(1.0, 0.7, 0.3)
	center_fire_particles.scale_amount_min = 6.0  # Very thick
	center_fire_particles.scale_amount_max = 8.0
	
	# Create a gradient for fire fade-out
	var fire_gradient = Gradient.new()
	fire_gradient.add_point(0.0, Color(1.0, 0.9, 0.3, 1.0))
	fire_gradient.add_point(0.5, Color(1.0, 0.6, 0.1, 0.7))
	fire_gradient.add_point(1.0, Color(0.8, 0.3, 0.0, 0.0))
	
	var fire_ramp = GradientTexture1D.new()
	fire_ramp.gradient = fire_gradient
	center_fire_particles.color_ramp = fire_ramp
	
	add_child(center_fire_particles)

func _create_core_fire_particles():
	core_fire_particles = CPUParticles2D.new()
	core_fire_particles.z_index = 4
	
	# Configure core fire particles
	core_fire_particles.amount = num_core_fire_particles
	core_fire_particles.lifetime = explosion_duration * 0.4
	core_fire_particles.explosiveness = 1.0
	core_fire_particles.one_shot = true
	core_fire_particles.local_coords = false
	core_fire_particles.emitting = true
	
	# Direction and movement
	core_fire_particles.direction = Vector2(0, 0)
	core_fire_particles.spread = 360.0
	core_fire_particles.gravity = Vector2(0, -100)
	core_fire_particles.initial_velocity_min = 300.0
	core_fire_particles.initial_velocity_max = 500.0
	
	# Appearance
	core_fire_particles.color = Color(1.0, 0.6, 0.2)
	core_fire_particles.scale_amount_min = 2.0  # Thicker particles
	core_fire_particles.scale_amount_max = 3.0
	
	# Create a gradient for fire fade-out
	var fire_gradient = Gradient.new()
	fire_gradient.add_point(0.0, Color(1.0, 0.8, 0.2, 1.0))
	fire_gradient.add_point(0.5, Color(1.0, 0.4, 0.1, 0.7))
	fire_gradient.add_point(1.0, Color(0.8, 0.2, 0.0, 0.0))
	
	var fire_ramp = GradientTexture1D.new()
	fire_ramp.gradient = fire_gradient
	core_fire_particles.color_ramp = fire_ramp
	
	add_child(core_fire_particles)

func _create_core_smoke_particles():
	core_smoke_particles = CPUParticles2D.new()
	core_smoke_particles.z_index = 3
	
	# Configure core smoke particles
	core_smoke_particles.amount = num_core_smoke_particles
	core_smoke_particles.lifetime = explosion_duration * 1.2
	core_smoke_particles.explosiveness = 0.9
	core_smoke_particles.one_shot = true
	core_smoke_particles.local_coords = false
	core_smoke_particles.emitting = true
	
	# Direction and movement
	core_smoke_particles.direction = Vector2(0, 0)
	core_smoke_particles.spread = 360.0
	core_smoke_particles.gravity = Vector2(0, -20)
	core_smoke_particles.initial_velocity_min = 20.0
	core_smoke_particles.initial_velocity_max = 50.0
	
	# Appearance
	core_smoke_particles.color = Color(0.2, 0.2, 0.2, 0.8)
	core_smoke_particles.scale_amount_min = 5.0  # Larger, thicker smoke
	core_smoke_particles.scale_amount_max = 7.0
	
	# Create a gradient for core smoke fade-out
	var core_smoke_gradient = Gradient.new()
	core_smoke_gradient.add_point(0.0, Color(0.2, 0.2, 0.2, 0.8))
	core_smoke_gradient.add_point(0.4, Color(0.3, 0.3, 0.3, 0.6))
	core_smoke_gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))
	
	var core_smoke_ramp = GradientTexture1D.new()
	core_smoke_ramp.gradient = core_smoke_gradient
	core_smoke_particles.color_ramp = core_smoke_ramp
	
	add_child(core_smoke_particles)

func _create_outer_smoke_particles():
	outer_smoke_particles = CPUParticles2D.new()
	outer_smoke_particles.z_index = 2
	
	# Configure outer smoke particles
	outer_smoke_particles.amount = num_outer_smoke_particles
	outer_smoke_particles.lifetime = explosion_duration * 1.5
	outer_smoke_particles.explosiveness = 0.5
	outer_smoke_particles.one_shot = true
	outer_smoke_particles.local_coords = false
	outer_smoke_particles.emitting = true
	
	# Direction and movement
	outer_smoke_particles.direction = Vector2(0, 0)
	outer_smoke_particles.spread = 360.0
	outer_smoke_particles.gravity = Vector2(0, -10)
	outer_smoke_particles.initial_velocity_min = 30.0
	outer_smoke_particles.initial_velocity_max = 80.0
	
	# Appearance
	outer_smoke_particles.color = Color(0.1, 0.1, 0.1, 0.6)
	outer_smoke_particles.scale_amount_min = 3.0
	outer_smoke_particles.scale_amount_max = 5.0
	
	# Create a gradient for outer smoke fade-out
	var outer_smoke_gradient = Gradient.new()
	outer_smoke_gradient.add_point(0.0, Color(0.1, 0.1, 0.1, 0.6))
	outer_smoke_gradient.add_point(0.4, Color(0.15, 0.15, 0.15, 0.4))
	outer_smoke_gradient.add_point(1.0, Color(0.1, 0.1, 0.1, 0.0))
	
	var outer_smoke_ramp = GradientTexture1D.new()
	outer_smoke_ramp.gradient = outer_smoke_gradient
	outer_smoke_particles.color_ramp = outer_smoke_ramp
	
	add_child(outer_smoke_particles)

func _create_debris_particles():
	debris_particles = CPUParticles2D.new()
	debris_particles.z_index = 1
	
	# Configure debris particles
	debris_particles.amount = num_debris_particles
	debris_particles.lifetime = explosion_duration * 0.8
	debris_particles.explosiveness = 1.0
	debris_particles.one_shot = true
	debris_particles.local_coords = false
	debris_particles.emitting = true
	
	# Direction and movement
	debris_particles.direction = Vector2(0, 0)
	debris_particles.spread = 360.0
	debris_particles.gravity = Vector2(0, 100)
	debris_particles.initial_velocity_min = 150.0
	debris_particles.initial_velocity_max = 300.0
	
	# Appearance - fire debris is more spark-like
	debris_particles.color = Color(0.9, 0.5, 0.1, 0.8)
	debris_particles.scale_amount_min = 1.0
	debris_particles.scale_amount_max = 2.0
	
	# Create a gradient for debris fade-out
	var debris_gradient = Gradient.new()
	debris_gradient.add_point(0.0, Color(1.0, 0.8, 0.2, 0.9))
	debris_gradient.add_point(0.5, Color(0.9, 0.4, 0.1, 0.6))
	debris_gradient.add_point(1.0, Color(0.5, 0.2, 0.1, 0.0))
	
	var debris_ramp = GradientTexture1D.new()
	debris_ramp.gradient = debris_gradient
	debris_particles.color_ramp = debris_ramp
	
	add_child(debris_particles)

func _create_explosion_sound():
	# Use sound manager to play a random explosion sound
	if sound_system:
		sound_system.play_explosion(global_position)

func _animate_explosion():
	var tween = create_tween().set_parallel(true)
	
	# Animate center fire particles (very slow, thick)
	var center_fire_duration = explosion_duration * 0.6
	tween.tween_property(center_fire_particles, "scale", Vector2(2.0, 2.0), center_fire_duration)
	tween.tween_property(center_fire_particles, "modulate:a", 0.0, center_fire_duration)
	
	# Animate core fire particles (fast, quick fade)
	tween.tween_property(core_fire_particles, "scale", Vector2(1.5, 1.5), explosion_duration * 0.3)
	tween.tween_property(core_fire_particles, "modulate:a", 0.0, explosion_duration * 0.4)
	
	# Animate core smoke particles (slow, thick lingering)
	tween.tween_property(core_smoke_particles, "scale", Vector2(3.0, 3.0), explosion_duration)
	tween.tween_property(core_smoke_particles, "modulate:a", 0.0, explosion_duration * 1.2)
	
	# Animate outer smoke particles
	tween.tween_property(outer_smoke_particles, "scale", Vector2(3.5, 3.5), explosion_duration * 1.2)
	tween.tween_property(outer_smoke_particles, "modulate:a", 0.0, explosion_duration * 1.5)
	
	# Animate debris particles
	tween.tween_property(debris_particles, "scale", Vector2(1.5, 1.5), explosion_duration * 0.6)
	tween.tween_property(debris_particles, "modulate:a", 0.0, explosion_duration * 0.7)
	
	# Remove the node after animation finishes
	tween.chain().tween_callback(queue_free).set_delay(0.1)
