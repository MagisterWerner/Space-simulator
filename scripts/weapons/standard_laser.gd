class_name StandardLaser
extends WeaponStrategy

# Laser specific properties
@export var laser_color: Color = Color.BLUE

func _init():
	weapon_name = "StandardLaser"
	cooldown = 0.3
	damage = 10.0
	energy_cost = 5.0
	projectile_speed = 1000.0
	range = 800.0

func fire(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	# Create the laser directly without using a scene
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
	
	# Add to scene
	entity.get_tree().current_scene.add_child(laser)
	
	# Return the projectile array (just one for standard laser)
	return [laser]
