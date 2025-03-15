extends Node2D
class_name WeaponComponent

# Signals
signal weapon_fired(projectile)
signal cooldown_complete
signal ammo_changed(current, maximum)

# Base weapon properties
@export var weapon_name: String = "Base Weapon"
@export var damage: float = 10.0
@export var fire_rate: float = 1.0  # Shots per second
@export var projectile_speed: float = 500.0
@export var energy_cost: float = 1.0
@export var max_ammo: int = 100
@export var reload_time: float = 2.0
@export var auto_reload: bool = true
@export var enabled: bool = true

# Current state
var current_ammo: int = max_ammo
var cooldown_timer: float = 0.0
var can_fire: bool = true
var reloading: bool = false
var reload_progress: float = 0.0

# Upgrade strategies
var applied_strategies = []

# Owner reference
var owner_entity: Node = null

func _ready() -> void:
	# Get reference to the owner (parent)
	owner_entity = get_parent()
	
	# Set initial ammo
	current_ammo = max_ammo

func _process(delta: float) -> void:
	if not enabled:
		return
	
	# Handle cooldown
	if not can_fire:
		cooldown_timer -= delta
		if cooldown_timer <= 0:
			can_fire = true
			cooldown_complete.emit()
	
	# Handle reloading
	if reloading:
		reload_progress += delta
		if reload_progress >= reload_time:
			_complete_reload()

# Virtual method to be overridden by subclasses
func fire() -> bool:
	# Basic implementation
	if not can_fire or not enabled:
		return false
	
	if current_ammo <= 0:
		# Try to reload if out of ammo
		if auto_reload:
			start_reload()
		return false
	
	# Set cooldown
	cooldown_timer = 1.0 / fire_rate
	can_fire = false
	
	# Reduce ammo
	current_ammo -= 1
	ammo_changed.emit(current_ammo, max_ammo)
	
	return true

# Start reloading
func start_reload() -> void:
	if reloading or current_ammo >= max_ammo:
		return
	
	reloading = true
	reload_progress = 0.0

# Complete reload
func _complete_reload() -> void:
	reloading = false
	current_ammo = max_ammo
	ammo_changed.emit(current_ammo, max_ammo)

# Enable the weapon
func enable() -> void:
	enabled = true

# Disable the weapon
func disable() -> void:
	enabled = false

# Get ammo percentage (0.0 to 1.0)
func get_ammo_percent() -> float:
	if max_ammo <= 0:
		return 0.0
	return float(current_ammo) / float(max_ammo)

# Add a new strategy
func apply_strategy(strategy) -> void:
	# Check if the strategy is already applied
	for existing in applied_strategies:
		if existing.get_script() == strategy.get_script():
			return
	
	# Set the owner component
	strategy.owner_component = self
	
	# Apply the strategy
	strategy.apply()
	
	# Add to the list
	applied_strategies.append(strategy)

# Remove a strategy
func remove_strategy(strategy) -> void:
	var index = applied_strategies.find(strategy)
	if index >= 0:
		# Remove the strategy's effects
		strategy.remove()
		
		# Remove from the list
		applied_strategies.remove_at(index)

# Reset to default values
func reset() -> void:
	current_ammo = max_ammo
	cooldown_timer = 0.0
	can_fire = true
	reloading = false
	reload_progress = 0.0
	ammo_changed.emit(current_ammo, max_ammo)
