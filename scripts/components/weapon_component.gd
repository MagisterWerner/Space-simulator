# scripts/components/weapon_component.gd
extends Component
class_name WeaponComponent

signal weapon_fired(position, direction)

# Weapon configuration
@export var weapon_name: String = "Generic Weapon"
@export var fire_rate: float = 0.5  # Seconds between shots
@export var damage: float = 10.0
@export var energy_cost: float = 5.0
@export var projectile_speed: float = 500.0

# Projectile configuration
@export var projectile_type: String = "laser"
@export_file("*.tscn") var projectile_scene_path: String = ""

# Audio configuration
@export var fire_sound: String = "laser"
@export var audio_volume_db: float = 0.0
@export var audio_pitch: float = 1.0

# Component references
@export var muzzle_path: NodePath
@onready var muzzle = get_node_or_null(muzzle_path)

# Internal state
var _fire_timer: float = 0.0
var _can_fire: bool = true
var _base_fire_rate: float
var _base_damage: float
var _base_projectile_speed: float

# Manager references - cached
var _audio_manager = null
var _projectile_pool_manager = null

func _ready() -> void:
	super._ready()
	
	# Store base values for strategy modifications
	_base_fire_rate = fire_rate
	_base_damage = damage
	_base_projectile_speed = projectile_speed
	
	# Get manager references
	_audio_manager = get_node_or_null("/root/AudioManager")
	_projectile_pool_manager = get_node_or_null("/root/ProjectilePoolManager")

func _process(delta: float) -> void:
	# Update fire timer
	if not _can_fire:
		_fire_timer -= delta
		if _fire_timer <= 0:
			_can_fire = true

# Fire the weapon
func fire() -> bool:
	if not enabled or not _can_fire:
		return false
	
	# Reset fire timer
	_can_fire = false
	_fire_timer = fire_rate
	
	# Use projectile pool manager if available
	if _projectile_pool_manager:
		_spawn_projectile_from_pool()
	else:
		# Fallback to direct instantiation
		_spawn_projectile_direct()
	
	# Play fire sound
	_play_fire_sound()
	
	# Emit signal
	var direction = Vector2.UP.rotated(get_parent().rotation)
	weapon_fired.emit(get_fire_position(), direction)
	
	return true

# Spawn projectile using pool manager
func _spawn_projectile_from_pool() -> void:
	var spawn_position = get_fire_position()
	var direction = Vector2.UP.rotated(get_parent().rotation)
	
	# Get projectile from pool
	_projectile_pool_manager.get_projectile(
		projectile_type,
		spawn_position,
		direction,
		get_parent()
	)

# Fallback direct projectile spawning
func _spawn_projectile_direct() -> void:
	if projectile_scene_path.is_empty():
		return
		
	# Load scene if it exists
	if not ResourceLoader.exists(projectile_scene_path):
		push_error("WeaponComponent: Projectile scene not found: " + projectile_scene_path)
		return
	
	# Spawn projectile
	var projectile_scene = load(projectile_scene_path)
	var projectile = projectile_scene.instantiate()
	
	# Add to scene tree
	get_tree().current_scene.add_child(projectile)
	
	# Position and configure
	projectile.global_position = get_fire_position()
	
	# Set direction and speed
	var direction = Vector2.UP.rotated(get_parent().rotation)
	
	# Configure projectile if it has appropriate methods
	if projectile.has_method("set_damage"):
		projectile.set_damage(damage)
	
	if projectile.has_method("set_speed"):
		projectile.set_speed(projectile_speed)
	
	if projectile.has_method("fire"):
		projectile.fire(direction, get_parent())
	else:
		# Basic fallback for RigidBody2D projectiles
		if projectile is RigidBody2D:
			projectile.linear_velocity = direction * projectile_speed
		
		# Add source information via metadata
		projectile.set_meta("source", get_parent())
		projectile.set_meta("damage", damage)

# Get fire position
func get_fire_position() -> Vector2:
	if muzzle:
		return muzzle.global_position
	return get_parent().global_position

# Play fire sound
func _play_fire_sound() -> void:
	if _audio_manager and not fire_sound.is_empty():
		_audio_manager.play_sfx(
			fire_sound,
			get_fire_position(),
			audio_pitch,
			audio_volume_db
		)

# Apply modification from strategy
func apply_strategy_mod(property: String, value: float) -> void:
	match property:
		"fire_rate":
			fire_rate = _base_fire_rate * value
		"damage":
			damage = _base_damage * value
		"projectile_speed":
			projectile_speed = _base_projectile_speed * value

# Reset to base values
func reset_to_base_values() -> void:
	fire_rate = _base_fire_rate
	damage = _base_damage
	projectile_speed = _base_projectile_speed
