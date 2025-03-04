# spread_shot.gd
class_name SpreadShot
extends WeaponStrategy

@export var projectile_count: int = 3
@export var spread_angle: float = 0.3
@export var laser_color: Color = Color(0.2, 0.8, 1.0)

func _init():
	weapon_name = "SpreadShot"
	cooldown = 0.5
	damage = 8.0
	energy_cost = 12.0
	projectile_speed = 900.0
	range = 600.0

func fire(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	var projectiles = []
	var start_angle = direction.angle() - (spread_angle * (projectile_count - 1) / 2)
	
	var sound_system = entity.get_node_or_null("/root/SoundSystem")
	if sound_system:
		sound_system.play_laser(spawn_position)
	
	for i in range(projectile_count):
		var angle = start_angle + (spread_angle * i)
		var projectile_dir = Vector2(cos(angle), sin(angle))
		
		var laser = Laser.new()
		laser.global_position = spawn_position + projectile_dir * 30
		laser.direction = projectile_dir
		laser.rotation = angle
		laser.is_player_laser = entity.is_in_group("player")
		laser.damage = damage
		laser.speed = projectile_speed
		
		entity.get_tree().current_scene.add_child(laser)
		projectiles.append(laser)
	
	return projectiles
