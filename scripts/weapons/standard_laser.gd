class_name StandardLaser
extends WeaponStrategy

# Laser specific properties
@export var laser_color: Color = Color(0.2, 0.8, 0.2)  # Green for player

func _init():
	weapon_name = "StandardLaser"
	cooldown = 0.3
	damage = 10.0
	energy_cost = 5.0
	projectile_speed = 1000.0
	range = 800.0

func fire(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	# Create laser directly instead of using the scene
	var laser = Laser.new()
	
	# Set position
	var spawn_offset = direction * 30
	laser.global_position = spawn_position + spawn_offset
	
	# Configure the laser
	laser.direction = direction
	laser.rotation = direction.angle()
	laser.is_player_laser = entity.is_in_group("player")
	laser.damage = damage
	laser.speed = projectile_speed
	
	# Note: No Sprite2D is added here, so the laser will use its _draw method
	# which draws a colored rectangle based on is_player_laser
	
	# Add to scene
	entity.get_tree().current_scene.add_child(laser)
	
	# Play laser sound
	var sound_system = entity.get_node_or_null("/root/SoundSystem")
	if sound_system:
		sound_system.play_laser(spawn_position)
	
	# Return the projectile array (just one for standard laser)
	return [laser]
