extends RefCounted
class_name WeaponStrategies

# Base weapon strategy class
class WeaponStrategy:
	var owner_component = null
	var name: String = "Weapon Strategy"
	var description: String = "Base weapon strategy"
	var icon_texture: Texture2D = null
	var price: int = 100
	
	func apply() -> void:
		pass
	
	func remove() -> void:
		pass
	
	func modify_projectile(_projectile) -> void:
		pass
	
	func get_name() -> String:
		return name
	
	func get_description() -> String:
		return description
	
	func get_price() -> int:
		return price

# Double damage strategy - increases weapon damage
class DoubleDamageStrategy extends WeaponStrategy:
	var original_damage: float = 0.0
	
	func _init() -> void:
		name = "Double Damage"
		description = "Doubles weapon damage"
		price = 300
	
	func apply() -> void:
		if not owner_component:
			return
			
		# Store original damage
		original_damage = owner_component.damage
		
		# Double the damage
		owner_component.damage *= 2.0
	
	func remove() -> void:
		if not owner_component or original_damage <= 0:
			return
			
		# Restore original damage
		owner_component.damage = original_damage
	
	func modify_projectile(projectile) -> void:
		# Make projectile larger to show increased power
		if "scale" in projectile:
			var original_scale = projectile.scale
			projectile.scale = original_scale * 1.2
		
		# Change color to indicate more power
		if "modulate" in projectile:
			var original_color = projectile.modulate
			projectile.modulate = Color(
				min(original_color.r * 1.2, 1.0),
				original_color.g * 0.8,
				original_color.b * 0.8,
				original_color.a
			)

# Rapid fire strategy - increases fire rate
class RapidFireStrategy extends WeaponStrategy:
	var original_fire_rate: float = 0.0
	
	func _init() -> void:
		name = "Rapid Fire"
		description = "Increases fire rate by 50%"
		price = 250
	
	func apply() -> void:
		if not owner_component:
			return
			
		# Store original fire rate
		original_fire_rate = owner_component.fire_rate
		
		# Increase fire rate
		owner_component.fire_rate *= 1.5
	
	func remove() -> void:
		if not owner_component or original_fire_rate <= 0:
			return
			
		# Restore original fire rate
		owner_component.fire_rate = original_fire_rate
	
	func modify_projectile(projectile) -> void:
		# Make projectile slightly smaller for rapid fire
		if "scale" in projectile:
			var original_scale = projectile.scale
			projectile.scale = original_scale * 0.9
		
		# Change color slightly
		if "modulate" in projectile:
			var original_color = projectile.modulate
			projectile.modulate = Color(
				original_color.r,
				original_color.g * 1.2,
				original_color.b * 1.2,
				original_color.a
			)

# Piercing shot strategy - allows projectiles to pierce through targets
class PiercingShotStrategy extends WeaponStrategy:
	func _init() -> void:
		name = "Piercing Shot"
		description = "Projectiles pierce through targets"
		price = 350
	
	func apply() -> void:
		# Nothing to do here - we modify projectiles when fired
		pass
	
	func remove() -> void:
		# Nothing to undo
		pass
	
	func modify_projectile(projectile) -> void:
		# Enable piercing
		if projectile.has_method("set_piercing"):
			projectile.set_piercing(true, 3)  # Pierce up to 3 targets
		elif "pierce_targets" in projectile:
			projectile.pierce_targets = true
			projectile.pierce_count = 3
		
		# Modify appearance to show piercing capability
		if "modulate" in projectile:
			var original_color = projectile.modulate
			projectile.modulate = Color(
				original_color.r * 0.8,
				original_color.g * 0.8,
				min(original_color.b * 1.5, 1.0),
				original_color.a
			)
		
		# Make projectile longer to indicate piercing
		if "scale" in projectile:
			var original_scale = projectile.scale
			projectile.scale = Vector2(original_scale.x * 1.5, original_scale.y)

# Spread shot strategy - fires multiple projectiles in a spread pattern
class SpreadShotStrategy extends WeaponStrategy:
	var spread_count: int = 3
	var spread_angle: float = 0.2  # Radians
	
	func _init() -> void:
		name = "Spread Shot"
		description = "Fires 3 projectiles in a spread pattern"
		price = 300
	
	func apply() -> void:
		if not owner_component:
			return
			
		# Connect to weapon fired signal if not already connected
		if not owner_component.is_connected("weapon_fired", _on_weapon_fired):
			owner_component.weapon_fired.connect(_on_weapon_fired)
	
	func remove() -> void:
		if not owner_component:
			return
			
		# Disconnect from weapon fired signal
		if owner_component.is_connected("weapon_fired", _on_weapon_fired):
			owner_component.disconnect("weapon_fired", _on_weapon_fired)
	
	func _on_weapon_fired(first_projectile) -> void:
		# First projectile is already fired, add spread projectiles
		# Skip if not valid or no owner
		if not owner_component or not is_instance_valid(first_projectile):
			return
		
		# Calculate base direction from the first projectile
		var base_direction = Vector2.RIGHT.rotated(owner_component.global_rotation)
		
		# Fire additional projectiles with angle offsets
		for i in range(1, spread_count):
			var angle_offset = spread_angle * (i % 2 == 0 ? 1 : -1) * (i / 2 + 0.5)
			var direction = base_direction.rotated(angle_offset)
			
			# Create projectile
			var projectile
			if has_node("/root/ProjectilePoolManager"):
				var spawn_position = owner_component.global_position + owner_component.muzzle_offset.rotated(owner_component.global_rotation)
				projectile = ProjectilePoolManager.get_projectile("laser", spawn_position, direction, owner_component.owner_entity)
			else:
				# Fallback to create projectile directly
				projectile = owner_component._create_projectile()
				
			# If we have a projectile, adjust direction
			if projectile:
				if projectile.has_method("fire"):
					projectile.fire(direction, owner_component.owner_entity)
				else:
					projectile.rotation = direction.angle()
	
	func modify_projectile(projectile) -> void:
		# Make each projectile slightly smaller for spread shot
		if "scale" in projectile:
			var original_scale = projectile.scale
			projectile.scale = original_scale * 0.85
		
		# Reduce damage slightly for balance
		if projectile.has_method("set_damage"):
			var current_damage = projectile.damage
			projectile.set_damage(current_damage * 0.8)
		elif "damage" in projectile:
			projectile.damage *= 0.8
