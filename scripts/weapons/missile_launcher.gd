class_name MissileLauncher
extends WeaponStrategy

# Enhanced Missile Launcher with Explosive Area Damage
@export var tracking_strength: float = 5.0  # Increased tracking strength
@export var turn_speed: float = 4.0  # Faster turning
@export var explosion_radius: float = 120.0  # Increased explosion radius
@export var explosion_damage: float = 50.0  # Damage dealt by explosion
@export var missile_count: int = 1
@export var spread_angle: float = 0.2  # For multiple missiles

var missile_scene_path = "res://scenes/homing_missile.tscn"
var explosion_scene_path = "res://scenes/explosion_effect.tscn"

func _init():
	weapon_name = "ExplosiveMissileLauncher"
	cooldown = 1.0
	damage = 30.0
	energy_cost = 25.0
	projectile_speed = 600.0
	range = 1500.0

func fire(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	var projectiles = []
	
	# Calculate start angle for the spread
	var start_angle = direction.angle() - (spread_angle * (missile_count - 1) / 2)
	
	# Create missiles
	for i in range(missile_count):
		var angle = start_angle + (spread_angle * i)
		var missile_dir = Vector2(cos(angle), sin(angle))
		
		# Create homing missile
		var missile = Area2D.new()
		missile.name = "HomingMissile_" + str(i)
		
		# Collision shape
		var collision_shape = CollisionShape2D.new()
		var shape = CircleShape2D.new()
		shape.radius = 10
		collision_shape.shape = shape
		missile.add_child(collision_shape)
		
		# Sprite for the missile
		var sprite = Sprite2D.new()
		sprite.scale = Vector2(1.5, 0.8)
		sprite.modulate = Color.WHITE
		
		# Create a simple white texture if no texture is loaded
		var image = Image.create(20, 10, false, Image.FORMAT_RGB8)
		image.fill(Color.WHITE)
		var texture = ImageTexture.create_from_image(image)
		sprite.texture = texture
		
		missile.add_child(sprite)
		
		# Missile Script with Explosion Mechanism
		var script = GDScript.new()
		script.source_code = """
extends Area2D

# Missile configuration
var speed: float = 600.0
var direct_damage: float = 30.0
var explosion_damage: float = 50.0
var explosion_radius: float = 120.0
var direction: Vector2
var tracking_strength: float = 5.0
var is_player_missile: bool = false
var lifetime: float = 3.0

# Explosion effect
var explosion_scene = preload('res://scenes/explosion_effect.tscn')

func _ready():
	# Connect body_entered signal
	connect('body_entered', _on_body_entered)

func _physics_process(delta):
	# Decrement lifetime
	lifetime -= delta
	if lifetime <= 0:
		explode()
		return
	
	# Find closest target (asteroids or enemies)
	var target = _find_closest_target()
	
	if target:
		# Calculate direction to target
		var target_direction = (target.global_position - global_position).normalized()
		
		# Smoothly interpolate current direction towards target
		direction = direction.lerp(target_direction, tracking_strength * delta)
	
	# Move missile
	global_position += direction * speed * delta
	rotation = direction.angle()

func _find_closest_target():
	# Combine enemy and asteroid groups
	var potential_targets = get_tree().get_nodes_in_group('enemies') + get_tree().get_nodes_in_group('asteroids')
	
	var closest_target = null
	var closest_distance = INF
	
	for target in potential_targets:
		if is_instance_valid(target) and target.visible:
			var distance = global_position.distance_to(target.global_position)
			if distance < closest_distance:
				closest_target = target
				closest_distance = distance
	
	return closest_target

func _on_body_entered(body):
	# Trigger explosion on body contact
	explode(body)

func explode(direct_hit_body = null):
	# Direct damage to the hit body
	if direct_hit_body and direct_hit_body.has_method('take_damage'):
		direct_hit_body.take_damage(direct_damage)
	
	# Find and damage nearby targets
	var nearby_targets = get_tree().get_nodes_in_group('enemies') + get_tree().get_nodes_in_group('asteroids')
	
	for target in nearby_targets:
		if is_instance_valid(target) and target.visible:
			var distance = global_position.distance_to(target.global_position)
			
			# Check if target is within explosion radius
			if distance <= explosion_radius:
				# Calculate damage falloff (linear for simplicity)
				var damage_multiplier = 1.0 - (distance / explosion_radius)
				var area_damage = explosion_damage * damage_multiplier
				
				if target.has_method('take_damage'):
					target.take_damage(area_damage)
	
	# Create explosion effect (if scene exists)
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		get_tree().current_scene.add_child(explosion)
	
	# Remove the missile
	queue_free()
"""
		
		# Compile the script
		var err = script.reload()
		if err != OK:
			print("Failed to compile missile script")
			continue
		
		# Set the script to the missile
		missile.set_script(script)
		
		# Set missile properties
		missile.global_position = spawn_position + missile_dir * 40
		missile.rotation = angle
		
		# Configure missile script properties
		missile.speed = projectile_speed
		missile.direct_damage = damage
		missile.explosion_damage = explosion_damage
		missile.explosion_radius = explosion_radius
		missile.direction = missile_dir
		missile.tracking_strength = tracking_strength
		missile.is_player_missile = entity.is_in_group("player")
		
		# Add to scene
		var scene_root = entity.get_tree().current_scene
		if scene_root:
			scene_root.add_child(missile)
			projectiles.append(missile)
	
	return projectiles

# Optional: Helper function to find a target
func _find_closest_target(entity, is_player_missile: bool) -> Node2D:
	var target_groups = ["enemies", "asteroids"]
	var all_targets = []
	
	for group in target_groups:
		all_targets += entity.get_tree().get_nodes_in_group(group)
	
	var closest_target = null
	var closest_distance = INF
	
	for target in all_targets:
		if is_instance_valid(target) and target.visible:
			var distance = entity.global_position.distance_to(target.global_position)
			if distance < closest_distance:
				closest_target = target
				closest_distance = distance
	
	return closest_target
