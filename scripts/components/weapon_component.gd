# scripts/components/weapon_component.gd
# Component that handles weapon functionality including firing, ammo, and overheating mechanics
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
@export var fire_rate: float = 1.0  # Shots per second
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
@export var cooling_rate: float = 15.0  # Per second
@export var overheat_cooldown_time: float = 3.0  # Forced cooldown time when overheated

@export_category("Positioning")
@export var muzzle_path: NodePath

@export_category("Audio")
@export var enable_audio: bool = true
@export var fire_sound_name: String = "laser"
@export var reload_sound_name: String = "reload"
@export var empty_sound_name: String = "empty"
@export var overheat_sound_name: String = "overheat"

var _current_heat: float = 0.0
var _can_fire: bool = true
var _is_reloading: bool = false
var _is_overheated: bool = false
var _last_fire_time: float = 0.0
var _overheated_time: float = 0.0
var _weapon_strategies: Array = []
var _muzzle_node: Node = null
var _audio_manager = null

func setup() -> void:
	_current_heat = 0.0
	
	if not muzzle_path.is_empty():
		_muzzle_node = get_node(muzzle_path)
	else:
		# Default to the weapon component itself
		_muzzle_node = self
	
	if current_ammo > max_ammo:
		current_ammo = max_ammo
	
	ammo_changed.emit(current_ammo, max_ammo)
	
	# Get a direct reference to AudioManager at setup time
	_audio_manager = _get_audio_manager()
	
	# Initialize audio with a slight delay to ensure AudioManager is ready
	call_deferred("_initialize_audio")

func _get_audio_manager():
	# Try multiple approaches to get the AudioManager
	var audio_mgr = null
	
	# First try getting it as an autoload from the root
	if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("AudioManager"):
		audio_mgr = Engine.get_main_loop().root.get_node("AudioManager")
		debug_print("Found AudioManager via root node")
		return audio_mgr
	
	# Try the simpler approach if the previous didn't work
	audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr:
		debug_print("Found AudioManager via direct path")
		return audio_mgr
	
	# Manually load the script if all else fails
	var script = load("res://autoload/audio_manager.gd")
	if script:
		audio_mgr = script.new()
		debug_print("Created AudioManager instance manually")
		return audio_mgr
	
	push_warning("WeaponComponent: AudioManager not found")
	return null

func _initialize_audio() -> void:
	if not enable_audio:
		return
	
	if _audio_manager == null:
		_audio_manager = _get_audio_manager()
		if _audio_manager == null:
			push_warning("WeaponComponent: AudioManager still not available after deferred initialization")
			return
	
	debug_print("Initializing audio with manager: " + str(_audio_manager))
	
	# Preload sounds if using AudioManager
	if _audio_manager.has_method("is_sfx_loaded") and not _audio_manager.is_sfx_loaded(fire_sound_name):
		var sound_path = "res://assets/audio/laser.sfxr"
		if ResourceLoader.exists(sound_path):
			_audio_manager.preload_sfx(fire_sound_name, sound_path, 10)
			debug_print("Preloaded laser sound from: " + sound_path)
		else:
			push_warning("WeaponComponent: Laser sound file not found: " + sound_path)
	
	if reload_sound_name and _audio_manager.has_method("is_sfx_loaded") and not _audio_manager.is_sfx_loaded(reload_sound_name):
		var reload_path = "res://assets/audio/reload.sfxr"
		if ResourceLoader.exists(reload_path):
			_audio_manager.preload_sfx(reload_sound_name, reload_path, 2)
	
	if empty_sound_name and _audio_manager.has_method("is_sfx_loaded") and not _audio_manager.is_sfx_loaded(empty_sound_name):
		var empty_path = "res://assets/audio/empty.sfxr"
		if ResourceLoader.exists(empty_path):
			_audio_manager.preload_sfx(empty_sound_name, empty_path, 2)
		
	if overheat_sound_name and _audio_manager.has_method("is_sfx_loaded") and not _audio_manager.is_sfx_loaded(overheat_sound_name):
		var overheat_path = "res://assets/audio/overheat.sfxr"
		if ResourceLoader.exists(overheat_path):
			_audio_manager.preload_sfx(overheat_sound_name, overheat_path, 2)

func can_fire() -> bool:
	if not enabled or _is_overheated:
		return false
		
	if not unlimited_ammo and current_ammo <= 0:
		if auto_reload and not _is_reloading:
			start_reload()
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	var time_since_last_fire = current_time - _last_fire_time
	
	return _can_fire and time_since_last_fire >= (1.0 / fire_rate)

