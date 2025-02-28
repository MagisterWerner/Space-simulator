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
	# Create the laser using the scene
	var laser_scene = load("res://laser.tscn")
	var laser
	
	if laser_scene:
		laser = laser_scene.instantiate()
	else:
		push_error("ERROR: Failed to load laser scene")
		# Fallback to creating laser directly if scene load fails
		laser = Laser.new()
	
	# Set position
	var spawn_offset = direction * 30
	laser.global_position = spawn_position + spawn_offset
	
	# Configure the laser
	laser.direction = direction
	laser.rotation = direction.angle()
	laser.is_player_laser = entity.is_in_group("player")
	laser.damage = damage
	laser.speed = projectile_speed
	
	# Set the correct sprite based on player or enemy
	var sprite = laser.get_node_or_null("Sprite2D")
	if sprite:
		if laser.is_player_laser:
			# Try to load a blue laser texture
			var blue_laser_texture = load("res://sprites/weapons/laser_blue.png")
			if blue_laser_texture:
				sprite.texture = blue_laser_texture
			else:
				# Fallback to setting color
				sprite.modulate = Color(0.2, 0.8, 0.2)  # Green
		else:
			# Try to load a red laser texture
			var red_laser_texture = load("res://sprites/weapons/laser_red.png")
			if red_laser_texture:
				sprite.texture = red_laser_texture
			else:
				# Fallback to setting color
				sprite.modulate = Color(1.0, 0.2, 0.2)  # Red
	
	# Add to scene
	entity.get_tree().current_scene.add_child(laser)
	
	# Return the projectile array (just one for standard laser)
	return [laser]
