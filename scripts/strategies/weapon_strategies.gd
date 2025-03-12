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

# Spread Shot Strategy - Optimized
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
			if not component.weapon_fired.is_connected(_on_weapon_fired):
				component.weapon_fired.connect(_on_weapon_fired)
	
	func remove_from_component() -> void:
		if owner_component is WeaponComponent:
			if owner_component.weapon_fired.is_connected(_on_weapon_fired):
				owner_component.weapon_fired.disconnect(_on_weapon_fired)
		super.remove_from_component()
	
	func _on_weapon_fired(projectile) -> void:
		if not is_instance_valid(projectile) or not owner_component or not projectile.get_parent() is Node2D:
			return
		
		var weapon = owner_component as WeaponComponent
		if not weapon.projectile_scene:
			return
			
		var parent = projectile.get_parent()
		var projectile_props = {
			"position": projectile.global_position,
			"rotation": projectile.global_rotation,
			"damage": weapon.damage if projectile.has_method("set_damage") else 0,
			"speed": weapon.projectile_speed if projectile.has_method("set_speed") else 0,
			"lifespan": weapon.projectile_lifespan if projectile.has_method("set_lifespan") else 0,
			"shooter": weapon.owner_entity if projectile.has_method("set_shooter") else null
		}
			
		for i in range(num_additional_projectiles):
			# Calculate angle offset (alternating left and right)
			var offset = spread_angle * (i + 1) / 2.0
			if i % 2 == 0:
				offset *= -1.0
			
			# Create side projectile efficiently
			var side_projectile = weapon.projectile_scene.instantiate()
			parent.add_child(side_projectile)
			
			# Set position and rotation
			side_projectile.global_position = projectile_props.position
			side_projectile.global_rotation = projectile_props.rotation + deg_to_rad(offset)
			
			# Configure the projectile properties - only set if available
			if side_projectile.has_method("set_damage") and projectile_props.damage > 0:
				side_projectile.set_damage(projectile_props.damage)
			
			if side_projectile.has_method("set_speed") and projectile_props.speed > 0:
				side_projectile.set_speed(projectile_props.speed)
			
			if side_projectile.has_method("set_lifespan") and projectile_props.lifespan > 0:
				side_projectile.set_lifespan(projectile_props.lifespan)
			
			# Mark the shooter to prevent self-damage
			if side_projectile.has_method("set_shooter") and projectile_props.shooter:
				side_projectile.set_shooter(projectile_props.shooter)
