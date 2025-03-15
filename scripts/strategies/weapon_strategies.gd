# scripts/strategies/weapon_strategies.gd
extends Resource

# Base Weapon Strategy class
class WeaponStrategy extends Strategy:
	func _init() -> void:
		target_component_type = "WeaponComponent"
	
	func can_apply_to(component) -> bool:
		return component != null and component.get_class() == "WeaponComponent"

# Double Damage Strategy
class DoubleDamageStrategy extends WeaponStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Double Damage"
		description = "Doubles weapon damage"
		price = 500
		affected_properties = ["damage_multiplier"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.damage_multiplier *= 2.0
	
	func _restore_component() -> void:
		if target_component:
			target_component.damage_multiplier /= 2.0
	
	func get_property_value():
		return 2.0

# Rapid Fire Strategy
class RapidFireStrategy extends WeaponStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Rapid Fire"
		description = "Reduces cooldown between shots by 30%"
		price = 400
		affected_properties = ["cooldown_multiplier"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.cooldown_multiplier *= 0.7
	
	func _restore_component() -> void:
		if target_component:
			target_component.cooldown_multiplier /= 0.7
	
	func get_property_value():
		return 0.7

# Piercing Shot Strategy
class PiercingShotStrategy extends WeaponStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Piercing Shot"
		description = "Projectiles pass through targets"
		price = 600
		affected_properties = ["piercing"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.piercing = true
	
	func _restore_component() -> void:
		if target_component:
			target_component.piercing = false
	
	func get_property_value():
		return true

# Spread Shot Strategy
class SpreadShotStrategy extends WeaponStrategy:
	func _init() -> void:
		super._init()
		strategy_name = "Spread Shot"
		description = "Fires multiple projectiles in a spread pattern"
		price = 450
		affected_properties = ["projectile_count"]
	
	func _modify_component() -> void:
		if target_component:
			target_component.projectile_count += 2
	
	func _restore_component() -> void:
		if target_component:
			target_component.projectile_count -= 2
	
	func get_property_value():
		return 2
