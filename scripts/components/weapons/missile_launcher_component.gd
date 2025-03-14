# scripts/components/weapons/missile_launcher_component.gd
extends WeaponComponent
class_name MissileLauncherComponent

# Missile properties
@export_category("Missile Properties")
@export var explosion_radius: float = 100.0
@export var explosion_damage: float = 30.0
@export var missile_speed: float = 300.0
@export var missile_acceleration: float = 20.0

# Sound settings
@export_category("Audio")
@export var fire_sound: String = "missile_launch"

# Visual effects
@export_category("Visual Effects")
@export var muzzle_flash_scene: PackedScene = null

# Internal state
var _projectile_scene: PackedScene = null
var _active_missiles: Array = []

func setup() -> void:
	super.setup()
	
	# Set default properties for a missile launcher
	weapon_name = "Missile Launcher"
	fire_rate = 0.8         # Slower fire rate (0.8 shots per second)
	damage = 50.0           # High direct hit damage
	projectile_speed = missile_speed
	projectile_lifespan = 5.0  # Long-lived projectile
	
	# Set ammunition settings
	unlimited_ammo = true   # Unlimited ammo, no reload needed
	
	# If projectile scene is not set, load the missile projectile
	if not projectile_scene:
		if ResourceLoader.exists("res://scenes/projectiles/missile_projectile.tscn"):
			_projectile_scene = load("res://scenes/projectiles/missile_projectile.tscn")
			projectile_scene = _projectile_scene
		else:
			push_error("MissileLauncherComponent: Could not load missile projectile scene")
	else:
		_projectile_scene = projectile_scene
	
	# Configure audio
	if enable_audio:
		# These will be used by the parent class WeaponComponent
		fire_sound_name = fire_sound
		empty_sound_name = ""  # No empty click sound

func _process(_delta: float) -> void:
	# Clean up references to missiles that no longer exist
	_cleanup_inactive_missiles()

func _cleanup_inactive_missiles() -> void:
	var i = 0
	while i < _active_missiles.size():
		var missile = _active_missiles[i]
		if not is_instance_valid(missile):
			_active_missiles.remove_at(i)
		else:
			i += 1

func _create_projectile() -> Node:
	var projectile = super._create_projectile()
	
	if projectile:
		# Add to active missiles list
		_active_missiles.append(projectile)
		
		# Set missile-specific properties
		if projectile.has_method("set_explosion_properties"):
			projectile.set_explosion_properties(explosion_radius, explosion_damage)
		
		if projectile.has_method("set_acceleration"):
			projectile.set_acceleration(missile_acceleration)
		
		# Set direction for proper missile orientation and movement
		if projectile.has_method("set_direction"):
			var firing_dir = Vector2.RIGHT.rotated(owner_entity.global_rotation)
			projectile.set_direction(firing_dir)
		
		# Create muzzle flash effect if available
		_spawn_muzzle_flash()
	
	return projectile

func _spawn_muzzle_flash() -> void:
	if not muzzle_flash_scene:
		return
		
	var muzzle_pos = Vector2.ZERO
	
	# Get position from muzzle or owner
	if _muzzle_node is Node2D:
		muzzle_pos = _muzzle_node.global_position
	elif owner_entity is Node2D:
		muzzle_pos = owner_entity.global_position
	
	var flash = muzzle_flash_scene.instantiate()
	get_tree().current_scene.add_child(flash)
	flash.global_position = muzzle_pos
	
	# Auto-remove after a short time
	get_tree().create_timer(0.2).timeout.connect(func(): 
		if is_instance_valid(flash):
			flash.queue_free()
	)

func _on_disable() -> void:
	super._on_disable()
	
	# Clean up active missiles if disabling the component
	for missile in _active_missiles:
		if is_instance_valid(missile) and missile.has_method("_trigger_explosion"):
			missile._trigger_explosion()
	
	_active_missiles.clear()
