class_name WeaponPickup
extends Node2D

@export var weapon_type: String = "StandardLaser"
@export var pickup_radius: float = 40.0
@export var rotation_speed: float = 1.0
@export var bob_height: float = 5.0
@export var bob_speed: float = 2.0

var original_position: Vector2
var pickup_particles: CPUParticles2D
var weapon_strategy: WeaponStrategy

func _ready():
	# Set properties
	z_index = 5
	add_to_group("pickups")
	original_position = global_position
	
	# Create visual effects
	_create_visual_effects()
	
	# Create the appropriate weapon strategy based on type
	_initialize_weapon_strategy()

func _process(delta):
	# Rotate the pickup
	rotation += rotation_speed * delta
	
	# Bob up and down
	global_position.y = original_position.y + sin(Time.get_ticks_msec() / 1000.0 * bob_speed) * bob_height
	
	# Check for player collision
	_check_player_collision()

func _create_visual_effects():
	# Create particles
	pickup_particles = CPUParticles2D.new()
	pickup_particles.amount = 16
	pickup_particles.lifetime = 1.0
	pickup_particles.explosiveness = 0.0
	pickup_particles.local_coords = false
	pickup_particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_CIRCLE
	pickup_particles.emission_sphere_radius = 20.0
	pickup_particles.direction = Vector2(0, -1)
	pickup_particles.spread = 180.0
	pickup_particles.gravity = Vector2(0, -20)
	pickup_particles.initial_velocity = 10.0
	pickup_particles.scale_amount = 2.0
	
	# Set particle color based on weapon type
	match weapon_type:
		"StandardLaser":
			pickup_particles.color = Color(0.2, 0.5, 1.0)
		"SpreadShot":
			pickup_particles.color = Color(0.2, 0.8, 1.0)
		"ChargeBeam":
			pickup_particles.color = Color(1.0, 0.5, 0.0)
		"MissileLauncher":
			pickup_particles.color = Color(1.0, 0.3, 0.2)
		_:
			pickup_particles.color = Color(0.7, 0.7, 1.0)
	
	add_child(pickup_particles)

func _initialize_weapon_strategy():
	# Create the appropriate weapon strategy
	match weapon_type:
		"StandardLaser":
			weapon_strategy = StandardLaser.new()
		"SpreadShot":
			weapon_strategy = SpreadShot.new()
		"ChargeBeam":
			weapon_strategy = ChargeBeam.new()
		"MissileLauncher":
			weapon_strategy = MissileLauncher.new()
		_:
			weapon_strategy = StandardLaser.new()
			weapon_type = "StandardLaser"

func _check_player_collision():
	var player = get_node_or_null("/root/Main/Player")
	if not player:
		return
		
	var distance = global_position.distance_to(player.global_position)
	if distance <= pickup_radius:
		give_weapon_to_player(player)

func give_weapon_to_player(player):
	# Get the player's combat component
	var combat = player.get_node_or_null("CombatComponent")
	if not combat:
		return
	
	# Give the weapon to the player
	combat.add_weapon(weapon_type, weapon_strategy)
	combat.set_weapon(weapon_type)
	
	# Create pickup effect
	_create_pickup_effect()
	
	# Remove the pickup
	queue_free()

func _create_pickup_effect():
	# Create a flash effect
	var flash = CPUParticles2D.new()
	flash.position = global_position
	flash.z_index = 10
	flash.emitting = true
	flash.one_shot = true
	flash.explosiveness = 1.0
	flash.amount = 20
	flash.lifetime = 0.5
	flash.local_coords = false
	flash.direction = Vector2(0, 0)
	flash.spread = 180.0
	flash.gravity = Vector2(0, 0)
	flash.initial_velocity = 100.0
	flash.scale_amount = 3.0
	
	# Set color based on weapon type
	match weapon_type:
		"StandardLaser":
			flash.color = Color(0.2, 0.5, 1.0)
		"SpreadShot":
			flash.color = Color(0.2, 0.8, 1.0)
		"ChargeBeam":
			flash.color = Color(1.0, 0.5, 0.0)
		"MissileLauncher":
			flash.color = Color(1.0, 0.3, 0.2)
		_:
			flash.color = Color(0.7, 0.7, 1.0)
	
	# Add to the scene
	get_tree().current_scene.add_child(flash)
	
	# Remove after animation completes
	var timer = Timer.new()
	flash.add_child(timer)
	timer.wait_time = 0.6
	timer.one_shot = true
	timer.start()
	timer.timeout.connect(func(): flash.queue_free())

func _draw():
	# Draw the pickup if there's no sprite
	if not has_node("Sprite2D"):
		var color = Color(1, 1, 1)
		
		# Set color based on weapon type
		match weapon_type:
			"StandardLaser":
				color = Color(0.2, 0.5, 1.0)
			"SpreadShot":
				color = Color(0.2, 0.8, 1.0)
			"ChargeBeam":
				color = Color(1.0, 0.5, 0.0)
			"MissileLauncher":
				color = Color(1.0, 0.3, 0.2)
		
		# Draw weapon icon
		draw_circle(Vector2.ZERO, 15, color)
		
		# Draw weapon symbol based on type
		match weapon_type:
			"StandardLaser":
				# Draw laser line
				draw_line(Vector2(-10, 0), Vector2(10, 0), Color.WHITE, 3)
			"SpreadShot":
				# Draw spread lines
				draw_line(Vector2(-10, -5), Vector2(10, -10), Color.WHITE, 2)
				draw_line(Vector2(-10, 0), Vector2(10, 0), Color.WHITE, 2)
				draw_line(Vector2(-10, 5), Vector2(10, 10), Color.WHITE, 2)
			"ChargeBeam":
				# Draw charge beam
				draw_circle(Vector2.ZERO, 5, Color.WHITE)
				draw_line(Vector2(-10, 0), Vector2(10, 0), Color.WHITE, 5)
			"MissileLauncher":
				# Draw missile
				draw_rect(Rect2(-8, -3, 16, 6), Color.WHITE)
				draw_triangle(Vector2(8, 0), 8, Color.WHITE)
	
func draw_triangle(center, size, color):
	var points = PackedVector2Array([
		center + Vector2(size, 0),
		center + Vector2(-size/2, -size/2),
		center + Vector2(-size/2, size/2)
	])
	draw_colored_polygon(points, color)
