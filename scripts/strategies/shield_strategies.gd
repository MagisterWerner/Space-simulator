# shield_strategies.gd
extends Resource
class_name ShieldStrategies

# Reinforced Shield Strategy
class ReinforcedShieldStrategy extends Strategy:
	@export var max_shield_multiplier: float = 1.5
	
	func _init() -> void:
		strategy_name = "Reinforced Shield"
		description = "Increases shield capacity by 50%"
		rarity = "Uncommon"
		price = 200
	
	func apply_to_component(component: Component) -> void:
		super.apply_to_component(component)
		
		if component is ShieldComponent:
			var shield = component as ShieldComponent
			shield.set_max_shield(shield.max_shield * max_shield_multiplier)
	
	func remove_from_component() -> void:
		if owner_component is ShieldComponent:
			var shield = owner_component as ShieldComponent
			shield.set_max_shield(shield.max_shield / max_shield_multiplier)
		super.remove_from_component()

# Fast Recharge Strategy
class FastRechargeStrategy extends Strategy:
	@export var recharge_rate_multiplier: float = 2.0
	@export var recharge_delay_reduction: float = 1.0
	
	func _init() -> void:
		strategy_name = "Fast Recharge"
		description = "Doubles shield recharge rate and reduces recharge delay"
		rarity = "Rare"
		price = 300
	
	func apply_to_component(component: Component) -> void:
		super.apply_to_component(component)
		
		if component is ShieldComponent:
			var shield = component as ShieldComponent
			shield.recharge_rate *= recharge_rate_multiplier
			shield.recharge_delay = max(0.5, shield.recharge_delay - recharge_delay_reduction)
	
	func remove_from_component() -> void:
		if owner_component is ShieldComponent:
			var shield = owner_component as ShieldComponent
			shield.recharge_rate /= recharge_rate_multiplier
			shield.recharge_delay += recharge_delay_reduction
		super.remove_from_component()

# Reflective Shield Strategy
class ReflectiveShieldStrategy extends Strategy:
	@export var reflection_chance: float = 0.25
	
	func _init() -> void:
		strategy_name = "Reflective Shield"
		description = "25% chance to reflect projectiles back at enemies"
		rarity = "Epic"
		price = 500
	
	func modify_shield_damage(damage_amount: float, projectile_id: int = 0) -> float:
		# Get SeedManager singleton
		var seed_manager = Engine.get_singleton("SeedManager")
		
		# Use a deterministic random value based on projectile_id
		# If no projectile_id is provided, use component's instance_id
		var object_id = projectile_id if projectile_id > 0 else (owner_component.get_instance_id() if owner_component else 0)
		
		if seed_manager and seed_manager.get_random_value(object_id, 0.0, 1.0) <= reflection_chance:
			# Reflect projectile
			# This would require implementation in the game's projectile system
			# to actually reflect the projectile that hit the shield
			return 0  # No damage taken when reflected
		return damage_amount

# Absorbent Shield Strategy
class AbsorbentShieldStrategy extends Strategy:
	@export var absorption_percentage: float = 0.25
	
	func _init() -> void:
		strategy_name = "Absorbent Shield"
		description = "Convert 25% of damage taken to shield energy"
		rarity = "Legendary"
		price = 700
	
	func modify_shield_damage(damage_amount: float) -> float:
		if owner_component is ShieldComponent:
			var shield = owner_component as ShieldComponent
			
			# Calculate energy gained from damage
			var energy_gained = damage_amount * absorption_percentage
			
			# Add to max shield (one-time bonus, not permanent)
			shield.current_shield = min(shield.max_shield, shield.current_shield + energy_gained)
			shield.shield_changed.emit(shield.current_shield, shield.max_shield)
			
		return damage_amount
