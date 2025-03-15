# shield_component.gd - Optimized implementation
extends Component
class_name ShieldComponent

signal shield_hit(damage, position)
signal shield_depleted
signal shield_recharged
signal shield_changed(current, maximum)

# Shield properties
@export_category("Shield Properties")
@export var max_shield: float = 100.0
@export var current_shield: float = 100.0
@export var recharge_rate: float = 10.0
@export var recharge_delay: float = 5.0
@export var damage_reduction: float = 0.7

# Visual settings
@export_category("Visual")
@export var shield_visual_path: NodePath
@export var impact_effect_scene: PackedScene

# Cached state
var _shield_active: bool = true
var _last_hit_time: float = 0.0
var _shield_visual: Node = null
var _shield_percent: float = 1.0
var _recharge_accumulator: float = 0.0
var _hit_this_frame: bool = false
var _current_frame: int = 0
var _last_hit_frame: int = -1

# Strategies - kept as direct array for better performance
var _shield_strategies = []

# Constants
const MIN_VISIBLE_ALPHA = 0.1
const MAX_VISIBLE_ALPHA = 0.8
const RECHARGE_CHECK_INTERVAL = 0.1

func setup() -> void:
	current_shield = max_shield
	_shield_percent = 1.0
	
	if not shield_visual_path.is_empty():
		_shield_visual = get_node_or_null(shield_visual_path)
		_update_shield_visual()
	
	shield_changed.emit(current_shield, max_shield)

func _on_enable() -> void:
	_shield_active = true
	_update_shield_visual()

func _on_disable() -> void:
	_shield_active = false
	_update_shield_visual()

func take_hit(damage_amount: float, hit_position: Vector2 = Vector2.ZERO) -> float:
	# Fast rejection path
	if not enabled or not _shield_active or damage_amount <= 0 or current_shield <= 0:
		return damage_amount
	
	# Batch hits in the same frame (prevents shield flicker)
	_current_frame = Engine.get_physics_frames()
	if _current_frame == _last_hit_frame:
		_hit_this_frame = true
		return damage_amount
	
	_last_hit_frame = _current_frame
	_hit_this_frame = true
	
	_last_hit_time = Time.get_ticks_msec() / 1000.0
	
	# Apply damage reduction
	var reduced_damage = damage_amount * (1.0 - damage_reduction)
	
	# Apply modifier strategies - only if there are strategies
	if not _shield_strategies.is_empty():
		for strategy in _shield_strategies:
			if strategy.has_method("modify_shield_damage"):
				reduced_damage = strategy.modify_shield_damage(reduced_damage)
	
	# Calculate shield absorption
	var damage_to_shield = damage_amount - reduced_damage
	current_shield -= damage_to_shield
	
	# Handle shield depletion
	if current_shield < 0:
		var shield_overflow = -current_shield
		current_shield = 0
		reduced_damage += shield_overflow
		
		# Shield depleted
		_shield_active = false
		_shield_percent = 0.0
		shield_depleted.emit()
		_update_shield_visual()
		
		if debug_mode:
			print("[ShieldComponent] Shield depleted")
	else:
		# Update cached percentage
		_shield_percent = current_shield / max_shield
	
	shield_changed.emit(current_shield, max_shield)
	shield_hit.emit(damage_to_shield, hit_position)
	
	if debug_mode:
		print("[ShieldComponent] Shield took hit: %.1f damage, shield: %.1f/%.1f" % 
			  [damage_to_shield, current_shield, max_shield])
	
	# Spawn impact effect if provided
	_spawn_impact_effect(hit_position)
	
	return reduced_damage

# Separate method for impact effect to improve main function readability
func _spawn_impact_effect(hit_position: Vector2) -> void:
	if impact_effect_scene and hit_position != Vector2.ZERO:
		var impact = impact_effect_scene.instantiate()
		owner_entity.add_child(impact)
		impact.global_position = hit_position

func process_component(delta: float) -> void:
	# Skip if no recharging is needed
	if not enabled or current_shield >= max_shield:
		return
	
	# Accumulate time to reduce processing frequency
	_recharge_accumulator += delta
	if _recharge_accumulator < RECHARGE_CHECK_INTERVAL:
		return
	
	var current_time = Time.get_ticks_msec() / 1000.0
	
	# Handle shield recharge after delay
	if current_time - _last_hit_time >= recharge_delay:
		var modified_recharge_rate = recharge_rate
		
		# Apply modifier strategies - only if there are strategies
		if not _shield_strategies.is_empty():
			for strategy in _shield_strategies:
				if strategy.has_method("modify_recharge_rate"):
					modified_recharge_rate = strategy.modify_recharge_rate(modified_recharge_rate)
		
		var old_shield = current_shield
		current_shield = min(current_shield + (modified_recharge_rate * _recharge_accumulator), max_shield)
		
		# Only emit signal if shield actually changed
		if current_shield != old_shield:
			_shield_percent = current_shield / max_shield
			shield_changed.emit(current_shield, max_shield)
		
		# Check if shield was fully recharged
		if not _shield_active and current_shield > 0:
			_shield_active = true
			shield_recharged.emit()
			_update_shield_visual()
			
			if debug_mode:
				print("[ShieldComponent] Shield recharged")
	
	# Reset accumulator and hit tracking
	_recharge_accumulator = 0
	_hit_this_frame = false

func _update_shield_visual() -> void:
	if _shield_visual == null:
		return
	
	var visible = _shield_active and enabled
	
	if _shield_visual is Node2D:
		_shield_visual.visible = visible
		
		# Apply shield percentage to alpha
		if visible and _shield_visual is CanvasItem and not _hit_this_frame:
			var alpha = MIN_VISIBLE_ALPHA + (MAX_VISIBLE_ALPHA - MIN_VISIBLE_ALPHA) * _shield_percent
			_shield_visual.modulate.a = alpha
		elif _hit_this_frame:
			# Flash shield at full alpha when hit
			_shield_visual.modulate.a = MAX_VISIBLE_ALPHA
	elif _shield_visual.has_method("set_visible"):
		_shield_visual.set_visible(visible)

func get_shield_percent() -> float:
	return _shield_percent

func set_max_shield(new_max: float, adjust_current: bool = true) -> void:
	if new_max <= 0:
		return
	
	var old_max = max_shield
	max_shield = max(1.0, new_max)
	
	if adjust_current:
		var ratio = current_shield / old_max
		current_shield = max_shield * ratio
	else:
		current_shield = min(current_shield, max_shield)
	
	_shield_percent = current_shield / max_shield
	shield_changed.emit(current_shield, max_shield)

# Strategy management
func add_shield_strategy(strategy) -> void:
	if not _shield_strategies.has(strategy):
		_shield_strategies.append(strategy)
		
func remove_shield_strategy(strategy) -> void:
	_shield_strategies.erase(strategy)

# Reset shield
func reset_shield() -> void:
	current_shield = max_shield
	_shield_percent = 1.0
	_shield_active = true
	shield_changed.emit(current_shield, max_shield)
	_update_shield_visual()

# Deplete shield
func deplete_shield() -> void:
	if current_shield <= 0 or not _shield_active:
		return
		
	var _old_shield = current_shield
	current_shield = 0
	_shield_percent = 0.0
	_shield_active = false
	
	shield_changed.emit(0.0, max_shield)
	shield_depleted.emit()
	_update_shield_visual()
