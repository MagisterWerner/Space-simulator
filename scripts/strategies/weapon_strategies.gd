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
			if owner_component.weapon_fired.is_connected(_on_weapon_fired):
				owner_component.weapon_fired.disconnect(_on_weapon_fired)
		super.remove_from_component()
	
	func _on_weapon_fired(projectile) -> void:
		if not is_instance_valid(projectile) or not owner_component:
			return
		
		var weapon = owner_component as WeaponComponent
		
		# Make sure we can access the projectile's parent (should be a Node2D)
		if not projectile.get_parent() is Node2D:
			return
			
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
