# scripts/components/weapons/laser_weapon_component.gd
extends WeaponComponent
class_name LaserWeaponComponent

# Laser-specific properties
@export_group("Laser Properties")
@export var laser_color: Color = Color(1.0, 0.2, 0.2, 1.0)
@export var laser_width: float = 2.0
@export var energy_consumption: float = 5.0
@export var max_energy: float = 100.0
@export var energy_regen_rate: float = 10.0

# State tracking
var current_energy: float = 100.0
var _energy_percent: float = 1.0
var _is_energy_depleted: bool = false

# Cooldown tracking for laser sound
var _last_sound_time: float = 0.0
var _sound_cooldown: float = 0.1

# Optional beam effect
var _beam_effect: Line2D = null

func setup() -> void:
	super.setup()
	
	# Set default properties for a laser weapon
	weapon_name = "Laser"
	fire_rate = 8.0  # Rapid fire
	damage = 5.0     # Lower per-shot damage
	projectile_lifespan = 1.0  # Short-lived projectile
	
	# If projectile scene is not set, load the laser projectile
	if not projectile_scene and ResourceLoader.exists("res://scenes/projectiles/laser_projectile.tscn"):
		projectile_scene = load("res://scenes/projectiles/laser_projectile.tscn")
	
	# Set initial energy
	current_energy = max_energy
	_energy_percent = 1.0
	
	# Setup visual beam effect if needed
	_setup_beam_effect()

func _on_enable() -> void:
	super._on_enable()
	
	if _beam_effect:
		_beam_effect.visible = false

func _on_disable() -> void:
	super._on_disable()
	
	if _beam_effect:
		_beam_effect.visible = false

func fire() -> bool:
	# Check energy before firing
	if current_energy < energy_consumption:
		if not _is_energy_depleted:
			_is_energy_depleted = true
			
			# Play empty click sound if enabled
			if enable_audio and _audio_manager and empty_sound_name:
				_play_sound(empty_sound_name)
		
		return false
	
	# Call parent fire method
	var did_fire = super.fire()
	
	# If fired successfully, consume energy
	if did_fire:
		current_energy -= energy_consumption
		_energy_percent = current_energy / max_energy
		
		# Update beam effect if it exists
		if _beam_effect:
			_update_beam_effect()
	
	return did_fire

func process_component(delta: float) -> void:
	super.process_component(delta)
	
	# Handle energy regeneration
	if current_energy < max_energy:
		current_energy = min(max_energy, current_energy + (energy_regen_rate * delta))
		_energy_percent = current_energy / max_energy
		
		# Check if we've recovered from energy depletion
		if _is_energy_depleted and current_energy >= energy_consumption:
			_is_energy_depleted = false
	
	# Update beam effect visibility
	if _beam_effect:
		_beam_effect.visible = false

# Setup visual beam effect
func _setup_beam_effect() -> void:
	# Create a Line2D for the beam effect if needed
	if not _beam_effect and owner_entity is Node2D:
		_beam_effect = Line2D.new()
		_beam_effect.name = "LaserBeamEffect"
		_beam_effect.width = laser_width
		_beam_effect.default_color = laser_color
		_beam_effect.z_index = 5
		_beam_effect.visible = false
		
		# Add points for the line
		_beam_effect.add_point(Vector2.ZERO)
		_beam_effect.add_point(Vector2(500, 0))  # Default length
		
		var muzzle = _muzzle_node if _muzzle_node else owner_entity
		muzzle.add_child(_beam_effect)

# Update beam effect when firing
func _update_beam_effect() -> void:
	if not _beam_effect:
		return
	
	_beam_effect.visible = true
	_beam_effect.default_color = laser_color
	
	# Schedule hiding the beam effect after a short delay
	get_tree().create_timer(0.05).timeout.connect(func(): _beam_effect.visible = false)

# Get energy percentage for UI
func get_energy_percent() -> float:
	return _energy_percent

# Modify projectile at creation time
func _create_projectile() -> Node:
	var projectile = super._create_projectile()
	
	if projectile:
		# Set laser-specific properties
		if projectile.has_method("set_laser_color"):
			projectile.set_laser_color(laser_color)
		
		if projectile.has_method("set_laser_width"):
			projectile.set_laser_width(laser_width)
			
		# IMPORTANT: Set direction for proper laser orientation and movement
		if projectile.has_method("set_direction"):
			var firing_dir = Vector2.RIGHT.rotated(owner_entity.global_rotation)
			projectile.set_direction(firing_dir)
	
	return projectile

# Override sound method to add cooldown for rapid fire
func _play_sound(sound_name: String, pitch: float = 1.0) -> void:
	# Use cooldown to avoid sound spam for rapid fire
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_sound_time < _sound_cooldown:
		return
		
	_last_sound_time = current_time
	super._play_sound(sound_name, pitch)
