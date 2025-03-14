# scripts/components/explode_debris_component.gd
extends Component
class_name ExplodeDebrisComponent

signal explosion_started
signal explosion_completed

# Explosion configuration
@export var explosion_size: String = "medium"  # small, medium, large
@export var explosion_scale: float = 1.0
@export var explosion_offset: Vector2 = Vector2.ZERO
@export var debris_count: int = 10
@export var debris_velocity_min: float = 50.0
@export var debris_velocity_max: float = 150.0
@export var debris_size_min: float = 0.2
@export var debris_size_max: float = 0.8
@export var debris_lifetime: float = 1.5

# Audio configuration
@export var explosion_sound: String = "explosion_fire"
@export var debris_sound: String = "explosion_debris"
@export var audio_volume_db: float = 0.0
@export var audio_pitch_range: Vector2 = Vector2(0.9, 1.1)

# References
var _audio_manager = null
var _effect_pool_manager = null

# Legacy fallback paths - only used if pool manager unavailable
@export_file("*.tscn") var explosion_scene_path: String = ""
@export_file("*.tscn") var debris_scene_path: String = ""

func _ready() -> void:
	super._ready()
	
	# Get manager references
	_audio_manager = get_node_or_null("/root/AudioManager")
	_effect_pool_manager = get_node_or_null("/root/EffectPoolManager")

# Start explosion effect
func explode() -> void:
	if not enabled:
		return
	
	# Use the effect pool if available
	if _effect_pool_manager:
		_create_explosion_from_pool()
	else:
		# Fallback to direct instantiation
		_create_explosion_direct()
	
	# Play explosion sound
	_play_explosion_sound()
	
	# Emit signal
	explosion_started.emit()
	
	# Schedule completion signal after a delay
	get_tree().create_timer(0.5).timeout.connect(
		func(): explosion_completed.emit()
	)

# Create explosion using effect pool
func _create_explosion_from_pool() -> void:
	var explosion_position = get_parent().global_position + explosion_offset
	var rotation = get_parent().rotation if "rotation" in get_parent() else 0.0
	
	# Spawn main explosion effect
	_effect_pool_manager.explosion(explosion_position, explosion_size, rotation, explosion_scale)
	
	# Spawn debris effects
	for i in range(debris_count):
		var angle = randf() * TAU
		var distance = randf_range(5.0, 15.0)
		var debris_pos = explosion_position + Vector2(cos(angle), sin(angle)) * distance
		
		var debris_scale = randf_range(debris_size_min, debris_size_max)
		var debris_rotation = randf() * TAU
		
		_effect_pool_manager.play_effect("impact_effect", debris_pos, debris_rotation, debris_scale)

# Fallback direct explosion creation
func _create_explosion_direct() -> void:
	var explosion_position = get_parent().global_position + explosion_offset
	
	# Create main explosion if scene path is valid
	if not explosion_scene_path.is_empty() and ResourceLoader.exists(explosion_scene_path):
		var explosion_scene = load(explosion_scene_path)
		var explosion = explosion_scene.instantiate()
		
		# Add to scene tree
		get_tree().current_scene.add_child(explosion)
		
		# Position and configure
		explosion.global_position = explosion_position
		
		# Scale based on size
		var size_scale = 1.0
		match explosion_size:
			"small": size_scale = 0.7
			"medium": size_scale = 1.0
			"large": size_scale = 1.5
		
		if "scale" in explosion:
			explosion.scale = Vector2(size_scale, size_scale) * explosion_scale
		
		# Auto-cleanup for one-shot effects
		if explosion is CPUParticles2D or explosion is GPUParticles2D:
			explosion.emitting = true
			explosion.one_shot = true
			
			# Calculate max lifetime
			var max_lifetime = explosion.lifetime
			if explosion is CPUParticles2D and explosion.lifetime_randomness > 0:
				max_lifetime *= (1.0 + explosion.lifetime_randomness)
			
			get_tree().create_timer(max_lifetime + 0.1).timeout.connect(explosion.queue_free)
		elif explosion.has_method("play"):
			explosion.play()
			
			if explosion.has_signal("animation_finished"):
				explosion.animation_finished.connect(explosion.queue_free)
			else:
				get_tree().create_timer(1.0).timeout.connect(explosion.queue_free)
	
	# Create debris
	_create_debris_direct(explosion_position)

# Create debris particles directly
func _create_debris_direct(position: Vector2) -> void:
	# Skip if no debris scene
	if debris_scene_path.is_empty() or not ResourceLoader.exists(debris_scene_path):
		_create_fallback_debris(position)
		return
	
	# Load debris scene
	var debris_scene = load(debris_scene_path)
	
	# Create debris particles
	for i in range(debris_count):
		var debris = debris_scene.instantiate()
		
		# Add to scene tree
		get_tree().current_scene.add_child(debris)
		
		# Configure
		var angle = randf() * TAU
		var distance = randf_range(5.0, 15.0)
		debris.global_position = position + Vector2(cos(angle), sin(angle)) * distance
		
		# Apply velocity if rigid body
		if debris is RigidBody2D:
			var velocity = Vector2(cos(angle), sin(angle)) * randf_range(debris_velocity_min, debris_velocity_max)
			debris.linear_velocity = velocity
			debris.angular_velocity = randf_range(-5.0, 5.0)
		
		# Scale
		if "scale" in debris:
			var scale_value = randf_range(debris_size_min, debris_size_max)
			debris.scale = Vector2(scale_value, scale_value)
		
		# Auto-cleanup
		get_tree().create_timer(debris_lifetime).timeout.connect(debris.queue_free)

# Create simple fallback debris if no scene is available
func _create_fallback_debris(position: Vector2) -> void:
	for i in range(debris_count):
		var particles = CPUParticles2D.new()
		
		# Add to scene tree
		get_tree().current_scene.add_child(particles)
		
		# Configure particles
		var angle = randf() * TAU
		var distance = randf_range(5.0, 15.0)
		particles.global_position = position + Vector2(cos(angle), sin(angle)) * distance
		
		particles.emitting = true
		particles.one_shot = true
		particles.explosiveness = 0.8
		particles.amount = 5
		particles.lifetime = debris_lifetime
		particles.direction = Vector2(cos(angle), sin(angle))
		particles.spread = 30
		particles.gravity = Vector2.ZERO
		particles.initial_velocity_min = debris_velocity_min
		particles.initial_velocity_max = debris_velocity_max
		
		# Scale
		var scale_value = randf_range(debris_size_min, debris_size_max)
		particles.scale_amount = scale_value
		
		# Color
		particles.color = Color(0.8, 0.5, 0.2)
		
		# Auto-cleanup
		get_tree().create_timer(debris_lifetime + 0.1).timeout.connect(particles.queue_free)

# Play explosion sound
func _play_explosion_sound() -> void:
	if _audio_manager:
		var pitch = randf_range(audio_pitch_range.x, audio_pitch_range.y)
		
		# Play main explosion sound
		if not explosion_sound.is_empty():
			_audio_manager.play_sfx(explosion_sound, get_parent().global_position, pitch, audio_volume_db)
		
		# Play debris sound
		if not debris_sound.is_empty():
			_audio_manager.play_sfx(debris_sound, get_parent().global_position, pitch * 0.9, audio_volume_db - 3.0)
