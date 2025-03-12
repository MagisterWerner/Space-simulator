# scripts/entities/asteroid.gd - Highly optimized implementation
extends Node2D
class_name Asteroid

# Core components and properties
var health_component: HealthComponent
var size_category: String = "medium"
var rotation_speed: float = 0.0
var base_scale: float = 1.0
var field_data = null
var audio_manager = null

# Frequently accessed nodes - cached
var _sprite: Sprite2D
var _explosion_component: Node
var _collision_rect: Rect2
var _collision_rect_global: Rect2
var _health_values := {"small": 20.0, "medium": 50.0, "large": 100.0}

# Static shared paths - avoid recalculation
const EXPLOSION_SCENE_PATH: String = "res://scenes/explosion_effect.tscn"

func _ready() -> void:
	z_index = 3
	add_to_group("asteroids")
	
	# Cache component references
	health_component = $HealthComponent
	_sprite = $Sprite2D
	_explosion_component = $ExplodeDebrisComponent if has_node("ExplodeDebrisComponent") else null
	
	# Direct singleton access is more efficient
	audio_manager = Engine.get_singleton("AudioManager")
	
	# Set health based on size
	if health_component:
		health_component.max_health = _health_values.get(size_category, 50.0)
		health_component.current_health = health_component.max_health
		health_component.connect("died", _on_destroyed)
	
	# Apply visual settings
	if _sprite:
		_sprite.scale = Vector2(base_scale, base_scale)
		_sprite.rotation = randf() * TAU  # Initial random rotation
	
	# Precalculate collision rect
	_update_collision_rect()
	
	# Only enable process if actually rotating
	set_process(rotation_speed != 0)

# Only called if rotation_speed != 0
func _process(delta: float) -> void:
	if _sprite:
		_sprite.rotation += rotation_speed * delta

# Setup with all needed values at once
func setup(size: String, variant: int, scale_value: float, rot_speed: float, initial_rot: float = 0.0) -> void:
	size_category = size
	base_scale = scale_value
	rotation_speed = rot_speed
	
	if _sprite:
		_sprite.scale = Vector2(scale_value, scale_value)
		_sprite.rotation = initial_rot
	
	# Update health based on size
	if health_component:
		health_component.max_health = _health_values.get(size, 50.0)
		health_component.current_health = health_component.max_health
	
	# Precalculate collision rectangle
	_update_collision_rect()
	
	# Only enable process if actually rotating
	set_process(rot_speed != 0)

# Precalculate collision rectangle once
func _update_collision_rect() -> void:
	if _sprite and _sprite.texture:
		var texture_size = _sprite.texture.get_size()
		var scaled_size = texture_size * _sprite.scale
		_collision_rect = Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	else:
		# Fallback to size-based rect
		var size = 10 * (1 if size_category == "small" else (2 if size_category == "medium" else 3))
		_collision_rect = Rect2(-size/2, -size/2, size, size)

# Delegate to health component with optional source
func take_damage(amount: float, source = null) -> bool:
	if health_component:
		return health_component.apply_damage(amount, "impact", source)
	return false

# Optimized collision check using precalculated rect
func check_laser_hit(laser) -> bool:
	# Update global rect only when checking collision
	_collision_rect_global = _collision_rect
	_collision_rect_global.position += global_position
	return _collision_rect_global.has_point(laser.global_position)

func get_collision_rect() -> Rect2:
	return _collision_rect

# Explosion and destruction handling
func _on_destroyed() -> void:
	# Use cached explosion component if available
	if _explosion_component and _explosion_component.has_method("explode"):
		_explosion_component.explode()
	else:
		_create_explosion()
		
		if audio_manager:
			audio_manager.play_sfx("explosion", global_position)
		
		# Only get asteroid spawner if needed - direct path access
		var asteroid_spawner = get_node_or_null("/root/Main/AsteroidSpawner")
		if asteroid_spawner:
			asteroid_spawner._spawn_fragments(
				global_position,
				size_category,
				2,
				base_scale
			)
	
	queue_free()

# Create explosion effect
func _create_explosion() -> void:
	# Only check if path exists once
	if ResourceLoader.exists(EXPLOSION_SCENE_PATH):
		var explosion_scene = load(EXPLOSION_SCENE_PATH)
		var explosion = explosion_scene.instantiate()
		explosion.global_position = global_position
		
		# Size scale based on asteroid size
		var explosion_scale = 0.5
		match size_category:
			"medium": explosion_scale = 1.0
			"large": explosion_scale = 1.5
		
		explosion.scale = Vector2(explosion_scale, explosion_scale)
		get_tree().current_scene.add_child(explosion)
	else:
		# Fallback particles - optimized setup
		var particles = CPUParticles2D.new()
		
		# Configure particles with efficient property setup
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
		
		# Auto cleanup with timer
		get_tree().current_scene.add_child(particles)
		get_tree().create_timer(0.8).timeout.connect(particles.queue_free)
