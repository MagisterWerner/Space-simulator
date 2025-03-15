extends Node
class_name HealthComponent

signal damaged(amount, type, source)
signal healed(amount)
signal shield_damaged(amount, type, source)
signal shield_depleted()
signal shield_recharged()
signal killed()
signal health_changed(current, max_health)
signal health_depleted()
signal died()

# Health configuration
@export_category("Health")
@export var max_health: float = 100.0
@export var starting_health_percent: float = 1.0
@export var invincible: bool = false
@export var destroy_parent_on_death: bool = true

# Shield configuration
@export_category("Shield")
@export var has_shield: bool = false
@export var max_shield: float = 50.0
@export var shield_recharge_rate: float = 5.0
@export var shield_recharge_delay: float = 3.0
@export var shield_efficiency: float = 1.0  # Damage multiplier (lower means shield absorbs more)

# Armor & damage reduction
@export_category("Damage Reduction")
@export var armor: float = 0.0
@export var damage_resistance: Dictionary = {}

# Hit effects
@export_category("Hit Effects")
@export var hit_effect_scene: PackedScene
@export var hit_flash_duration: float = 0.1
@export var hit_immunity_time: float = 0.0
@export var death_effect_scene: PackedScene

# Debug options
@export_category("Debug")
@export var debug_health: bool = false
@export var print_damage_taken: bool = false

# Runtime state
var current_health: float
var current_shield: float
var is_dead: bool = false
var shield_depleted_timestamp: float = 0
var hit_immunity_timestamp: float = 0

# Damage types - can be extended
enum DamageType {
	IMPACT,
	EXPLOSIVE,
	ENERGY,
	FIRE,
	PROJECTILE,
	COLLISION
}

# Private state
var _shield_recharging: bool = false
var _parent = null
var _registered_strategies: Array = []
var _game_time: float = 0

func _ready() -> void:
	_parent = get_parent()
	
	# Initialize health based on percentage
	current_health = max_health * starting_health_percent
	
	# Initialize shield
	if has_shield:
		current_shield = max_shield
	else:
		current_shield = 0
	
	if debug_health:
		print("HealthComponent: Initialized with ", current_health, " health and ", current_shield, " shield")
	
	# Connect to damage strategy signals if available
	_connect_to_strategies()

func _process(delta: float) -> void:
	_game_time += delta
	
	# Shield recharge logic
	if has_shield and current_shield < max_shield and _game_time - shield_depleted_timestamp > shield_recharge_delay:
		_recharge_shield(delta)

func _recharge_shield(delta: float) -> void:
	var old_shield = current_shield
	current_shield = min(max_shield, current_shield + shield_recharge_rate * delta)
	
	# Emit signal if shield recharged from 0
	if old_shield <= 0 and current_shield > 0:
		_shield_recharging = false
		shield_recharged.emit()
		
		if debug_health:
			print("HealthComponent: Shield recharged")

# Main method to apply damage to the entity
func apply_damage(amount: float, type: String = "impact", source = null) -> bool:
	if invincible:
		return false
	
	# Check hit immunity
	if hit_immunity_time > 0 and _game_time - hit_immunity_timestamp < hit_immunity_time:
		return false
	
	# Process damage modifiers from registered strategies
	amount = _process_damage_modifiers(amount, type, source)
	
	if amount <= 0:
		return false
	
	# Apply damage resistance
	var damage_type_id = _get_damage_type_id(type)
	if damage_resistance.has(damage_type_id):
		amount *= (1.0 - damage_resistance[damage_type_id])
	
	# Apply armor damage reduction if any
	if armor > 0:
		amount = max(1.0, amount - armor)
	
	var original_amount = amount
	var shield_damage = 0.0
	
	# Handle shield damage first if available
	if has_shield and current_shield > 0:
		shield_damage = min(current_shield, amount * shield_efficiency)
		current_shield -= shield_damage
		amount -= shield_damage / shield_efficiency
		
		# Emit shield damaged signal
		if shield_damage > 0:
			shield_damaged.emit(shield_damage, type, source)
		
		# Check if shield was depleted
		if current_shield <= 0:
			_shield_recharging = true
			shield_depleted_timestamp = _game_time
			shield_depleted.emit()
			
			if debug_health:
				print("HealthComponent: Shield depleted")
	
	# Apply remaining damage to health
	if amount > 0:
		# Set hit immunity timestamp
		hit_immunity_timestamp = _game_time
		
		# Apply damage to health
		current_health -= amount
		damaged.emit(amount, type, source)
		health_changed.emit(current_health, max_health)
		
		if print_damage_taken:
			var shield_text = ""
			if shield_damage > 0:
				shield_text = " (Shield absorbed: " + str(shield_damage) + ")"
			print("Damage taken: ", amount, shield_text, " from ", type)
		
		# Spawn hit effect if provided
		if hit_effect_scene:
			_spawn_hit_effect()
		
		# Handle death if health depleted
		if current_health <= 0 and not is_dead:
			current_health = 0
			health_depleted.emit()
			_handle_death()
	
	return true

