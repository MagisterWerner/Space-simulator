# scripts/strategies/shield_strategies.gd
extends Resource

# Base Shield Strategy class
class ShieldStrategy extends Strategy:
	func _init() -> void:
		target_component_type = "ShieldComponent"
	
	func can_apply_to(component) -> bool:
		return component != null and component.get_class() == "ShieldComponent"

# Reinforced Shield Strategy
class ReinforcedShieldStrategy extends ShieldStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Reinforced Shield"
		description = "Increases shield capacity by 50%"
		price = 500
		affected_properties = ["max_shield"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.max_shield *= 1.5
			# Recalculate current shield
			target_component.current_shield = min(target_component.current_shield, target_component.max_shield)
	
	func _restore_component() -> void:
		if target_component:
			target_component.max_shield /= 1.5
			# Recalculate current shield
			target_component.current_shield = min(target_component.current_shield, target_component.max_shield)
	
	func get_property_value():
		return 1.5

# Fast Recharge Strategy
class FastRechargeStrategy extends ShieldStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Fast Recharge"
		description = "Increases shield recharge rate by 100%"
		price = 450
		affected_properties = ["recharge_rate"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.recharge_rate *= 2.0
	
	func _restore_component() -> void:
		if target_component:
			target_component.recharge_rate /= 2.0
	
	func get_property_value():
		return 2.0

# Reflective Shield Strategy
class ReflectiveShieldStrategy extends ShieldStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Reflective Shield"
		description = "Reflects 25% of damage back to attackers"
		price = 600
		affected_properties = ["reflection_factor"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.reflection_factor = 0.25
	
	func _restore_component() -> void:
		if target_component:
			target_component.reflection_factor = 0.0
	
	func get_property_value():
		return 0.25

# Absorbent Shield Strategy
class AbsorbentShieldStrategy extends ShieldStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Absorbent Shield"
		description = "Reduces shield damage taken by 30%"
		price = 550
		affected_properties = ["damage_reduction"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.damage_reduction = 0.3
	
	func _restore_component() -> void:
		if target_component:
			target_component.damage_reduction = 0.0
	
	func get_property_value():
		return 0.3
