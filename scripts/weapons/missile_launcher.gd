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
	
	# Calculate start angle for the spread
	var start_angle = direction.angle() - (spread_angle * (missile_count - 1) / 2)
	
	# Create missile scene resource
	var missile_scene_path = "res://scenes/homing_missile.tscn"
	var missile_scene = null
	
	if ResourceLoader.exists(missile_scene_path):
		missile_scene = load(missile_scene_path)
	
	# Create missiles
	for i in range(missile_count):
		var angle = start_angle + (spread_angle * i)
		var missile_dir = Vector2(cos(angle), sin(angle))
		
		var missile = null
		
		# Create missile from scene if available
		if missile_scene:
			missile = missile_scene.instantiate()
		else:
			# Create missile manually if scene not available
			missile = HomingMissile.new()
			
			# Create sprite
			var sprite = Sprite2D.new()
			sprite.name = "Sprite2D"
			
			# Try to load missile texture
			var texture_path = "res://sprites/weapons/missile.png"
			if ResourceLoader.exists(texture_path):
				sprite.texture = load(texture_path)
			else:
				# Create a simple texture
				var image = Image.create(20, 6, false, Image.FORMAT_RGBA8)
				var color = Color(0.2, 0.8, 1.0) if entity.is_in_group("player") else Color(1.0, 0.3, 0.2)
				for x in range(20):
					for y in range(6):
						image.set_pixel(x, y, color)
				var texture = ImageTexture.create_from_image(image)
				sprite.texture = texture
			
			sprite.scale = Vector2(1.0, 1.0)
			missile.add_child(sprite)
		
		# Configure missile properties
		missile.is_player_missile = entity.is_in_group("player")
		missile.direction = missile_dir
		missile.speed = projectile_speed
		missile.damage = damage
		missile.tracking_strength = tracking_strength
		missile.turn_speed = turn_speed
		missile.explosion_radius = explosion_radius
		missile.range = range
		
		# Set position with offset
		missile.global_position = spawn_position + missile_dir * 40
		missile.rotation = angle
		
		# Find initial target
		missile.target = _find_closest_target(entity, missile.is_player_missile)
		
		# Add to scene
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
