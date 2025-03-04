# missile_launcher.gd
class_name MissileLauncher
extends WeaponStrategy

@export var tracking_strength: float = 3.0
@export var turn_speed: float = 2.0
@export var explosion_radius: float = 60.0
@export var missile_count: int = 1
@export var spread_angle: float = 0.2

func _init():
	weapon_name = "MissileLauncher"
	cooldown = 1.0
	damage = 25.0
	energy_cost = 20.0
	projectile_speed = 400.0
	range = 1200.0

func fire(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	var projectiles = []
	var start_angle = direction.angle() - (spread_angle * (missile_count - 1) / 2)
	var missile_scene = null
	
	if ResourceLoader.exists("res://scenes/homing_missile.tscn"):
		missile_scene = load("res://scenes/homing_missile.tscn")
	
	var sound_system = entity.get_node_or_null("/root/SoundSystem")
	if sound_system:
		sound_system.play_laser(spawn_position)
	
	for i in range(missile_count):
		var angle = start_angle + (spread_angle * i)
		var missile_dir = Vector2(cos(angle), sin(angle))
		var missile = null
		
		if missile_scene:
			missile = missile_scene.instantiate()
		else:
			missile = HomingMissile.new()
			var sprite = Sprite2D.new()
			sprite.name = "Sprite2D"
			
			if ResourceLoader.exists("res://sprites/weapons/missile.png"):
				sprite.texture = load("res://sprites/weapons/missile.png")
			else:
				var image = Image.create(20, 6, false, Image.FORMAT_RGBA8)
				var color = Color(0.2, 0.8, 1.0) if entity.is_in_group("player") else Color(1.0, 0.3, 0.2)
				for x in range(20):
					for y in range(6):
						image.set_pixel(x, y, color)
				sprite.texture = ImageTexture.create_from_image(image)
			
			sprite.scale = Vector2(1.0, 1.0)
			missile.add_child(sprite)
		
		missile.is_player_missile = entity.is_in_group("player")
		missile.direction = missile_dir
		missile.speed = projectile_speed
		missile.damage = damage
		missile.tracking_strength = tracking_strength
		missile.turn_speed = turn_speed
		missile.explosion_radius = explosion_radius
		missile.range = range
		
		missile.global_position = spawn_position + missile_dir * 40
		missile.rotation = angle
		missile.target = _find_closest_target(entity, missile.is_player_missile)
		
		entity.get_tree().current_scene.add_child(missile)
		projectiles.append(missile)
	
	return projectiles

func _find_closest_target(entity, is_player_missile: bool) -> Node2D:
	var target_groups = ["enemies", "asteroids"] if is_player_missile else ["player"]
	var all_targets = []
	
	for group in target_groups:
		all_targets.append_array(entity.get_tree().get_nodes_in_group(group))
	
	var closest_target = null
	var closest_distance = INF
	
	for target in all_targets:
		if is_instance_valid(target) and target.visible:
			var distance = entity.global_position.distance_to(target.global_position)
			if distance < closest_distance:
				closest_target = target
				closest_distance = distance
	
	return closest_target