# Heal the entity
func heal(amount: float) -> bool:
	if amount <= 0 or is_dead:
		return false
	
	var old_health = current_health
	current_health = min(max_health, current_health + amount)
	
	if current_health > old_health:
		healed.emit(current_health - old_health)
		health_changed.emit(current_health, max_health)
		return true
	
	return false

# Restore shield
func restore_shield(amount: float) -> bool:
	if amount <= 0 or not has_shield:
		return false
	
	var old_shield = current_shield
	current_shield = min(max_shield, current_shield + amount)
	
	return current_shield > old_shield

# Kill immediately
func kill() -> void:
	if is_dead:
		return
	
	current_health = 0
	health_depleted.emit()
	_handle_death()

# Handle death logic
func _handle_death() -> void:
	if is_dead:
		return
	
	is_dead = true
	killed.emit()
	died.emit()
	
	# Spawn death effect if provided
	if death_effect_scene:
		_spawn_death_effect()
	
	# Destroy parent if configured to do so
	if destroy_parent_on_death and _parent and is_instance_valid(_parent):
		# Use call_deferred to avoid issues during signal processing
		_parent.call_deferred("queue_free")

# Get health percentage (0-1)
func get_health_percent() -> float:
	return current_health / max_health

# Get shield percentage (0-1)
func get_shield_percent() -> float:
	return current_shield / max_shield if has_shield and max_shield > 0 else 0.0

# Reset health to starting values
func reset_health() -> void:
	is_dead = false
	current_health = max_health * starting_health_percent
	current_shield = max_shield if has_shield else 0.0
	health_changed.emit(current_health, max_health)

# Add a damage modification strategy
func add_strategy(strategy) -> void:
	if not strategy in _registered_strategies:
		_registered_strategies.append(strategy)
		
		# Connect to strategy signals if it has them
		if "property_name" in strategy and strategy.has_signal("strategy_enabled"):
			strategy.connect("strategy_enabled", _on_strategy_enabled)
			strategy.connect("strategy_disabled", _on_strategy_disabled)

# Remove a damage modification strategy
func remove_strategy(strategy) -> void:
	var index = _registered_strategies.find(strategy)
	if index >= 0:
		_registered_strategies.remove_at(index)
		
		# Disconnect signals
		if "property_name" in strategy and strategy.is_connected("strategy_enabled", _on_strategy_enabled):
			strategy.disconnect("strategy_enabled", _on_strategy_enabled)
			strategy.disconnect("strategy_disabled", _on_strategy_disabled)

# Process damage modifiers from registered strategies
func _process_damage_modifiers(amount: float, type: String, source) -> float:
	var modified_amount = amount
	
	for strategy in _registered_strategies:
		if strategy.has_method("process_damage"):
			modified_amount = strategy.process_damage(modified_amount, type, source)
	
	return modified_amount

# Connect to any damage strategy components
func _connect_to_strategies() -> void:
	# Look for strategy components in parent
	if _parent:
		for child in _parent.get_children():
			if child.has_method("process_damage") or (child.has_signal("strategy_enabled") and child.has_signal("strategy_disabled")):
				add_strategy(child)

# Handle strategy enable/disable events
func _on_strategy_enabled(strategy_name: String, property_name: String, value) -> void:
	if property_name in self:
		var old_value = get(property_name)
		set(property_name, value)
		
		if debug_health:
			print("HealthComponent: Property ", property_name, " changed from ", old_value, " to ", value, " by strategy ", strategy_name)

func _on_strategy_disabled(strategy_name: String, property_name: String) -> void:
	# Reset property to default if needed
	pass

# Spawn hit effect
func _spawn_hit_effect() -> void:
	if not hit_effect_scene or not _parent or not is_instance_valid(_parent):
		return
	
	var effect = hit_effect_scene.instantiate()
	_parent.get_parent().add_child(effect)
	
	if effect is Node2D and _parent is Node2D:
		effect.global_position = _parent.global_position

# Spawn death effect
func _spawn_death_effect() -> void:
	if not death_effect_scene or not _parent or not is_instance_valid(_parent):
		return
	
	var effect = death_effect_scene.instantiate()
	_parent.get_parent().add_child(effect)
	
	if effect is Node2D and _parent is Node2D:
		effect.global_position = _parent.global_position

# Helper to convert damage type string to enum
func _get_damage_type_id(type: String) -> int:
	match type.to_lower():
		"impact": return DamageType.IMPACT
		"explosive": return DamageType.EXPLOSIVE
		"energy": return DamageType.ENERGY
		"fire": return DamageType.FIRE
		"projectile": return DamageType.PROJECTILE
		"collision": return DamageType.COLLISION
		_: return DamageType.IMPACT  # Default
