# scripts/components/weapon_component.gd - Optimized implementation
extends Component
class_name WeaponComponent

signal weapon_fired(projectile)
signal weapon_reloaded
signal ammo_changed(current, maximum)
signal weapon_overheated
signal weapon_cooled

@export_category("Weapon Properties")
@export var weapon_name: String = "Laser"
@export var damage: float = 10.0
@export var fire_rate: float = 1.0
@export var projectile_speed: float = 500.0
@export var projectile_scene: PackedScene
@export var projectile_lifespan: float = 2.0

@export_category("Ammo")
@export var unlimited_ammo: bool = true
@export var max_ammo: int = 100
@export var current_ammo: int = 100
@export var reload_time: float = 1.5
@export var auto_reload: bool = true

@export_category("Overheating")
@export var can_overheat: bool = false
@export var heat_per_shot: float = 10.0
@export var max_heat: float = 100.0
@export var cooling_rate: float = 15.0
@export var overheat_cooldown_time: float = 3.0

@export_category("Positioning")
@export var muzzle_path: NodePath

@export_category("Audio")
@export var enable_audio: bool = true
@export var fire_sound_name: String = "laser"
@export var reload_sound_name: String = "reload"
@export var empty_sound_name: String = "empty"
@export var overheat_sound_name: String = "overheat"

# Internal state
var _current_heat: float = 0.0
var _can_fire: bool = true
var _is_reloading: bool = false
var _is_overheated: bool = false
var _last_fire_time: float = 0.0
var _overheated_time: float = 0.0
var _weapon_strategies: Array = []
var _muzzle_node: Node = null
var _audio_manager = null
var _heat_percent: float = 0.0  # Cached heat percentage
var _reload_timer: SceneTreeTimer = null
var _fire_interval: float = 1.0  # Cached firing interval

func setup() -> void:
	_current_heat = 0.0
	_heat_percent = 0.0
	_fire_interval = 1.0 / max(0.1, fire_rate)  # Avoid division by zero
	
	# Get muzzle node
	if not muzzle_path.is_empty():
		_muzzle_node = get_node_or_null(muzzle_path)
	
	# Fallback to self if not found
	if _muzzle_node == null:
		_muzzle_node = self
	
	# Clamp ammo
	current_ammo = min(current_ammo, max_ammo)
	ammo_changed.emit(current_ammo, max_ammo)
	
	# Setup audio
	if enable_audio:
		_audio_manager = get_node_or_null("/root/AudioManager")
		if _audio_manager == null:
			enable_audio = false
			push_warning("WeaponComponent: AudioManager not found, disabling audio")

func can_fire() -> bool:
	if not enabled or _is_overheated:
		return false
		
	if not unlimited_ammo and current_ammo <= 0:
		if auto_reload and not _is_reloading:
			start_reload()
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	return _can_fire and (current_time - _last_fire_time) >= _fire_interval

func fire() -> bool:
	if not can_fire():
		# Play empty click sound if we're out of ammo
		if enable_audio and not unlimited_ammo and current_ammo <= 0 and empty_sound_name:
			_play_sound(empty_sound_name)
		return false
	
	_last_fire_time = Time.get_ticks_msec() / 1000.0
	
	# Create and setup projectile
	var projectile = _create_projectile()
	if projectile == null:
		return false
	
	# Play firing sound
	if enable_audio:
		_play_sound(fire_sound_name, randf_range(0.95, 1.05))
	
	# Consume ammo
	if not unlimited_ammo:
		current_ammo -= 1
		ammo_changed.emit(current_ammo, max_ammo)
	
	# Handle heat
	if can_overheat:
		_current_heat += heat_per_shot
		_heat_percent = _current_heat / max_heat
		
		if _current_heat >= max_heat:
			_overheat()
	
	weapon_fired.emit(projectile)
	
	if debug_mode:
		_debug_print("Fired weapon")
	
	# Check for auto-reload
	if not unlimited_ammo and current_ammo <= 0 and auto_reload:
		start_reload()
	
	return true

