# strategy.gd
extends Resource
class_name Strategy

# Base class for all strategies that can be applied to components
# Each strategy modifies specific properties of a component

@export var strategy_name: String = "Base Strategy"
@export var description: String = "Base strategy class"
@export var icon_texture: Texture2D
@export var rarity: String = "Common"  # Common, Uncommon, Rare, Epic, Legendary
@export var price: int = 100

# Strategy-specific properties
var owner_component: Component = null

func apply_to_component(component: Component) -> void:
	owner_component = component

func remove_from_component() -> void:
	owner_component = null

# ---------------------------------------------------------

# weapon_strategies.gd
extends Resource
class_name WeaponStrategies

# Double Damage Strategy
class DoubleDamageStrategy extends Strategy:
	func _init() -> void:
		strategy_name = "Double Damage"
		description = "Doubles the damage of your weapon"
		rarity = "Rare"
		price = 300
	
	func modify_projectile_damage(base_damage: float) -> float:
		return base_damage * 2.0

# Rapid Fire Strategy
class RapidFireStrategy extends Strategy:
	@export var fire_rate_multiplier: float = 1.75
	
	func _init() -> void:
		strategy_name = "Rapid Fire"
		description = "Increases fire rate by 75%"
		rarity = "Uncommon"
		price = 200
	
	func apply_to_component(component: Component) -> void:
		super.apply_to_component(component)
		if component is WeaponComponent:
			component.fire_rate *= fire_rate_multiplier
	
	func remove_from_component() -> void:
		if owner_component is WeaponComponent:
			owner_component.fire_rate /= fire_rate_multiplier
		super.remove_from_component()

# Piercing Shot Strategy
class PiercingShotStrategy extends Strategy:
	func _init() -> void:
		strategy_name = "Piercing Shot"
		description = "Projectiles can pierce through enemies"
		rarity = "Epic"
		price = 500
	
	func modify_projectile(projectile: Node) -> void:
		if projectile.has_method("set_piercing"):
			projectile.set_piercing(true)

# Spread Shot Strategy
class SpreadShotStrategy extends Strategy:
	@export var num_additional_projectiles: int = 2
	@export var spread_angle: float = 15.0  # Degrees
	
	func _init() -> void:
		strategy_name = "Spread Shot"
		description = "Fires additional projectiles in a spread pattern"
		rarity = "Legendary"
		price = 750
	
	func apply_to_component(component: Component) -> void:
		super.apply_to_component(component)
		
		if component is WeaponComponent:
			# Connect to the weapon fired signal to create additional projectiles
			component.weapon_fired.connect(_on_weapon_fired)
	
	func remove_from_component() -> void:
		if owner_component is WeaponComponent:
			owner_component.weapon_fired.disconnect(_on_weapon_fired)
		super.remove_from_component()
	
	func _on_weapon_fired(projectile) -> void:
		if not is_instance_valid(projectile) or not owner_component:
			return
		
		var weapon = owner_component as WeaponComponent
		
		for i in range(num_additional_projectiles):
			# Create side projectiles with angle offsets
			var side_projectile = weapon.projectile_scene.instantiate()
			projectile.get_parent().add_child(side_projectile)
			
			# Calculate angle offset (alternating left and right)
			var offset = spread_angle * (i + 1) / 2.0
			if i % 2 == 0:
				offset *= -1.0
			
			# Set properties similar to original projectile
			side_projectile.global_position = projectile.global_position
			side_projectile.global_rotation = projectile.global_rotation + deg_to_rad(offset)
			
			# Configure the projectile
			if side_projectile.has_method("set_damage"):
				side_projectile.set_damage(weapon.damage)
			
			if side_projectile.has_method("set_speed"):
				side_projectile.set_speed(weapon.projectile_speed)
			
			if side_projectile.has_method("set_lifespan"):
				side_projectile.set_lifespan(weapon.projectile_lifespan)
			
			# Mark the shooter to prevent self-damage
			if side_projectile.has_method("set_shooter"):
				side_projectile.set_shooter(weapon.owner_entity)

# ---------------------------------------------------------

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
	
	func modify_shield_damage(damage_amount: float) -> float:
		if randf() <= reflection_chance:
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

# ---------------------------------------------------------

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
