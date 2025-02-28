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
	weapon_name = "Missile Launcher"
	cooldown = 1.2
	damage = 25.0
	energy_cost = 20.0
	projectile_speed = 400.0
	range = 1200.0

func fire(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	var projectiles = []
	
	# Check if missile scene exists
	if not ResourceLoader.exists(missile_scene_path):
		# Fallback to creating a missile directly
		return _create_fallback_missiles(entity, spawn_position, direction)
	
	# Calculate start angle for the spread (if multiple missiles)
	var start_angle = direction.angle() - (spread_angle * (missile_count - 1) / 2)
	
	# Create missiles
	for i in range(missile_count):
		var angle = start_angle + (spread_angle * i)
		var missile_dir = Vector2(cos(angle), sin(angle))
		
		# Create missile instance
		var missile = load(missile_scene_path).instantiate()
		
		# Set position
		var spawn_offset = missile_dir * 40  # Spawn further away
		missile.global_position = spawn_position + spawn_offset
		
		# Configure the missile
		missile.direction = missile_dir
		missile.rotation = angle
		missile.is_player_missile = entity.is_in_group("player")
		missile.damage = damage
		missile.speed = projectile_speed
		missile.tracking_strength = tracking_strength
		missile.turn_speed = turn_speed
		missile.explosion_radius = explosion_radius
		missile.range = range
		
		# Set target if the entity has a targeting component
		var targeting = entity.get_node_or_null("TargetingComponent")
		if targeting and targeting.current_target:
			missile.target = targeting.current_target
		
		# Add to scene
		entity.get_tree().current_scene.add_child(missile)
		projectiles.append(missile)
	
	return projectiles

# Fallback method to create missiles if the scene doesn't exist
func _create_fallback_missiles(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	var projectiles = []
	
	# Calculate start angle for the spread (if multiple missiles)
	var start_angle = direction.angle() - (spread_angle * (missile_count - 1) / 2)
	
	# Create missiles using laser scene as a base
	var laser_scene = load("res://laser.tscn")
	
	for i in range(missile_count):
		var angle = start_angle + (spread_angle * i)
		var missile_dir = Vector2(cos(angle), sin(angle))
		
		# Create laser instance (as missile fallback)
		var missile = laser_scene.instantiate()
		
		# Set position
		var spawn_offset = missile_dir * 40
		missile.global_position = spawn_position + spawn_offset
		
		# Configure as a missile-like projectile
		missile.direction = missile_dir
		missile.rotation = angle
		missile.is_player_laser = entity.is_in_group("player")
		missile.damage = damage
		missile.speed = projectile_speed
		
		# Make it look more like a missile
		if missile.has_node("Sprite2D"):
			var sprite = missile.get_node("Sprite2D")
			sprite.modulate = Color(1.0, 0.6, 0.2)  # Orange
			sprite.scale = Vector2(1.5, 0.8)  # Make it wider
		
		# Add to scene
		entity.get_tree().current_scene.add_child(missile)
		projectiles.append(missile)
	
	return projectiles
