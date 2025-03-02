class_name SpreadShot
extends WeaponStrategy

# Spread shot specific properties
@export var projectile_count: int = 3
@export var spread_angle: float = 0.3  # Radians
@export var laser_color: Color = Color(0.2, 0.8, 1.0)  # Light blue

func _init():
	weapon_name = "SpreadShot"
	cooldown = 0.5
	damage = 8.0  # Less damage per projectile
	energy_cost = 12.0  # More energy cost for multiple projectiles
	projectile_speed = 900.0
	range = 600.0

func fire(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	var projectiles = []
	
	# Calculate start angle for the spread
	var start_angle = direction.angle() - (spread_angle * (projectile_count - 1) / 2)
	
	# Play laser sound (just once for spread shot)
	var sound_system = entity.get_node_or_null("/root/SoundSystem")
	if sound_system:
		sound_system.play_laser(spawn_position)
	
	# Create multiple projectiles in a spread pattern
	for i in range(projectile_count):
		var angle = start_angle + (spread_angle * i)
		var projectile_dir = Vector2(cos(angle), sin(angle))
		
		# Create laser directly
		var laser = Laser.new()
		
		# Set position slightly offset in the direction
		var spawn_offset = projectile_dir * 30
		laser.global_position = spawn_position + spawn_offset
		
		# Configure the laser
		laser.direction = projectile_dir
		laser.rotation = angle
		laser.is_player_laser = entity.is_in_group("player")
		laser.damage = damage
		laser.speed = projectile_speed
		
		# Add to scene
		entity.get_tree().current_scene.add_child(laser)
		projectiles.append(laser)
	
	return projectiles
