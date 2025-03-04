# standard_laser.gd
class_name StandardLaser
extends WeaponStrategy

@export var laser_color: Color = Color(0.2, 0.8, 0.2)

func _init():
	weapon_name = "StandardLaser"
	cooldown = 0.3
	damage = 10.0
	energy_cost = 5.0
	projectile_speed = 1000.0
	range = 800.0

func fire(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	var laser = Laser.new()
	
	laser.global_position = spawn_position + direction * 30
	laser.direction = direction
	laser.rotation = direction.angle()
	laser.is_player_laser = entity.is_in_group("player")
	laser.damage = damage
	laser.speed = projectile_speed
	
	entity.get_tree().current_scene.add_child(laser)
	
	var sound_system = entity.get_node_or_null("/root/SoundSystem")
	if sound_system:
		sound_system.play_laser(spawn_position)
	
	return [laser]
