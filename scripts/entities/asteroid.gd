extends Node2D
class_name Asteroid

# Component references
var health_component
var size_category: String = "medium"  # "small", "medium", or "large"
var sprite_variant: int = 0
var rotation_speed: float = 0.0
var base_scale: float = 1.0
var field_data = null  # Reference to parent asteroid field data

func _ready():
	# Set basic properties
	z_index = 3
	add_to_group("asteroids")
	
	# Get component references
	health_component = $HealthComponent
	
	# Configure health based on size
	if health_component:
		match size_category:
			"small":
				health_component.max_health = 20.0
			"medium":
				health_component.max_health = 50.0
			"large":
				health_component.max_health = 100.0
		
		health_component.current_health = health_component.max_health
		health_component.connect("died", _on_destroyed)
	
	# Apply scale to asteroid
	if has_node("Sprite2D"):
		$Sprite2D.scale = Vector2(base_scale, base_scale)

func _process(delta):
	# Apply rotation if set
	if rotation_speed != 0 and has_node("Sprite2D"):
		$Sprite2D.rotation += rotation_speed * delta

func setup(size: String, variant: int, scale_value: float, rot_speed: float):
	size_category = size
	sprite_variant = variant
	base_scale = scale_value
	rotation_speed = rot_speed

func take_damage(amount: float) -> bool:
	if health_component:
		return health_component.take_damage(amount)
	return false

func check_laser_hit(laser) -> bool:
	if get_collision_rect().has_point(to_local(laser.global_position)):
		return true
	return false

func get_collision_rect() -> Rect2:
	var sprite = $Sprite2D
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		var scaled_size = texture_size * sprite.scale
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	else:
		# Fallback collision rect
		var size = 10
		match size_category:
			"small": size = 10
			"medium": size = 20
			"large": size = 30
		return Rect2(-size/2, -size/2, size, size)

func _on_destroyed():
	# Spawn smaller asteroids if this was a large or medium asteroid
	_spawn_fragments()
	
	# Chance to spawn resources
	_spawn_resources()
	
	# Create explosion effect
	_create_explosion()
	
	# Remove asteroid
	queue_free()

func _spawn_fragments():
	# Only spawn fragments for medium and large asteroids
	if size_category == "small":
		return
	
	var spawner = get_node_or_null("/root/Main/AsteroidSpawner")
	if not spawner:
		return
	
	# Number of fragments to spawn
	var fragment_count = 2
	if size_category == "large":
		fragment_count = 3
	
	# Determine smaller size for fragments
	var fragment_size = "small"
	if size_category == "large":
		fragment_size = "medium"
	
	# Get the fragment sprites
	var fragment_sprites
	match fragment_size:
		"small": fragment_sprites = spawner.small_asteroid_sprites
		"medium": fragment_sprites = spawner.medium_asteroid_sprites
	
	# If no sprites, exit
	if fragment_sprites.size() == 0:
		return
	
	# Create a random generator
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Spawn fragments
	for i in range(fragment_count):
		# Create asteroid scene
		var asteroid_scene = load("res://scenes/asteroid.tscn")
		var fragment = asteroid_scene.instantiate()
		
		# Set fragment position with offset
		var angle = rng.randf_range(0, TAU)
		var distance = 20 * base_scale
		var offset = Vector2(cos(angle), sin(angle)) * distance
		fragment.global_position = global_position + offset
		
		# Configure fragment
		var sprite_idx = rng.randi() % fragment_sprites.size()
		var fragment_scale = base_scale * rng.randf_range(0.6, 0.9)
		var rot_speed = rng.randf_range(-1.0, 1.0)
		fragment.setup(fragment_size, sprite_idx, fragment_scale, rot_speed)
		
		# Add sprite
		var sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		sprite.texture = fragment_sprites[sprite_idx]
		fragment.add_child(sprite)
		
		# Add health component
		var health_comp = load("res://scripts/components/health_component.gd").new()
		health_comp.name = "HealthComponent"
		fragment.add_child(health_comp)
		
		# Add fragment to scene
		get_tree().current_scene.add_child(fragment)

func _spawn_resources():
	# Chance to spawn resources based on size
	var chance = 0.1  # 10% base chance
	match size_category:
		"small": chance = 0.1
		"medium": chance = 0.3
		"large": chance = 0.5
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	if rng.randf() <= chance:
		# Spawn resource if implemented
		pass

func _create_explosion():
	# Create explosion effect if implemented
	pass
