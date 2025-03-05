# shield_component.gd
extends Component
class_name ShieldComponent

signal shield_hit(damage, position)
signal shield_depleted
signal shield_recharged
signal shield_changed(current, maximum)

@export_category("Shield Properties")
@export var max_shield: float = 100.0
@export var current_shield: float = 100.0
@export var recharge_rate: float = 10.0  # Per second
@export var recharge_delay: float = 5.0  # Seconds after taking damage before recharging
@export var damage_reduction: float = 0.7  # Damage reduction multiplier (0.7 = 70% damage reduction)

@export_category("Visual")
@export var shield_visual_path: NodePath
@export var impact_effect_scene: PackedScene

var _shield_active: bool = true
var _last_hit_time: float = 0.0
var _shield_visual: Node = null  # Changed from Node2D to Node
var _shield_strategies: Array = []

func setup() -> void:
	current_shield = max_shield
	
	if not shield_visual_path.is_empty():
		_shield_visual = get_node(shield_visual_path)
		_update_shield_visual()
	
	shield_changed.emit(current_shield, max_shield)

func _on_enable() -> void:
	_shield_active = true
	_update_shield_visual()

func _on_disable() -> void:
	_shield_active = false
	_update_shield_visual()

func take_hit(damage_amount: float, hit_position: Vector2 = Vector2.ZERO) -> float:
	if not enabled or not _shield_active or damage_amount <= 0 or current_shield <= 0:
		return damage_amount
	
	_last_hit_time = Time.get_ticks_msec() / 1000.0
	
	# Apply damage reduction and strategies
	var reduced_damage = damage_amount * (1.0 - damage_reduction)
	
	# Apply modifier strategies
	for strategy in _shield_strategies:
		if strategy.has_method("modify_shield_damage"):
			reduced_damage = strategy.modify_shield_damage(reduced_damage)
	
	# Calculate how much damage the shield absorbs
	var damage_to_shield = damage_amount - reduced_damage
	current_shield -= damage_to_shield
	
	# Ensure shield doesn't go negative
	if current_shield < 0:
		var shield_overflow = -current_shield
		current_shield = 0
		reduced_damage += shield_overflow
		
		# Shield depleted
		_shield_active = false
		shield_depleted.emit()
		_update_shield_visual()
		
		debug_print("Shield depleted")
	
	shield_changed.emit(current_shield, max_shield)
	shield_hit.emit(damage_to_shield, hit_position)
	debug_print("Shield took hit: %s damage, shield: %s/%s" % [damage_to_shield, current_shield, max_shield])
	
	# Show impact effect if provided
	if impact_effect_scene and hit_position != Vector2.ZERO:
		var impact = impact_effect_scene.instantiate()
		owner_entity.add_child(impact)
		impact.global_position = hit_position
	
	return reduced_damage

func process_component(delta: float) -> void:
	if not enabled:
		return
		
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Handle shield recharge
	if current_shield < max_shield and current_time - _last_hit_time >= recharge_delay:
		var modified_recharge_rate = recharge_rate
		
		# Apply modifier strategies
		for strategy in _shield_strategies:
			if strategy.has_method("modify_recharge_rate"):
				modified_recharge_rate = strategy.modify_recharge_rate(modified_recharge_rate)
		
		current_shield = min(current_shield + (modified_recharge_rate * delta), max_shield)
		shield_changed.emit(current_shield, max_shield)
		
		# Check if shield was fully recharged
		if not _shield_active and current_shield > 0:
			_shield_active = true
			shield_recharged.emit()
			_update_shield_visual()
			debug_print("Shield recharged")

func _update_shield_visual() -> void:
	if _shield_visual:
		# Check if the shield visual has a visible property (most nodes do)
		if _shield_visual.has_method("set_visible"):
			_shield_visual.set_visible(_shield_active and enabled)
		elif _shield_visual is Node2D:
			_shield_visual.visible = _shield_active and enabled

func get_shield_percent() -> float:
	return current_shield / max_shield

func set_max_shield(new_max: float, adjust_current: bool = true) -> void:
	var old_max = max_shield
	max_shield = max(1.0, new_max)
	
	if adjust_current:
		var ratio = current_shield / old_max
		current_shield = max_shield * ratio
	else:
		current_shield = min(current_shield, max_shield)
		
	shield_changed.emit(current_shield, max_shield)

func add_shield_strategy(strategy) -> void:
	if not _shield_strategies.has(strategy):
		_shield_strategies.append(strategy)
		
func remove_shield_strategy(strategy) -> void:
	_shield_strategies.erase(strategy)
