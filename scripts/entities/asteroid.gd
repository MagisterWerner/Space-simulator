# scripts/entities/asteroid.gd
# Asteroid entity that can be destroyed, split into fragments, and damage the player
extends Node2D
class_name Asteroid

var health_component
var size_category: String = "medium"
var sprite_variant: int = 0
var rotation_speed: float = 0.0
var base_scale: float = 1.0
var field_data = null
var initial_rotation: float = 0.0
var audio_manager = null

func _ready():
	z_index = 3
	add_to_group("asteroids")
	
	health_component = $HealthComponent
	
	# Look for AudioManager singleton
	if Engine.has_singleton("AudioManager"):
		audio_manager = AudioManager
	
	if health_component:
		match size_category:
			"small": health_component.max_health = 20.0
			"medium": health_component.max_health = 50.0
			"large": health_component.max_health = 100.0
		
		health_component.current_health = health_component.max_health
		health_component.connect("died", _on_destroyed)
	
	if has_node("Sprite2D"):
		var sprite = $Sprite2D
		sprite.scale = Vector2(base_scale, base_scale)
		sprite.rotation = initial_rotation
	
	set_process(true)
	
func _process(delta):
	if has_node("Sprite2D") and rotation_speed != 0:
		$Sprite2D.rotation += rotation_speed * delta

func setup(size: String, variant: int, scale_value: float, rot_speed: float, initial_rot: float = 0.0):
	size_category = size
	sprite_variant = variant
	base_scale = scale_value
	rotation_speed = rot_speed
	initial_rotation = initial_rot
	
	if has_node("Sprite2D"):
		$Sprite2D.scale = Vector2(base_scale, base_scale)
		$Sprite2D.rotation = initial_rotation

func take_damage(amount: float) -> bool:
	return health_component.take_damage(amount) if health_component else false

func check_laser_hit(laser) -> bool:
	return get_collision_rect().has_point(to_local(laser.global_position))

func get_collision_rect() -> Rect2:
	var sprite = $Sprite2D
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		var scaled_size = texture_size * sprite.scale
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	
	var size = 10
	match size_category:
		"small": size = 10
		"medium": size = 20
		"large": size = 30
	return Rect2(-size/2, -size/2, size, size)

func _on_destroyed():
	var explode_component = $ExplodeDebrisComponent if has_node("ExplodeDebrisComponent") else null
	
	if explode_component and explode_component.has_method("explode"):
		explode_component.explode()
	else:
		_create_explosion()
		
		if audio_manager:
			audio_manager.play_sfx("explosion", global_position)
		
		var asteroid_spawner = get_node_or_null("/root/Main/AsteroidSpawner")
		if asteroid_spawner:
			asteroid_spawner._spawn_fragments(
				global_position,
				size_category,
				2,
				base_scale
			)
	
	queue_free()

func _create_explosion():
	var explosion_scene_path = "res://scenes/explosion_effect.tscn"
	
	if ResourceLoader.exists(explosion_scene_path):
		var explosion_scene = load(explosion_scene_path)
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		
		var explosion_scale = 1.0
		match size_category:
			"small": explosion_scale = 0.5
			"medium": explosion_scale = 1.0
			"large": explosion_scale = 1.5
		
		explosion.scale = Vector2(explosion_scale, explosion_scale)
		get_tree().current_scene.add_child(explosion)
	else:
		var explosion_particles = CPUParticles2D.new()
		explosion_particles.emitting = true
		explosion_particles.one_shot = true
		explosion_particles.explosiveness = 1.0
		explosion_particles.amount = 30
		explosion_particles.lifetime = 0.6
		explosion_particles.local_coords = false
		explosion_particles.position = global_position
		explosion_particles.direction = Vector2.ZERO
		explosion_particles.spread = 180.0
		explosion_particles.gravity = Vector2.ZERO
		explosion_particles.initial_velocity_min = 100.0
		explosion_particles.initial_velocity_max = 150.0
		explosion_particles.scale_amount_min = 2.0
		explosion_particles.scale_amount_max = 4.0
		
		get_tree().current_scene.add_child(explosion_particles)
		
		var timer = Timer.new()
		explosion_particles.add_child(timer)
		timer.wait_time = 0.8
		timer.one_shot = true
		timer.timeout.connect(func(): explosion_particles.queue_free())
		timer.start()
