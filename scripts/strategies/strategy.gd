# scripts/strategies/strategy.gd - Optimized base Strategy class
extends Resource
class_name Strategy

signal applied_to_component(component)
signal removed_from_component(component)

@export var strategy_name: String = "Base Strategy"
@export var description: String = "Base strategy class"
@export var icon_texture: Texture2D
@export var rarity: String = "Common"  # Common, Uncommon, Rare, Epic, Legendary
@export var price: int = 100
@export var unique_id: String = ""
@export var weight: float = 1.0
@export var incompatible_strategies: Array[String] = []

# Strategy metadata
var applied_count: int = 0
var last_applied_time: int = 0
var owner_component: Component = null

# Virtual method that components call when applying strategy
func apply_to_component(component: Component) -> void:
	if not component:
		push_error("Strategy applied to invalid component")
		return
		
	if owner_component:
		# Quietly remove from previous component without warnings
		remove_from_component()
	
	owner_component = component
	applied_count += 1
	last_applied_time = Time.get_ticks_msec()
	
	# Add this strategy to the component using type-specific handling
	if owner_component is WeaponComponent and owner_component.has_method("add_weapon_strategy"):
		owner_component.add_weapon_strategy(self)
	elif owner_component is ShieldComponent and owner_component.has_method("add_shield_strategy"):
		owner_component.add_shield_strategy(self)
	elif owner_component is MovementComponent and owner_component.has_method("add_movement_strategy"):
		owner_component.add_movement_strategy(self)
	elif owner_component is HealthComponent and owner_component.has_method("add_modifier_strategy"):
		owner_component.add_modifier_strategy(self)
	
	applied_to_component.emit(component)

# Virtual method to remove strategy effects
func remove_from_component() -> void:
	if not owner_component:
		return
	
	# Remove from component's strategy list using type-specific handling
	if owner_component is WeaponComponent and owner_component.has_method("remove_weapon_strategy"):
		owner_component.remove_weapon_strategy(self)
	elif owner_component is ShieldComponent and owner_component.has_method("remove_shield_strategy"):
		owner_component.remove_shield_strategy(self)
	elif owner_component is MovementComponent and owner_component.has_method("remove_movement_strategy"):
		owner_component.remove_movement_strategy(self)
	elif owner_component is HealthComponent and owner_component.has_method("remove_modifier_strategy"):
		owner_component.remove_modifier_strategy(self)
	
	var previous_component = owner_component
	owner_component = null
	
	removed_from_component.emit(previous_component)

# Check if this strategy is compatible with others
func is_compatible_with(other_strategy: Strategy) -> bool:
	if not other_strategy:
		return true
		
	# Fast path incompatibility check
	if other_strategy.unique_id and incompatible_strategies.has(other_strategy.unique_id):
		return false
	
	if unique_id and other_strategy.incompatible_strategies.has(unique_id):
		return false
	
	return true

# Get a description that includes effects
func get_detailed_description() -> String:
	return description  # Override in child classes to add specific effects
