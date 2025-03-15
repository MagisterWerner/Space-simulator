extends Node
class_name ShieldComponent

# Shield signals
signal shield_damaged(amount, source)
signal shield_depleted()
signal shield_recharged()
signal shield_changed(current, maximum)

# Shield properties
@export var max_shield: float = 100.0
@export var recharge_rate: float = 5.0
@export var recharge_delay: float = 3.0
@export var damage_reduction: float = 0.2
@export var enabled: bool = true

# Current shield state
var current_shield: float = max_shield
var recharging: bool = false
var recharge_timer: float = 0.0
var shield_active: bool = true

# Reference to owner entity and strategy
var owner_entity: Node = null
var applied_strategies = []

# Visual effect nodes
var _shield_effect: Node2D = null
var _hit_effect: Node2D = null

func _ready() -> void:
	# Get reference to owner entity (parent node)
	owner_entity = get_parent()
	
	# Initialize shield
	current_shield = max_shield
	
	# Create shield visual effect if needed
	_create_shield_effect()
	
	# Connect to damage signals if parent has a health component
	var health_component = owner_entity.get_node_or_null("HealthComponent")
	if health_component and health_component.has_signal("damaged"):
		if not health_component.is_connected("damaged", _on_health_damaged):
			health_component.connect("damaged", _on_health_damaged)

func _process(delta: float) -> void:
	if not enabled:
		return
		
	# Handle shield recharging
	if recharging and shield_active:
		current_shield += recharge_rate * delta
		current_shield = clamp(current_shield, 0, max_shield)
		
		# Emit shield changed signal
		shield_changed.emit(current_shield, max_shield)
		
		# Check if fully recharged
		if current_shield >= max_shield:
			current_shield = max_shield
			recharging = false
			shield_recharged.emit()
	
	# Handle recharge delay timer
	elif not recharging and current_shield < max_shield:
		recharge_timer += delta
		if recharge_timer >= recharge_delay:
			recharging = true
			recharge_timer = 0.0

# Apply damage to shield
func apply_damage(amount: float, damage_type: String = "", source = null) -> float:
	if not enabled or not shield_active or current_shield <= 0:
		return amount  # Pass through all damage
	
	# Apply any damage reduction from strategies
	var actual_damage = amount
	for strategy in applied_strategies:
		if strategy.has_method("modify_incoming_damage"):
			actual_damage = strategy.modify_incoming_damage(actual_damage, damage_type)
	
	# Calculate how much damage the shield can absorb
	var damage_absorbed = min(current_shield, actual_damage * (1.0 - damage_reduction))
	var damage_remaining = actual_damage - damage_absorbed
	
	# Reduce shield
	var old_shield = current_shield
	current_shield -= damage_absorbed
	
	# Show shield hit effect
	_show_hit_effect()
	
	# Reset recharge timer
	recharge_timer = 0.0
	recharging = false
	
	# Emit shield damaged signal
	shield_damaged.emit(damage_absorbed, source)
	shield_changed.emit(current_shield, max_shield)
	
	# Check if shield is depleted
	if old_shield > 0 and current_shield <= 0:
		shield_depleted.emit()
	
	# Return remaining damage to be applied to health
	return damage_remaining

# Enable or disable the shield
func set_active(active: bool) -> void:
	shield_active = active
	
	# Update visuals
	if _shield_effect:
		_shield_effect.visible = active and current_shield > 0

# Create shield visual effect
func _create_shield_effect() -> void:
	# Check if we already have a shield effect
	_shield_effect = get_node_or_null("ShieldEffect")
	
	if not _shield_effect:
		# Create a simple shield effect
		_shield_effect = Node2D.new()
		_shield_effect.name = "ShieldEffect"
		add_child(_shield_effect)
		
		# Create a simple shield sprite or effect
		# This can be replaced with a more complex effect in a real implementation
		var shield_sprite = Sprite2D.new()
		shield_sprite.name = "ShieldSprite"
		_shield_effect.add_child(shield_sprite)
		
		# Set properties
		shield_sprite.modulate = Color(0.3, 0.7, 1.0, 0.3)
		
		# Try to find a circular texture or create one
		var circle_texture = load("res://assets/effects/shield_circle.png")
		if circle_texture:
			shield_sprite.texture = circle_texture
		else:
			# Generate a basic circle texture
			var image = Image.create(64, 64, false, Image.FORMAT_RGBA8)
			image.fill(Color(1, 1, 1, 0.5))
			
			# Draw a circle
			for x in range(64):
				for y in range(64):
					var dist = Vector2(x - 32, y - 32).length()
					if dist > 30:
						image.set_pixel(x, y, Color(1, 1, 1, 0))
			
			var texture = ImageTexture.create_from_image(image)
			shield_sprite.texture = texture
		
		# Scale based on owner size if possible
		if owner_entity is Node2D:
			var size = 1.0
			if owner_entity.has_method("get_size"):
				size = owner_entity.get_size()
			elif owner_entity is CollisionShape2D and owner_entity.shape is CircleShape2D:
				size = owner_entity.shape.radius
			else:
				# Default size
				size = 30.0
				
			shield_sprite.scale = Vector2(size / 32.0, size / 32.0) * 1.2
		
	# Initialize visibility
	_shield_effect.visible = shield_active and current_shield > 0

# Show hit effect when shield takes damage
func _show_hit_effect() -> void:
	if not _shield_effect:
		return
		
	# Flash the shield
	var shield_sprite = _shield_effect.get_node_or_null("ShieldSprite")
	if shield_sprite:
		var original_color = shield_sprite.modulate
		shield_sprite.modulate = Color(1, 1, 1, 0.7)
		
		# Reset after a short time
		var tween = create_tween()
		tween.tween_property(shield_sprite, "modulate", original_color, 0.2)

# React to owner entity taking damage (intercept damage)
func _on_health_damaged(amount: float, type: String, source) -> void:
	# This is just a notification that the entity was damaged
	# The actual damage absorption happens in apply_damage
	pass

# Apply a strategy to the shield
func apply_strategy(strategy) -> void:
	# Don't apply the same strategy twice
	for existing_strategy in applied_strategies:
		if existing_strategy.get_script() == strategy.get_script():
			return
	
	# Set the strategy's owner component
	strategy.owner_component = self
	
	# Apply the strategy
	strategy.apply()
	
	# Add to the list of applied strategies
	applied_strategies.append(strategy)

# Remove a strategy from the shield
func remove_strategy(strategy) -> void:
	var index = applied_strategies.find(strategy)
	if index >= 0:
		# Remove the strategy's effects
		strategy.remove()
		
		# Remove from the list
		applied_strategies.remove_at(index)

# Get current shield percentage (0.0 to 1.0)
func get_shield_percent() -> float:
	if max_shield <= 0:
		return 0.0
	return current_shield / max_shield

# Fully recharge the shield
func recharge_shield() -> void:
	var old_shield = current_shield
	current_shield = max_shield
	recharging = false
	
	shield_changed.emit(current_shield, max_shield)
	
	if old_shield <= 0 and current_shield > 0:
		shield_recharged.emit()

# Reset shield to default values
func reset() -> void:
	current_shield = max_shield
	recharging = false
	recharge_timer = 0.0
	shield_active = true
	
	shield_changed.emit(current_shield, max_shield)
	
	if _shield_effect:
		_shield_effect.visible = shield_active