func fire() -> bool:
	if not can_fire():
		# Play empty click sound if we're out of ammo
		if enable_audio and not unlimited_ammo and current_ammo <= 0 and empty_sound_name:
			_play_empty_sound()
		return false
	
	var current_time = Time.get_ticks_msec() / 1000.0
	_last_fire_time = current_time
	
	# Create projectile instance
	var projectile_instance = projectile_scene.instantiate()
	var world = owner_entity.get_parent()
	world.add_child(projectile_instance)
	
	# Set projectile properties - Safely handle positions and rotations
	var spawn_pos = Vector2.ZERO
	var spawn_rot = 0.0
	
	# Check if muzzle node has global_position (is Node2D)
	if _muzzle_node is Node2D:
		spawn_pos = _muzzle_node.global_position
		spawn_rot = _muzzle_node.global_rotation
	else:
		# Fallback to owner_entity's position and rotation if available
		if owner_entity is Node2D:
			spawn_pos = owner_entity.global_position
			spawn_rot = owner_entity.global_rotation
	
	projectile_instance.global_position = spawn_pos
	projectile_instance.global_rotation = spawn_rot
	
	# Apply modifiers from strategies
	var modified_damage = damage
	var modified_speed = projectile_speed
	var modified_lifespan = projectile_lifespan
	
	for strategy in _weapon_strategies:
		if strategy.has_method("modify_projectile_damage"):
			modified_damage = strategy.modify_projectile_damage(modified_damage)
		if strategy.has_method("modify_projectile_speed"):
			modified_speed = strategy.modify_projectile_speed(modified_speed)
		if strategy.has_method("modify_projectile_lifespan"):
			modified_lifespan = strategy.modify_projectile_lifespan(modified_lifespan)
	
	# Configure the projectile
	if projectile_instance.has_method("set_damage"):
		projectile_instance.set_damage(modified_damage)
	
	if projectile_instance.has_method("set_speed"):
		projectile_instance.set_speed(modified_speed)
	
	if projectile_instance.has_method("set_lifespan"):
		projectile_instance.set_lifespan(modified_lifespan)
	
	# Mark the shooter to prevent self-damage
	if projectile_instance.has_method("set_shooter"):
		projectile_instance.set_shooter(owner_entity)
	
	# Use strategies for special projectile behaviors
	for strategy in _weapon_strategies:
		if strategy.has_method("modify_projectile"):
			strategy.modify_projectile(projectile_instance)
	
	# Play firing sound
	if enable_audio:
		_play_fire_sound(spawn_pos)
	
	# Consume ammo
	if not unlimited_ammo:
		current_ammo -= 1
		ammo_changed.emit(current_ammo, max_ammo)
	
	# Handle heat
	if can_overheat:
		_current_heat += heat_per_shot
		if _current_heat >= max_heat:
			_overheat()
	
	weapon_fired.emit(projectile_instance)
	debug_print("Fired weapon")
	
	# Check for auto-reload
	if not unlimited_ammo and current_ammo <= 0 and auto_reload:
		start_reload()
	
	return true

func start_reload() -> void:
	if _is_reloading or unlimited_ammo or current_ammo == max_ammo:
		return
		
	_is_reloading = true
	_can_fire = false
	
	# Play reload sound
	if enable_audio and reload_sound_name:
		_play_reload_sound()
	
	# Create a timer for reload
	var timer = get_tree().create_timer(reload_time)
	timer.timeout.connect(_on_reload_complete)
	
	debug_print("Started reloading")

func _on_reload_complete() -> void:
	current_ammo = max_ammo
	_is_reloading = false
	_can_fire = true
	weapon_reloaded.emit()
	ammo_changed.emit(current_ammo, max_ammo)
	debug_print("Reload complete")

func _overheat() -> void:
	_is_overheated = true
	_can_fire = false
	_overheated_time = Time.get_ticks_msec() / 1000.0
	
	# Play overheat sound
	if enable_audio and overheat_sound_name:
		_play_overheat_sound()
		
	weapon_overheated.emit()
	debug_print("Weapon overheated")

func _cool_down() -> void:
	_is_overheated = false
	_can_fire = true
	_current_heat = 0.0
	weapon_cooled.emit()
	debug_print("Weapon cooled down")

func process_component(delta: float) -> void:
	# Handle cooling
	if can_overheat and _current_heat > 0:
		var current_time = Time.get_ticks_msec() / 1000.0
		
		if _is_overheated:
			if current_time - _overheated_time >= overheat_cooldown_time:
				_cool_down()
		else:
			_current_heat = max(0.0, _current_heat - (cooling_rate * delta))

# Audio methods
func _play_fire_sound(position: Vector2) -> void:
	if not enable_audio or _audio_manager == null:
		return
	
	if _audio_manager.has_method("play_sfx"):
		# Randomize pitch slightly for variety
		var pitch_variation = randf_range(0.95, 1.05)
		_audio_manager.play_sfx(fire_sound_name, position, pitch_variation)
	else:
		debug_print("AudioManager found but play_sfx method not available")

func _play_reload_sound() -> void:
	if not enable_audio or _audio_manager == null or not reload_sound_name:
		return
		
	var position = owner_entity.global_position if owner_entity is Node2D else Vector2.ZERO
	
	if _audio_manager.has_method("play_sfx"):
		_audio_manager.play_sfx(reload_sound_name, position)

func _play_empty_sound() -> void:
	if not enable_audio or _audio_manager == null or not empty_sound_name:
		return
		
	var position = owner_entity.global_position if owner_entity is Node2D else Vector2.ZERO
	
	if _audio_manager.has_method("play_sfx"):
		_audio_manager.play_sfx(empty_sound_name, position)

func _play_overheat_sound() -> void:
	if not enable_audio or _audio_manager == null or not overheat_sound_name:
		return
		
	var position = owner_entity.global_position if owner_entity is Node2D else Vector2.ZERO
	
	if _audio_manager.has_method("play_sfx"):
		_audio_manager.play_sfx(overheat_sound_name, position)

# Strategy management
func add_weapon_strategy(strategy) -> void:
	if not _weapon_strategies.has(strategy):
		_weapon_strategies.append(strategy)
		
func remove_weapon_strategy(strategy) -> void:
	_weapon_strategies.erase(strategy)

func get_heat_percent() -> float:
	if max_heat <= 0:
		return 0.0
	return _current_heat / max_heat
