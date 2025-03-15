# scripts/strategies/movement_strategies.gd
extends Resource

# Base Movement Strategy class
class MovementStrategy extends Strategy:
	func _init() -> void:
		target_component_type = "MovementComponent"
	
	func can_apply_to(component) -> bool:
		return component != null and component.get_class() == "MovementComponent"

# Enhanced Thrusters Strategy
class EnhancedThrustersStrategy extends MovementStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Enhanced Thrusters"
		description = "Increases engine power by 40%"
		price = 400
		affected_properties = ["engine_power"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.engine_power *= 1.4
	
	func _restore_component() -> void:
		if target_component:
			target_component.engine_power /= 1.4
	
	func get_property_value():
		return 1.4

# Maneuverability Strategy
class ManeuverabilityStrategy extends MovementStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Enhanced Maneuverability"
		description = "Increases turning speed by 30%"
		price = 350
		affected_properties = ["turning_speed"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.turning_speed *= 1.3
	
	func _restore_component() -> void:
		if target_component:
			target_component.turning_speed /= 1.3
	
	func get_property_value():
		return 1.3

# Afterburner Strategy
class AfterburnerStrategy extends MovementStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Afterburner"
		description = "Temporarily boosts maximum speed by 50%"
		price = 500
		affected_properties = ["max_speed"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.max_speed *= 1.5
	
	func _restore_component() -> void:
		if target_component:
			target_component.max_speed /= 1.5
	
	func get_property_value():
		return 1.5

# Inertial Dampeners Strategy
class InertialDampenersStrategy extends MovementStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Inertial Dampeners"
		description = "Reduces inertia for better handling"
		price = 450
		affected_properties = ["inertia_modifier"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.inertia_modifier = 0.5
	
	func _restore_component() -> void:
		if target_component:
			target_component.inertia_modifier = 1.0
	
	func get_property_value():
		return 0.5