func _create_projectile():
	if projectile_scene == null:
		return null
		
	var world = owner_entity.get_parent()
	if world == null:
		return null
		
	# Create projectile instance
	var projectile = projectile_scene.instantiate()
	world.add_child(projectile)
	
	# Set projectile properties
	var spawn_pos = Vector2.ZERO
	var spawn_rot = 0.0
	
	# Get position and rotation from muzzle or owner
	if _muzzle_node is Node2D:
		spawn_pos = _muzzle_node.global_position
		spawn_rot = _muzzle_node.global_rotation
	elif owner_entity is Node2D:
		spawn_pos = owner_entity.global_position
		spawn_rot = owner_entity.global_rotation
	
	projectile.global_position = spawn_pos
	projectile.global_rotation = spawn_rot
	
	# Apply modifiers from strategies
	var modified_damage = damage
	var modified_speed = projectile_speed
	var modified_lifespan = projectile_lifespan
	
	if not _weapon_strategies.is_empty():
		for strategy in _weapon_strategies:
			if strategy.has_method("modify_projectile_damage"):
				modified_damage = strategy.modify_projectile_damage(modified_damage)
			if strategy.has_method("modify_projectile_speed"):
				modified_speed = strategy.modify_projectile_speed(modified_speed)
			if strategy.has_method("modify_projectile_lifespan"):
				modified_lifespan = strategy.modify_projectile_lifespan(modified_lifespan)
	
	# Configure the projectile using method calls if available
	if projectile.has_method("set_damage"):
		projectile.set_damage(modified_damage)
	
	if projectile.has_method("set_speed"):
		projectile.set_speed(modified_speed)
	
	if projectile.has_method("set_lifespan"):
		projectile.set_lifespan(modified_lifespan)
	
	# Mark the shooter to prevent self-damage
	if projectile.has_method("set_shooter"):
		projectile.set_shooter(owner_entity)
	
	# Apply special projectile behaviors
	if not _weapon_strategies.is_empty():
		for strategy in _weapon_strategies:
			if strategy.has_method("modify_projectile"):
				strategy.modify_projectile(projectile)
				
	return projectile

func start_reload() -> void:
	if _is_reloading or unlimited_ammo or current_ammo == max_ammo:
		return
		
	_is_reloading = true
	_can_fire = false
	
	# Play reload sound
	if enable_audio and reload_sound_name:
		_play_sound(reload_sound_name)
	
	# Cancel existing timer if any
	if _reload_timer != null and _reload_timer.time_left > 0:
		# Can't cancel timers in Godot 4, let it run out
		pass
	
	# Create a timer for reload
	_reload_timer = get_tree().create_timer(reload_time)
	_reload_timer.timeout.connect(_on_reload_complete)
	
	if debug_mode:
		_debug_print("Started reloading")

func _on_reload_complete() -> void:
	current_ammo = max_ammo
	_is_reloading = false
	_can_fire = true
	weapon_reloaded.emit()
	ammo_changed.emit(current_ammo, max_ammo)
	
	if debug_mode:
		_debug_print("Reload complete")

func _overheat() -> void:
	_is_overheated = true
	_can_fire = false
	_overheated_time = Time.get_ticks_msec() / 1000.0
	
	# Play overheat sound
	if enable_audio and overheat_sound_name:
		_play_sound(overheat_sound_name)
		
	weapon_overheated.emit()
	
	if debug_mode:
		_debug_print("Weapon overheated")

func _cool_down() -> void:
	_is_overheated = false
	_can_fire = true
	_current_heat = 0.0
	_heat_percent = 0.0
	weapon_cooled.emit()
	
	if debug_mode:
		_debug_print("Weapon cooled down")

func process_component(delta: float) -> void:
	# Skip processing if not needed
	if not can_overheat or _current_heat <= 0:
		return
		
	# Handle cooling
	var current_time = Time.get_ticks_msec() / 1000.0
	
	if _is_overheated:
		if current_time - _overheated_time >= overheat_cooldown_time:
			_cool_down()
	else:
		var old_heat = _current_heat
		_current_heat = max(0.0, _current_heat - (cooling_rate * delta))
		
		# Update heat percentage
		if old_heat != _current_heat:
			_heat_percent = _current_heat / max_heat

# Simplified audio method
func _play_sound(sound_name: String, pitch: float = 1.0) -> void:
	if not enable_audio or _audio_manager == null:
		return
	
	var position = Vector2.ZERO
	if owner_entity is Node2D:
		position = owner_entity.global_position
	
	_audio_manager.play_sfx(sound_name, position, pitch)

# Strategy management
func add_weapon_strategy(strategy) -> void:
	if not _weapon_strategies.has(strategy):
		_weapon_strategies.append(strategy)
		
func remove_weapon_strategy(strategy) -> void:
	_weapon_strategies.erase(strategy)

func get_heat_percent() -> float:
	return _heat_percent
