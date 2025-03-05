# movement_strategies.gd
extends Resource
class_name MovementStrategies

# Enhanced Thrusters Strategy
class EnhancedThrustersStrategy extends Strategy:
	@export var thrust_multiplier: float = 1.5
	
	func _init() -> void:
		strategy_name = "Enhanced Thrusters"
		description = "Increases thrust force by 50%"
		rarity = "Uncommon"
		price = 150
	
	func modify_thrust(base_thrust: float) -> float:
		return base_thrust * thrust_multiplier

# Maneuverability Strategy
class ManeuverabilityStrategy extends Strategy:
	@export var rotation_speed_multiplier: float = 1.75
	
	func _init() -> void:
		strategy_name = "Enhanced Maneuverability"
		description = "Increases rotation speed by 75%"
		rarity = "Uncommon"
		price = 180
	
	func modify_rotation(base_rotation: float) -> float:
		return base_rotation * rotation_speed_multiplier

# Afterburner Strategy
class AfterburnerStrategy extends Strategy:
	@export var boost_multiplier_increase: float = 1.0
	@export var boost_duration_multiplier: float = 1.5
	
	func _init() -> void:
		strategy_name = "Afterburner"
		description = "Increases boost strength and duration"
		rarity = "Rare"
		price = 350
	
	func apply_to_component(component: Component) -> void:
		super.apply_to_component(component)
		
		if component is MovementComponent:
			var movement = component as MovementComponent
			movement.boost_multiplier += boost_multiplier_increase
			movement.boost_duration *= boost_duration_multiplier
	
	func remove_from_component() -> void:
		if owner_component is MovementComponent:
			var movement = owner_component as MovementComponent
			movement.boost_multiplier -= boost_multiplier_increase
			movement.boost_duration /= boost_duration_multiplier
		super.remove_from_component()

# Inertial Dampeners Strategy
class InertialDampenersStrategy extends Strategy:
	@export var dampening_factor_improvement: float = 0.05
	
	func _init() -> void:
		strategy_name = "Inertial Dampeners"
		description = "Improves handling by reducing drift"
		rarity = "Rare"
		price = 250
	
	func apply_to_component(component: Component) -> void:
		super.apply_to_component(component)
		
		if component is MovementComponent:
			var movement = component as MovementComponent
			# Lower dampening factor means less drift
			movement.dampening_factor -= dampening_factor_improvement
	
	func remove_from_component() -> void:
		if owner_component is MovementComponent:
			var movement = owner_component as MovementComponent
			movement.dampening_factor += dampening_factor_improvement
		super.remove_from_component()
