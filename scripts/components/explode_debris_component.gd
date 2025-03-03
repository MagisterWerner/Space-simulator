extends Component
class_name ExplodeDebrisComponent

# Configuration settings for the explosion
@export var explosion_scale: float = 1.0
@export var explosion_duration_multiplier: float = 1.0
@export var explosion_radius: float = 60.0
@export var damage: float = 0.0
@export var damage_falloff: bool = true
@export var damage_groups: Array[String] = []
@export var screen_shake: bool = true
@export var screen_shake_intensity: float = 5.0
@export var screen_shake_duration: float = 0.2
@export var spawn_fragments: bool = true
@export var fragment_count: int = 2

# References
var sound_system = null
var explosion_scene = preload("res://scenes/explosion_debris.tscn")

# Size categories for spawning fragments
var size_categories = {
	"large": { "next": "medium", "count": 2 },
	"medium": { "next": "small", "count": 2 },
	"small": { "next": "", "count": 0 }
}

func _initialize():
	# Get sound system reference
	sound_system = entity.get_node_or_null("/root/SoundSystem")

# Called when the entity is destroyed
func explode():
	# Get the entity's position
	var explosion_position = entity.global_position
	
	# Create explosion visual effect
	_create_explosion_effect(explosion_position)
	
	# Play explosion sound
	if sound_system:
		sound_system.play_explosion(explosion_position)
	
	# Apply damage if needed
	if damage > 0:
		_apply_explosion_damage(explosion_position)
	
	# Add screen shake if enabled
	if screen_shake:
		_apply_screen_shake()
		
	# Spawn fragments if enabled
	if spawn_fragments and entity.has("size_category"):
		_spawn_fragments(explosion_position, entity.size_category)

# Create the explosion visual effect
func _create_explosion_effect(position: Vector2):
	# Try to load the explosion scene
	if explosion_scene == null:
		# Try to load it by path as fallback
		var explosion_scene_path = "res://scenes/explosion_debris.tscn"
		if ResourceLoader.exists(explosion_scene_path):
			explosion_scene = load(explosion_scene_path)
	
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = position
		
		# Apply scale
		explosion.scale = Vector2(explosion_scale, explosion_scale)
		
		# Apply duration modifier if the property exists
		if explosion.has_method("set") and "explosion_duration" in explosion:
			explosion.explosion_duration *= explosion_duration_multiplier
		
		# Add explosion to the scene tree
		entity.get_tree().current_scene.add_child(explosion)
	else:
		# Fallback if scene can't be loaded
		_create_fallback_explosion(position)

# Apply damage to entities within explosion radius
func _apply_explosion_damage(position: Vector2):
	# Get all entities in the damage groups
	var targets = []
	for group in damage_groups:
		targets.append_array(entity.get_tree().get_nodes_in_group(group))
	
	# Apply damage to entities within explosion radius
	for target in targets:
		if not is_instance_valid(target) or not target.visible:
			continue
			
		var distance = position.distance_to(target.global_position)
		if distance <= explosion_radius:
			var damage_amount = damage
			
			# Apply damage falloff if enabled
			if damage_falloff:
				var damage_factor = 1.0 - (distance / explosion_radius)
				damage_amount *= damage_factor
			
			# Apply damage if the entity has a take_damage method
			if target.has_method("take_damage"):
				target.take_damage(damage_amount)

# Apply screen shake effect
func _apply_screen_shake():
	# Find the camera if it exists
	var camera = null
	var player = entity.get_tree().get_first_node_in_group("player")
	
	if player and player.has_node("Camera2D"):
		camera = player.get_node("Camera2D")
	
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(screen_shake_intensity, screen_shake_duration)
	elif camera:
		# Simple fallback shake
		var original_position = camera.position
		
		# Create a tween for camera shake
		var tween = entity.create_tween()
		
		# Shake in random directions
		var shake_count = 5
		var original_shake_intensity = screen_shake_intensity
		
		for i in range(shake_count):
			var intensity = original_shake_intensity * (1.0 - float(i) / shake_count)
			var random_offset = Vector2(
				randf_range(-intensity, intensity),
				randf_range(-intensity, intensity)
			)
			
			tween.tween_property(
				camera, 
				"position",
				original_position + random_offset,
				screen_shake_duration / shake_count
			)
		
		# Return to original position
		tween.tween_property(camera, "position", original_position, screen_shake_duration / shake_count)

# Spawn fragments when an entity is destroyed
func _spawn_fragments(position: Vector2, current_size: String):
	# Check if the current size has fragment configuration
	if not size_categories.has(current_size) or size_categories[current_size].next.is_empty():
		return
	
	# Get next size category for fragments
	var next_size = size_categories[current_size].next
	var count = size_categories[current_size].count
	
	# Get asteroid spawner (since we're using its fragment spawning)
	var asteroid_spawner = entity.get_node_or_null("/root/Main/AsteroidSpawner")
	if asteroid_spawner and asteroid_spawner.has_method("_spawn_fragments"):
		# Get scale from entity if it exists
		var base_scale = 1.0
		if entity.has("base_scale"):
			base_scale = entity.base_scale
			
		# Use the spawner's method to create fragments
		asteroid_spawner._spawn_fragments(
			position,
			current_size,
			count,
			base_scale
		)

# Fallback explosion if scene can't be loaded
func _create_fallback_explosion(position: Vector2):
	# Create a basic explosion with particles
	var explosion = Node2D.new()
	explosion.position = position
	entity.get_tree().current_scene.add_child(explosion)
	
	# Create debris particles
	var debris_particles = CPUParticles2D.new()
	debris_particles.z_index = 10
	debris_particles.amount = 50
	debris_particles.lifetime = 0.7 * explosion_duration_multiplier
	debris_particles.explosiveness = 1.0
	debris_particles.one_shot = true
	debris_particles.emitting = true
	debris_particles.direction = Vector2(0, 0)
	debris_particles.spread = 180.0
	debris_particles.gravity = Vector2(0, 150)
	debris_particles.initial_velocity_min = 150.0 * explosion_scale
	debris_particles.initial_velocity_max = 250.0 * explosion_scale
	debris_particles.scale_amount_min = 2.0 * explosion_scale
	debris_particles.scale_amount_max = 4.0 * explosion_scale
	debris_particles.color = Color(0.5, 0.45, 0.4, 0.8)
	
	explosion.add_child(debris_particles)
	
	# Create dust particles
	var dust_particles = CPUParticles2D.new()
	dust_particles.z_index = 9
	dust_particles.amount = 40
	dust_particles.lifetime = 0.9 * explosion_duration_multiplier
	dust_particles.explosiveness = 0.8
	dust_particles.one_shot = true
	dust_particles.emitting = true
	dust_particles.direction = Vector2(0, 0)
	dust_particles.spread = 180.0
	dust_particles.gravity = Vector2(0, 10)
	dust_particles.initial_velocity_min = 40.0 * explosion_scale
	dust_particles.initial_velocity_max = 80.0 * explosion_scale
	dust_particles.scale_amount_min = 3.0 * explosion_scale
	dust_particles.scale_amount_max = 6.0 * explosion_scale
	dust_particles.color = Color(0.6, 0.55, 0.5, 0.6)
	
	explosion.add_child(dust_particles)
	
	# Delete the node after the explosion finishes
	var timer = Timer.new()
	timer.wait_time = 1.2 * explosion_duration_multiplier
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): explosion.queue_free())
	explosion.add_child(timer)
