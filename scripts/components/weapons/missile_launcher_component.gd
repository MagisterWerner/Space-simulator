# scripts/components/weapons/missile_launcher_component.gd
extends WeaponComponent
class_name MissileLauncherComponent

# Missile launcher specific properties
@export_group("Missile Properties")
@export var explosion_radius: float = 100.0
@export var explosion_damage: float = 30.0
@export var missile_speed: float = 300.0
@export var missile_acceleration: float = 50.0
@export var missile_turn_rate: float = 2.0
@export var lock_on_time: float = 0.5
@export var lock_on_range: float = 800.0

# Ammunition settings
@export_group("Ammunition")
@export var missile_limit: int = 10
@export var reload_all: bool = false  # If true, reload all missiles at once instead of one by one

# Sound settings
@export_group("Missile Sounds")
@export var lock_on_sound: String = "lock_on"
@export var reload_sound: String = "missile_reload"

# State tracking
var target: Node2D = null
var lock_on_progress: float = 0.0
var _is_tracking: bool = false
var _last_target_check_time: float = 0.0
var _target_check_interval: float = 0.2
var _cached_nearest_entities = []

# Visual indicator for lock-on
var _lock_indicator: Node2D = null

func setup() -> void:
	super.setup()
	
	# Set default properties for a missile launcher
	weapon_name = "Missile Launcher"
	fire_rate = 1.0         # Slow fire rate
	damage = 50.0           # High damage
	projectile_speed = missile_speed
	projectile_lifespan = 5.0  # Long-lived projectile
	
	# Set ammunition settings
	unlimited_ammo = false
	max_ammo = missile_limit
	current_ammo = missile_limit
	reload_time = 2.0
	
	# If projectile scene is not set, load the missile projectile
	if not projectile_scene and ResourceLoader.exists("res://scenes/projectiles/missile_projectile.tscn"):
		projectile_scene = load("res://scenes/projectiles/missile_projectile.tscn")
	
	# Setup targeting indicator
	_setup_lock_indicator()

func _on_enable() -> void:
	super._on_enable()
	reset_lock_on()

func _on_disable() -> void:
	super._on_disable()
	reset_lock_on()
	
	if _lock_indicator:
		_lock_indicator.visible = false

func process_component(delta: float) -> void:
	super.process_component(delta)
	
	# Update target tracking
	_update_target_tracking(delta)
	
	# Update lock indicator
	_update_lock_indicator()

# Start tracking a target
func start_tracking() -> void:
	_is_tracking = true
	find_nearest_target()

# Stop tracking targets
func stop_tracking() -> void:
	_is_tracking = false
	reset_lock_on()

# Reset the lock-on state
func reset_lock_on() -> void:
	lock_on_progress = 0.0
	target = null
	
	if _lock_indicator:
		_lock_indicator.visible = false

# Find the nearest valid target
func find_nearest_target() -> void:
	# Only check periodically to improve performance
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_target_check_time < _target_check_interval:
		return
	
	_last_target_check_time = current_time
	
	# Get player position
	var own_position = Vector2.ZERO
	if owner_entity is Node2D:
		own_position = owner_entity.global_position
	
	# Try to use EntityManager if available
	if has_node("/root/EntityManager"):
		var entity_manager = get_node("/root/EntityManager")
		target = entity_manager.get_nearest_entity(own_position, "enemy", owner_entity)
	else:
		# Fallback - manually find nearest enemy
		var enemies = get_tree().get_nodes_in_group("enemy")
		var nearest_distance = lock_on_range
		var nearest_enemy = null
		
		for enemy in enemies:
			if enemy is Node2D and is_instance_valid(enemy):
				var distance = own_position.distance_to(enemy.global_position)
				if distance < nearest_distance:
					nearest_distance = distance
					nearest_enemy = enemy
		
		target = nearest_enemy

# Update target tracking
func _update_target_tracking(delta: float) -> void:
	if not _is_tracking:
		return
	
	# Check if target is still valid
	if not is_instance_valid(target) or (target is Node2D and owner_entity is Node2D and 
			target.global_position.distance_to(owner_entity.global_position) > lock_on_range):
		# Find a new target
		target = null
		lock_on_progress = 0.0
		find_nearest_target()
		return
	
	# Update lock-on progress
	if target:
		lock_on_progress = min(lock_on_time, lock_on_progress + delta)
		
		# Play lock-on sound when complete
		if lock_on_progress >= lock_on_time and enable_audio and _audio_manager and lock_on_sound:
			# Only play sound once when lock completes
			if lock_on_progress - delta < lock_on_time:
				_play_sound(lock_on_sound)

# Fire the missile
func fire() -> bool:
	# Require a locked-on target for firing
	if _is_tracking and target and lock_on_progress >= lock_on_time:
		var did_fire = super.fire()
		
		if did_fire:
			# Reset lock-on after firing
			lock_on_progress = 0.0
			
			# Keep the same target but restart lock-on process
			if _is_tracking:
				# Play lock on sound again
				if enable_audio and _audio_manager and lock_on_sound:
					_play_sound(lock_on_sound, 0.5)  # Lower pitch for restart
		
		return did_fire
	
	# No target locked, play empty sound
	if enable_audio and _audio_manager and empty_sound_name:
		_play_sound(empty_sound_name)
	
	return false

# Setup lock-on indicator
func _setup_lock_indicator() -> void:
	if not _lock_indicator and owner_entity is Node2D:
		_lock_indicator = Node2D.new()
		_lock_indicator.name = "LockIndicator"
		_lock_indicator.visible = false
		owner_entity.add_child(_lock_indicator)

# Update lock-on indicator
func _update_lock_indicator() -> void:
	if not _lock_indicator or not target or not _is_tracking:
		if _lock_indicator:
			_lock_indicator.visible = false
		return
	
	_lock_indicator.visible = true
	
	# Add custom drawing for indicator
	_lock_indicator.queue_redraw()

# Modify projectile at creation time
func _create_projectile() -> Node:
	var projectile = super._create_projectile()
	
	if projectile:
		# Set missile-specific properties
		if projectile.has_method("set_target"):
			projectile.set_target(target)
		
		if projectile.has_method("set_turn_rate"):
			projectile.set_turn_rate(missile_turn_rate)
		
		if projectile.has_method("set_acceleration"):
			projectile.set_acceleration(missile_acceleration)
		
		if projectile.has_method("set_explosion_radius"):
			projectile.set_explosion_radius(explosion_radius)
		
		if projectile.has_method("set_explosion_damage"):
			projectile.set_explosion_damage(explosion_damage)
	
	return projectile

# Get lock-on percentage (0-1) for UI
func get_lock_percent() -> float:
	if not target or not _is_tracking:
		return 0.0
	
	return lock_on_progress / lock_on_time

# Start tracking when enabled
func enable() -> void:
	super.enable()
	start_tracking()

# Stop tracking when disabled
func disable() -> void:
	stop_tracking()
	super.disable()

# Override reload sound
func _on_reload_complete() -> void:
	current_ammo = max_ammo
	_is_reloading = false
	_can_fire = true
	weapon_reloaded.emit()
	ammo_changed.emit(current_ammo, max_ammo)
	
	# Use custom reload sound
	if enable_audio and _audio_manager and reload_sound:
		_play_sound(reload_sound)
	
	if debug_mode:
		_debug_print("Reload complete")
