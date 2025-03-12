# health_component.gd - Optimized implementation
extends Component
class_name HealthComponent

signal health_changed(current_health, max_health)
signal damaged(amount, source)
signal healed(amount, source)
signal died

@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var shield_percentage: float = 0.0
@export var armor: float = 0.0
@export var invulnerable: bool = false

@export_category("Recovery")
@export var auto_recovery: bool = false
@export var recovery_rate: float = 5.0
@export var recovery_delay: float = 3.0
@export var critical_health_percentage: float = 0.25

var last_damage_time: float = 0.0
var _is_dead: bool = false
var _modifier_strategies: Array = []
var _health_percent: float = 1.0 # Cached health percentage

func setup() -> void:
	current_health = max_health
	_health_percent = 1.0
	
func _on_enable() -> void:
	_is_dead = false

func apply_damage(amount: float, damage_type: String = "normal", source: Node = null) -> float:
	if invulnerable or _is_dead or amount <= 0:
		return 0.0
		
	# Apply damage modifiers
	var actual_damage = amount
	
	# Apply shield reduction
	if shield_percentage > 0:
		actual_damage *= (1.0 - shield_percentage)
	
	# Apply armor reduction
	if armor > 0:
		actual_damage = max(0, actual_damage - armor)
	
	# Only apply strategies if we have them and damage is still positive
	if actual_damage > 0 and not _modifier_strategies.is_empty():
		for strategy in _modifier_strategies:
			if strategy.has_method("modify_incoming_damage"):
				actual_damage = strategy.modify_incoming_damage(actual_damage, damage_type)
	
	# Apply damage
	if actual_damage > 0:
		current_health -= actual_damage
		last_damage_time = Time.get_ticks_msec() / 1000.0
		
		damaged.emit(actual_damage, source)
		
		# Update cached health percent
		_health_percent = current_health / max_health
		health_changed.emit(current_health, max_health)
		
		if debug_mode:
			_debug_print("Took %s damage, health: %.1f/%.1f" % [actual_damage, current_health, max_health])
		
		# Check for death
		if current_health <= 0:
			_die()
			
	return actual_damage
	
func heal(amount: float, source: Node = null) -> float:
	if _is_dead or amount <= 0 or current_health >= max_health:
		return 0.0
		
	var actual_heal = amount
	
	# Only apply strategies if we have them
	if not _modifier_strategies.is_empty():
		for strategy in _modifier_strategies:
			if strategy.has_method("modify_incoming_healing"):
				actual_heal = strategy.modify_incoming_healing(actual_heal)
	
	var old_health = current_health
	current_health = min(current_health + actual_heal, max_health)
	
	var health_gained = current_health - old_health
	if health_gained > 0:
		healed.emit(health_gained, source)
		
		# Update cached health percent
		_health_percent = current_health / max_health
		health_changed.emit(current_health, max_health)
		
		if debug_mode:
			_debug_print("Healed %.1f, health: %.1f/%.1f" % [health_gained, current_health, max_health])
		
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
	
	# Update cached health percent
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
		_debug_print("Died")
	
func process_component(delta: float) -> void:
	if auto_recovery and not _is_dead and current_health < max_health:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_damage_time >= recovery_delay:
			heal(recovery_rate * delta, null)
			
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
