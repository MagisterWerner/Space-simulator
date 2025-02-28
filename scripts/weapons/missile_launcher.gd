class_name MissileLauncher
extends WeaponStrategy

# Missile specific properties
@export var tracking_strength: float = 3.0
@export var turn_speed: float = 2.0
@export var explosion_radius: float = 60.0
@export var missile_count: int = 1
@export var spread_angle: float = 0.2  # For multiple missiles

var missile_scene_path = "res://scenes/missile.tscn"

func _init():
	weapon_name = "MissileLauncher"
	cooldown = 1.2
	damage = 25.0
	energy_cost = 20.0
	projectile_speed = 400.0
	range = 1200.0

func fire(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	var projectiles = []
	
	# Create our own missiles instead of loading scenes
	# Calculate start angle for the spread (if multiple missiles)
	var start_angle = direction.angle() - (spread_angle * (missile_count - 1) / 2)
	
	# Create missiles
	for i in range(missile_count):
		var angle = start_angle + (spread_angle * i)
		var missile_dir = Vector2(cos(angle), sin(angle))
		
		# Create missile using Laser as base (fallback method)
		var missile = Laser.new()
		
		# Set position
		var spawn_offset = missile_dir * 40  # Spawn further away
		missile.global_position = spawn_position + spawn_offset
		
		# Configure the missile-like laser
		missile.direction = missile_dir
		missile.rotation = angle
		missile.is_player_laser = entity.is_in_group("player")
		missile.damage = damage
		missile.speed = projectile_speed / 2  # Slower than regular lasers
		
		# Add a sprite for the missile
		var sprite = Sprite2D.new()
		sprite.scale = Vector2(1.5, 0.8)  # Make it wider
		missile.add_child(sprite)
		
		# Add to scene
		entity.get_tree().current_scene.add_child(missile)
		projectiles.append(missile)
	
	return projectiles

# Helper function to find a target for the missile
func _find_closest_target(entity, is_player_missile: bool) -> Node2D:
	var target_group = "enemies" if is_player_missile else "player"
	var targets = entity.get_tree().get_nodes_in_group(target_group)
	
	var closest_target = null
	var closest_distance = INF
	
	for target in targets:
		if is_instance_valid(target) and target.visible:
			var distance = entity.global_position.distance_to(target.global_position)
			if distance < closest_distance:
				closest_target = target
				closest_distance = distance
	
	return closest_target
