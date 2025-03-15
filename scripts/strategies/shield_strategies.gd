extends RefCounted
class_name ShieldStrategies

# Base shield strategy class
class ShieldStrategy:
	var owner_component = null
	var name: String = "Shield Strategy"
	var description: String = "Base shield strategy"
	var icon_texture: Texture2D = null
	var price: int = 100
	
	func apply() -> void:
		pass
	
	func remove() -> void:
		pass
	
	func get_name() -> String:
		return name
	
	func get_description() -> String:
		return description
	
	func get_price() -> int:
		return price

# Reinforced Shield - Doubles shield capacity
class ReinforcedShieldStrategy extends ShieldStrategy:
	var original_max_shield: float = 0.0
	
	func _init() -> void:
		name = "Reinforced Shield"
		description = "Doubles shield capacity"
		price = 250
	
	func apply() -> void:
		if not owner_component:
			return
			
		# Store original value
		original_max_shield = owner_component.max_shield
		
		# Double shield capacity
		owner_component.max_shield *= 2.0
		
		# Update current shield
		var percent = owner_component.current_shield / original_max_shield
		owner_component.current_shield = owner_component.max_shield * percent
		
		# Emit shield changed signal
		owner_component.shield_changed.emit(owner_component.current_shield, owner_component.max_shield)
	
	func remove() -> void:
		if not owner_component or original_max_shield <= 0:
			return
			
		# Calculate current percentage
		var percent = owner_component.current_shield / owner_component.max_shield
		
		# Restore original max shield
		owner_component.max_shield = original_max_shield
		
		# Update current shield based on percentage
		owner_component.current_shield = owner_component.max_shield * percent
		
		# Emit shield changed signal
		owner_component.shield_changed.emit(owner_component.current_shield, owner_component.max_shield)

# Fast Recharge - Reduces recharge delay and increases recharge rate
class FastRechargeStrategy extends ShieldStrategy:
	var original_recharge_rate: float = 0.0
	var original_recharge_delay: float = 0.0
	
	func _init() -> void:
		name = "Fast Recharge"
		description = "Reduces shield recharge delay by 50% and increases recharge rate by 50%"
		price = 300
	
	func apply() -> void:
		if not owner_component:
			return
			
		# Store original values
		original_recharge_rate = owner_component.recharge_rate
		original_recharge_delay = owner_component.recharge_delay
		
		# Apply bonuses
		owner_component.recharge_rate *= 1.5
		owner_component.recharge_delay *= 0.5
	
	func remove() -> void:
		if not owner_component:
			return
			
		# Restore original values
		owner_component.recharge_rate = original_recharge_rate
		owner_component.recharge_delay = original_recharge_delay

# Reflective Shield - Reflects some damage back to attackers
class ReflectiveShieldStrategy extends ShieldStrategy:
	var reflection_chance: float = 0.25
	var reflection_damage_percent: float = 0.3
	
	func _init() -> void:
		name = "Reflective Shield"
		description = "Has a 25% chance to reflect 30% of damage back to attackers"
		price = 350
	
	func apply() -> void:
		if not owner_component:
			return
			
		# Connect to shield damaged signal if not already connected
		if not owner_component.is_connected("shield_damaged", _on_shield_damaged):
			owner_component.connect("shield_damaged", _on_shield_damaged)
	
	func remove() -> void:
		if not owner_component:
			return
			
		# Disconnect from shield damaged signal
		if owner_component.is_connected("shield_damaged", _on_shield_damaged):
			owner_component.disconnect("shield_damaged", _on_shield_damaged)
	
	func _on_shield_damaged(amount: float, source) -> void:
		# Check for reflection
		if not is_instance_valid(source) or amount <= 0:
			return
		
		# Random chance to reflect
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		
		if rng.randf() < reflection_chance:
			# Calculate reflection damage
			var reflect_amount = amount * reflection_damage_percent
			
			# Apply reflection damage to source if it has a health component
			var health_component = source.get_node_or_null("HealthComponent")
			if health_component and health_component.has_method("apply_damage"):
				health_component.apply_damage(reflect_amount, "reflection", owner_component.owner_entity)
				
				# Visual effect (if we have access to effect manager)
				if has_node("/root/EffectPoolManager"):
					EffectPoolManager.shield_hit(source.global_position, 0, 1.0)
				
				# Play reflection sound if we have AudioManager
				if has_node("/root/AudioManager"):
					AudioManager.play_sfx("shield_reflect", owner_component.owner_entity.global_position)

# Absorbent Shield - Reduces incoming damage
class AbsorbentShieldStrategy extends ShieldStrategy:
	var original_damage_reduction: float = 0.0
	
	func _init() -> void:
		name = "Absorbent Shield"
		description = "Increases damage absorption by shield by 20%"
		price = 280
	
	func apply() -> void:
		if not owner_component:
			return
			
		# Store original value
		original_damage_reduction = owner_component.damage_reduction
		
		# Increase damage reduction
		owner_component.damage_reduction += 0.2
	
	func remove() -> void:
		if not owner_component:
			return
			
		# Restore original value
		owner_component.damage_reduction = original_damage_reduction
	
	# Method that can be called by shield component during damage calculations
	func modify_incoming_damage(amount: float, _damage_type: String) -> float:
		# Already handled by the component's damage_reduction property
		return amount
