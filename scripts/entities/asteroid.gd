# scripts/entities/asteroid.gd
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

# Cache for frequently accessed nodes
var _sprite: Sprite2D
var _explosion_component: Node

func _ready() -> void:
	z_index = 3
	add_to_group("asteroids")
	
	health_component = $HealthComponent
	_sprite = $Sprite2D
	_explosion_component = $ExplodeDebrisComponent if has_node("ExplodeDebrisComponent") else null
	
	# Use direct singleton access - more efficient
	audio_manager = Engine.get_singleton("AudioManager")
	
	if health_component:
		match size_category:
			"small": health_component.max_health = 20.0
			"medium": health_component.max_health = 50.0
			"large": health_component.max_health = 100.0
		
		health_component.current_health = health_component.max_health
		health_component.connect("died", _on_destroyed)
	
	if _sprite:
		_sprite.scale = Vector2(base_scale, base_scale)
		_sprite.rotation = initial_rotation
	
	set_process(rotation_speed != 0)
	
func _process(delta: float) -> void:
	if _sprite:
		_sprite.rotation += rotation_speed * delta

func setup(size: String, variant: int, scale_value: float, rot_speed: float, initial_rot: float = 0.0) -> void:
	size_category = size
	sprite_variant = variant
	base_scale = scale_value
	rotation_speed = rot_speed
	initial_rotation = initial_rot
	
	if _sprite:
		_sprite.scale = Vector2(base_scale, base_scale)
		_sprite.rotation = initial_rotation
	
	# Only process if we need rotation
	set_process(rot_speed != 0)

func take_damage(amount: float) -> bool:
	return health_component.take_damage(amount) if health_component else false

func check_laser_hit(laser) -> bool:
	# More efficient collision check using global coordinates
	var global_rect = get_collision_rect()
	global_rect.position += global_position
	return global_rect.has_point(laser.global_position)

func get_collision_rect() -> Rect2:
	if _sprite and _sprite.texture:
		var texture_size = _sprite.texture.get_size()
		var scaled_size = texture_size * _sprite.scale
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	
	# Fallback to size-based rect
	var size = 10 * (1 if size_category == "small" else (2 if size_category == "medium" else 3))
	return Rect2(-size/2, -size/2, size, size)

func _on_destroyed() -> void:
	# Use cached explosion component
	if _explosion_component and _explosion_component.has_method("explode"):
		_explosion_component.explode()
	else:
		_create_explosion()
		
		if audio_manager:
			audio_manager.play_sfx("explosion", global_position)
		
		# Only get asteroid spawner if needed
		var asteroid_spawner = get_node_or_null("/root/Main/AsteroidSpawner")
		if asteroid_spawner:
			asteroid_spawner._spawn_fragments(
				global_position,
				size_category,
				2,
				base_scale
			)
	
	queue_free()

func _create_explosion() -> void:
	var explosion_scene_path = "res://scenes/explosion_effect.tscn"
	
	if ResourceLoader.exists(explosion_scene_path):
		var explosion_scene = load(explosion_scene_path)
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		
		var explosion_scale = 0.5 if size_category == "small" else (1.0 if size_category == "medium" else 1.5)
		explosion.scale = Vector2(explosion_scale, explosion_scale)
		get_tree().current_scene.add_child(explosion)
	else:
		# Fallback particles - simplified setup
		var particles = CPUParticles2D.new()
		
		# Configure particles in a more efficient way
		particles.emitting = true
		particles.one_shot = true
		particles.explosiveness = 1.0
		particles.amount = 30
		particles.lifetime = 0.6
		particles.position = global_position
		particles.direction = Vector2.ZERO
		particles.spread = 180.0
		particles.gravity = Vector2.ZERO
		particles.initial_velocity_min = 100.0
		particles.initial_velocity_max = 150.0
		particles.scale_amount_min = 2.0
		particles.scale_amount_max = 4.0
		
		# Use CallbackTimer pattern for cleanup
		get_tree().current_scene.add_child(particles)
		get_tree().create_timer(0.8).timeout.connect(particles.queue_free)
