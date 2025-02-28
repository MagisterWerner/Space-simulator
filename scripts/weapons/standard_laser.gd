class_name StandardLaser
extends WeaponStrategy

# Laser specific properties
@export var laser_color: Color = Color.BLUE

func _init():
	weapon_name = "Standard Laser"
	cooldown = 0.3
	damage = 10.0
	energy_cost = 5.0
	projectile_speed = 1000.0
	range = 800.0

func fire(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	# Create laser instance
	var laser_scene = load("res://laser.tscn")
	var laser = laser_scene.instantiate()
	
	# Set position
	var spawn_offset = direction * 30
	laser.global_position = spawn_position + spawn_offset
	
	# Configure the laser
	laser.direction = direction
	laser.rotation = direction.angle()
	laser.is_player_laser = entity.is_in_group("player")
	laser.damage = damage
	laser.speed = projectile_speed
	
	# Set laser color based on who's firing
	if laser.has_node("Sprite2D"):
		if laser.is_player_laser:
			laser.get_node("Sprite2D").modulate = laser_color
		else:
			laser.get_node("Sprite2D").modulate = Color.RED
	
	# Add to scene
	entity.get_tree().current_scene.add_child(laser)
	
	# Return the projectile array (just one for standard laser)
	return [laser]
