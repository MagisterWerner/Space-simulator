# health_component.gd
extends Component
class_name HealthComponent

signal health_changed(current_health, max_health)
signal damaged(amount, source)
signal healed(amount, source)
signal died

@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var shield_percentage: float = 0.0  # 0.0 to 1.0, reduces damage by this percentage
@export var armor: float = 0.0  # Flat damage reduction
@export var invulnerable: bool = false

@export_category("Recovery")
@export var auto_recovery: bool = false
@export var recovery_rate: float = 5.0  # Health per second
@export var recovery_delay: float = 3.0  # Seconds after taking damage before recovery starts
@export var critical_health_percentage: float = 0.25  # Below this percentage is considered critical

var last_damage_time: float = 0.0
var _is_dead: bool = false
var _modifier_strategies: Array = []

func setup() -> void:
	current_health = max_health
	
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
	actual_damage = max(0, actual_damage - armor)
	
	# Apply strategies
	for strategy in _modifier_strategies:
		if strategy.has_method("modify_incoming_damage"):
			actual_damage = strategy.modify_incoming_damage(actual_damage, damage_type)
	
	# Apply damage
	if actual_damage > 0:
		current_health -= actual_damage
		last_damage_time = Time.get_ticks_msec() / 1000.0
		damaged.emit(actual_damage, source)
		health_changed.emit(current_health, max_health)
		
		debug_print("Took %s damage, health: %s/%s" % [actual_damage, current_health, max_health])
		
		# Check for death
		if current_health <= 0:
			_die()
			
	return actual_damage
	
func heal(amount: float, source: Node = null) -> float:
	if _is_dead or amount <= 0:
		return 0.0
		
	var actual_heal = amount
	
	# Apply strategies
	for strategy in _modifier_strategies:
		if strategy.has_method("modify_incoming_healing"):
			actual_heal = strategy.modify_incoming_healing(actual_heal)
	
	var old_health = current_health
	current_health = min(current_health + actual_heal, max_health)
	
	var health_gained = current_health - old_health
	if health_gained > 0:
		healed.emit(health_gained, source)
		health_changed.emit(current_health, max_health)
		debug_print("Healed %s, health: %s/%s" % [health_gained, current_health, max_health])
		
	return health_gained
	
func set_max_health(new_max: float, adjust_current: bool = true) -> void:
	var old_max = max_health
	max_health = max(1.0, new_max)
	
	if adjust_current:
		var ratio = current_health / old_max
		current_health = max_health * ratio
	else:
		current_health = min(current_health, max_health)
		
	health_changed.emit(current_health, max_health)
	
func _die() -> void:
	if _is_dead:
		return
		
	_is_dead = true
	current_health = 0
	died.emit()
	debug_print("Died")
	
func process_component(delta: float) -> void:
	if auto_recovery and not _is_dead and current_health < max_health:
		var current_time = Time.get_ticks_msec() / 1000.0
		if current_time - last_damage_time >= recovery_delay:
			heal(recovery_rate * delta, null)
			
func is_dead() -> bool:
	return _is_dead
	
func get_health_percent() -> float:
	return current_health / max_health
	
func is_critical() -> bool:
	return get_health_percent() <= critical_health_percentage
	
func add_modifier_strategy(strategy) -> void:
	if not _modifier_strategies.has(strategy):
		_modifier_strategies.append(strategy)
		
func remove_modifier_strategy(strategy) -> void:
	_modifier_strategies.erase(strategy)
