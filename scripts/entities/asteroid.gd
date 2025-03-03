extends Node2D
class_name Asteroid

# Component references
var health_component
var size_category: String = "medium"  # "small", "medium", or "large"
var sprite_variant: int = 0
var rotation_speed: float = 0.0
var base_scale: float = 1.0
var field_data = null  # Reference to parent asteroid field data
var initial_rotation: float = 0.0  # Store the initial rotation from the seed

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
	
	# Apply scale and initial rotation to asteroid sprite
	if has_node("Sprite2D"):
		var sprite = $Sprite2D
		sprite.scale = Vector2(base_scale, base_scale)
		sprite.rotation = initial_rotation  # Set initial rotation based on seed
	
	# Ensure this node is processing
	process_mode = Node.PROCESS_MODE_INHERIT
	set_process(true)
	
func _process(delta):
	# Apply rotation if rotation speed is set
	if has_node("Sprite2D") and rotation_speed != 0:
		# Apply rotation to the sprite directly
		$Sprite2D.rotation += rotation_speed * delta

# Setup function called when asteroid is spawned or reused from pool
func setup(size: String, variant: int, scale_value: float, rot_speed: float, initial_rot: float = 0.0):
	size_category = size
	sprite_variant = variant
	base_scale = scale_value
	rotation_speed = rot_speed  # Rotation speed in radians per second
	initial_rotation = initial_rot  # Store the initial rotation
	
	# Apply settings immediately if we already have a sprite
	if has_node("Sprite2D"):
		$Sprite2D.scale = Vector2(base_scale, base_scale)
		$Sprite2D.rotation = initial_rotation

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
	# Get the spawner
	var asteroid_spawner = get_node_or_null("/root/Main/AsteroidSpawner")
	if asteroid_spawner:
		# Use the spawner's method to create procedural fragments
		asteroid_spawner._spawn_fragments(
			global_position,
			size_category,
			2, # Default fragment count (will be overridden in spawner)
			base_scale
		)
	
	# Chance to spawn resources
	_spawn_resources()
	
	# Create explosion effect
	_create_explosion()
	
	# Remove asteroid
	queue_free()

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
	# Use the explosion effect scene if it exists
	var explosion_scene_path = "res://scenes/explosion_effect.tscn"
	
	if ResourceLoader.exists(explosion_scene_path):
		var explosion_scene = load(explosion_scene_path)
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		
		# Scale explosion based on asteroid size
		var explosion_scale = 1.0
		match size_category:
			"small": explosion_scale = 0.5
			"medium": explosion_scale = 1.0
			"large": explosion_scale = 1.5
		
		explosion.scale = Vector2(explosion_scale, explosion_scale)
		
		# Add to scene
		get_tree().current_scene.add_child(explosion)
	else:
		# Simple fallback explosion
		var explosion_particles = CPUParticles2D.new()
		explosion_particles.emitting = true
		explosion_particles.one_shot = true
		explosion_particles.explosiveness = 1.0
		explosion_particles.amount = 30
		explosion_particles.lifetime = 0.6
		explosion_particles.local_coords = false
		explosion_particles.position = global_position
		explosion_particles.direction = Vector2(0, 0)
		explosion_particles.spread = 180.0
		explosion_particles.gravity = Vector2(0, 0)
		explosion_particles.initial_velocity_min = 100.0
		explosion_particles.initial_velocity_max = 150.0
		explosion_particles.scale_amount_min = 2.0
		explosion_particles.scale_amount_max = 4.0
		
		# Add to scene
		get_tree().current_scene.add_child(explosion_particles)
		
		# Remove after the particles complete
		var timer = Timer.new()
		explosion_particles.add_child(timer)
		timer.wait_time = 0.8
		timer.one_shot = true
		timer.timeout.connect(func(): explosion_particles.queue_free())
		timer.start()
