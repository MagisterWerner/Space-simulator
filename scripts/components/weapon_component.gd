# weapon_component.gd
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

var _current_heat: float = 0.0
var _can_fire: bool = true
var _is_reloading: bool = false
var _is_overheated: bool = false
var _last_fire_time: float = 0.0
var _overheated_time: float = 0.0
var _weapon_strategies: Array = []
var _muzzle_node: Node = null  # Changed from Node2D to Node

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

func add_weapon_strategy(strategy) -> void:
	if not _weapon_strategies.has(strategy):
		_weapon_strategies.append(strategy)
		
func remove_weapon_strategy(strategy) -> void:
	_weapon_strategies.erase(strategy)

func get_heat_percent() -> float:
	if max_heat <= 0:
		return 0.0
	return _current_heat / max_heat
