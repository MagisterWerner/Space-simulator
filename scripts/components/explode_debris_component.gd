# scripts/components/explode_debris_component.gd
extends Node
class_name ExplodeDebrisComponent

signal exploded
signal debris_finished

@export var explosion_size_factor: float = 1.0
@export var debris_count: int = 10
@export var debris_lifetime: float = 1.0
@export var debris_colors: Array[Color] = [
	Color(0.8, 0.5, 0.2),
	Color(0.6, 0.3, 0.1),
	Color(0.4, 0.2, 0.1)
]

# Explosion scene reference - if null, will create dynamic particles
@export var explosion_scene_path: String = ""
var _explosion_scene: PackedScene = null
var _explosion_active: bool = false
var _explosion_timer: float = 0.0

func _ready() -> void:
	# Preload explosion scene if specified
	if explosion_scene_path.length() > 0 and ResourceLoader.exists(explosion_scene_path):
		_explosion_scene = load(explosion_scene_path)

func _process(delta: float) -> void:
	if _explosion_active:
		_explosion_timer -= delta
		if _explosion_timer <= 0:
			_explosion_active = false
			debris_finished.emit()

func explode() -> void:
	var parent = get_parent()
	var position = parent.global_position if parent else Vector2.ZERO
	var scale_factor = explosion_size_factor
	
	# Try to get size from asteroid if available
	if parent.has_method("get_collision_rect"):
		var rect = parent.get_collision_rect()
		scale_factor = max(rect.size.x, rect.size.y) / 32.0 * explosion_size_factor
	
	if _explosion_scene:
		_spawn_explosion_scene(position, scale_factor)
	else:
		_create_dynamic_explosion(position, scale_factor)
	
	# Play explosion sound if AudioManager is available
	if Engine.has_singleton("AudioManager"):
		AudioManager.play_sfx("explosion_debris", position)
	
	exploded.emit()

func _spawn_explosion_scene(position: Vector2, scale_factor: float) -> void:
	var explosion = _explosion_scene.instantiate()
	get_tree().current_scene.add_child(explosion)
	explosion.global_position = position
	
	if explosion.has("scale"):
		explosion.scale = Vector2(scale_factor, scale_factor)
	
	# Set timer for explosion duration
	_explosion_active = true
	_explosion_timer = 1.0

func _create_dynamic_explosion(position: Vector2, scale_factor: float) -> void:
	# Create particles for debris
	var particles = CPUParticles2D.new()
	
	# Configure particles
	particles.emitting = true
	particles.one_shot = true
	particles.explosiveness = 1.0
	particles.amount = debris_count
	particles.lifetime = debris_lifetime
	particles.position = position
	particles.direction = Vector2.ZERO
	particles.spread = 180.0
	particles.gravity = Vector2.ZERO
	particles.initial_velocity_min = 100.0 * scale_factor
	particles.initial_velocity_max = 150.0 * scale_factor
	particles.scale_amount_min = 2.0 * scale_factor
	particles.scale_amount_max = 4.0 * scale_factor
	particles.color_ramp = _create_debris_gradient()
	
	# Add to scene and set to auto-clean
	get_tree().current_scene.add_child(particles)
	
	# Set up timer for tracking debris lifetime
	_explosion_active = true
	_explosion_timer = debris_lifetime + 0.1
	
	# Auto cleanup with timer
	get_tree().create_timer(debris_lifetime + 0.2).timeout.connect(particles.queue_free)

func _create_debris_gradient() -> Gradient:
	var gradient = Gradient.new()
	
	# Add colors from debris_colors array or use defaults
	var colors = debris_colors
	if colors.is_empty():
		colors = [
			Color(0.8, 0.5, 0.2),
			Color(0.6, 0.3, 0.1),
			Color(0.4, 0.2, 0.1)
		]
	
	# Add points
	gradient.add_point(0.0, colors[0])
	if colors.size() > 1:
		gradient.add_point(0.5, colors[1])
	if colors.size() > 2:
		gradient.add_point(0.8, colors[2])
	gradient.add_point(1.0, Color(colors[-1].r, colors[-1].g, colors[-1].b, 0.0))
	
	return gradient
