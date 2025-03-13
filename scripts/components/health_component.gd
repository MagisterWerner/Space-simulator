# scripts/components/health_component.gd - Optimized implementation
extends Component
class_name HealthComponent

signal health_changed(current_health, max_health)
signal damaged(amount, source)
signal healed(amount, source)
signal died

# Health properties
@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var shield_percentage: float = 0.0
@export var armor: float = 0.0
@export var invulnerable: bool = false

# Recovery settings
@export_category("Recovery")
@export var auto_recovery: bool = false
@export var recovery_rate: float = 5.0
@export var recovery_delay: float = 3.0
@export var critical_health_percentage: float = 0.25

# Damage event settings for better gameplay
@export_category("Damage Events")
@export var damage_threshold: float = 0.0  # Minimum damage to register (useful for asteroids)
@export var damage_multipliers: Dictionary = {
	"projectile": 1.0,   # Standard multiplier for projectiles
	"laser": 1.0,        # Laser weapons
	"missile": 1.5,      # Missiles do 50% more damage
	"explosion": 1.2,    # Explosions do 20% more damage
	"impact": 0.8,       # Physical impacts do less damage
	"collision": 0.6     # Collisions do even less damage
}

# State tracking
var last_damage_time: float = 0.0
var _is_dead: bool = false
var _health_percent: float = 1.0 # Cached health percentage
var _cached_recovery_time: float = 0.0
var _damage_this_frame: float = 0.0
var _last_damage_frame: int = -1

# Optimized arrays for strategy handling
var _modifier_strategies = []

# Cache for performance
var _current_frame: int = 0

func setup() -> void:
	current_health = max_health
	_health_percent = 1.0
	_is_dead = false
	
func _on_enable() -> void:
	_is_dead = false
	if current_health <= 0:
		current_health = max_health
		_health_percent = 1.0

func apply_damage(amount: float, damage_type: String = "normal", source: Node = null) -> float:
	# Skip processing for obvious cases
	if invulnerable or _is_dead or amount <= 0:
		return 0.0
	
	# Apply damage threshold filter - ignore tiny damage amounts
	if amount < damage_threshold:
		return 0.0
	
	# Batch damage in the same frame
	_current_frame = Engine.get_physics_frames()
	
	if _current_frame == _last_damage_frame:
		_damage_this_frame += amount
		return 0.0
	
	# Reset damage tracking for new frame
	_damage_this_frame = amount
	_last_damage_frame = _current_frame
	
	# Apply damage type multipliers if available
	if damage_multipliers.has(damage_type):
		amount *= damage_multipliers[damage_type]
	
	# Apply modifiers
	var actual_damage = _calculate_modified_damage(amount, damage_type)
	
	# Apply damage
	if actual_damage > 0:
		current_health -= actual_damage
		last_damage_time = Time.get_ticks_msec() / 1000.0
		
		# Update cache and emit signal
		_health_percent = current_health / max_health
		damaged.emit(actual_damage, damage_type, source)
		health_changed.emit(current_health, max_health)
		
		if debug_mode:
			print("[HealthComponent] Took %s damage, health: %.1f/%.1f" % [actual_damage, current_health, max_health])
		
		# Check for death
		if current_health <= 0:
			_die()
			
	return actual_damage

# Apply damage modifiers - separated for clarity
func _calculate_modified_damage(amount: float, damage_type: String) -> float:
	var modified_damage = amount
	
	# Apply shield reduction
	if shield_percentage > 0:
		modified_damage *= (1.0 - shield_percentage)
	
	# Apply armor reduction
	if armor > 0:
		modified_damage = max(0, modified_damage - armor)
	
	# Apply strategies
	if modified_damage > 0 and not _modifier_strategies.is_empty():
		for strategy in _modifier_strategies:
			if strategy.has_method("modify_incoming_damage"):
				modified_damage = strategy.modify_incoming_damage(modified_damage, damage_type)
	
	return modified_damage
	
func heal(amount: float, source: Node = null) -> float:
	if _is_dead or amount <= 0 or current_health >= max_health:
		return 0.0
	
	var actual_heal = amount
	
	# Apply healing modifiers from strategies
	if not _modifier_strategies.is_empty():
		for strategy in _modifier_strategies:
			if strategy.has_method("modify_incoming_healing"):
				actual_heal = strategy.modify_incoming_healing(actual_heal)
	
	# Apply healing
	var old_health = current_health
	current_health = min(current_health + actual_heal, max_health)
	
	# Calculate actual health gained
	var health_gained = current_health - old_health
	
	# Only emit signals if healing was actually applied
	if health_gained > 0:
		_health_percent = current_health / max_health
		healed.emit(health_gained, source)
		health_changed.emit(current_health, max_health)
		
		if debug_mode:
			print("[HealthComponent] Healed %.1f, health: %.1f/%.1f" % [health_gained, current_health, max_health])
	
	return health_gained
	
func set_max_health(new_max: float, adjust_current: bool = true) -> void:
	if new_max <= 0:
		return
	
	var old_max = max_health
	max_health = max(1.0, new_max)
	
	if adjust_current:
		var ratio = current_health / old_max
		current_health = max_health * ratio
	else:
		current_health = min(current_health, max_health)
	
	_health_percent = current_health / max_health
	health_changed.emit(current_health, max_health)
	
func _die() -> void:
	if _is_dead:
		return
	
	_is_dead = true
	current_health = 0
	_health_percent = 0
	died.emit()
	
	if debug_mode:
		print("[HealthComponent] Died")

# This now uses a more efficient time check to avoid excessive processing
func process_component(delta: float) -> void:
	if not auto_recovery or _is_dead or current_health >= max_health:
		return
	
	# Only process if needed - throttle recovery checks
	_cached_recovery_time += delta
	if _cached_recovery_time < 0.1:
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - last_damage_time >= recovery_delay:
		heal(recovery_rate * _cached_recovery_time, null)
		
	_cached_recovery_time = 0
	
# Fast accessors for frequent operations
func is_dead() -> bool:
	return _is_dead
	
func get_health_percent() -> float:
	return _health_percent
	
func is_critical() -> bool:
	return _health_percent <= critical_health_percentage
	
func add_modifier_strategy(strategy) -> void:
	if not _modifier_strategies.has(strategy):
		_modifier_strategies.append(strategy)
		
func remove_modifier_strategy(strategy) -> void:
	_modifier_strategies.erase(strategy)

# Kill entity immediately
func kill() -> void:
	if _is_dead:
		return
		
	current_health = 0
	_health_percent = 0
	_die()

# Resurrect entity
func resurrect(health_percentage: float = 1.0) -> void:
	if not _is_dead:
		return
		
	_is_dead = false
	current_health = max_health * clamp(health_percentage, 0.01, 1.0)
	_health_percent = current_health / max_health
	health_changed.emit(current_health, max_health)
