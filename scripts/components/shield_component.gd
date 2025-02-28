extends Component
class_name ShieldComponent

signal shield_damaged(current, maximum)
signal shield_depleted()
signal shield_recharged()
signal shield_hit(damage, position)

@export var max_shield: float = 100.0
@export var recharge_rate: float = 5.0  # Shield points per second
@export var recharge_delay: float = 3.0  # Seconds after damage before recharging starts
@export var damage_reduction: float = 0.2  # Percentage of damage reduced (0.2 = 20%)
@export var shield_color: Color = Color(0.2, 0.5, 1.0, 0.7)  # Blue-ish transparent color
@export var hit_flash_duration: float = 0.2

var current_shield: float = max_shield
var recharge_timer: float = 0.0
var is_recharging: bool = true
var is_depleted: bool = false
var hit_flash_timer: float = 0.0
var shield_visual: Node2D = null

func _initialize():
	# Create shield visual if it doesn't exist
	create_shield_visual()

func _process(delta):
	# Handle shield recharge after delay
	if !is_recharging and recharge_timer > 0:
		recharge_timer -= delta
		if recharge_timer <= 0:
			is_recharging = true
	
	# Recharge shield if enabled
	if is_recharging and current_shield < max_shield:
		current_shield = min(current_shield + recharge_rate * delta, max_shield)
		emit_signal("shield_damaged", current_shield, max_shield)
		
		# If shield was depleted and now has charge, emit recharged signal
		if is_depleted and current_shield > 0:
			is_depleted = false
			emit_signal("shield_recharged")
	
	# Update shield visual
	update_shield_visual(delta)

func absorb_damage(damage: float, impact_position: Vector2 = Vector2.ZERO) -> float:
	# If shield is depleted, pass all damage through
	if current_shield <= 0:
		return damage
	
	# Calculate damage reduction
	var absorbed = min(damage * (1.0 - damage_reduction), current_shield)
	var remaining_damage = damage - absorbed
	
	# Apply damage to shield
	current_shield -= absorbed
	
	# Reset recharge timer and stop recharging
	recharge_timer = recharge_delay
	is_recharging = false
	
	# Flash effect
	hit_flash_timer = hit_flash_duration
	
	# Emit signals
	emit_signal("shield_damaged", current_shield, max_shield)
	emit_signal("shield_hit", absorbed, impact_position)
	
	# Check if shield was depleted
	if current_shield <= 0 and !is_depleted:
		is_depleted = true
		emit_signal("shield_depleted")
	
	# Return damage that wasn't absorbed
	return remaining_damage

func create_shield_visual():
	# Remove existing shield visual if any
	if shield_visual != null:
		shield_visual.queue_free()
	
	# Create new shield visual
	shield_visual = Node2D.new()
	shield_visual.name = "ShieldVisual"
	shield_visual.z_index = 10  # Make sure it's drawn on top
	entity.add_child(shield_visual)
	
	# Set initial opacity based on shield percentage
	shield_visual.modulate = shield_color
	shield_visual.modulate.a = current_shield / max_shield * shield_color.a

func update_shield_visual(delta):
	if !shield_visual:
		return
	
	# Update shield opacity based on current shield level
	var target_alpha = (current_shield / max_shield) * shield_color.a
	
	# Increase alpha briefly when hit
	if hit_flash_timer > 0:
		hit_flash_timer -= delta
		target_alpha = min(1.0, target_alpha * 2.0)
	
	# Smoothly transition to target alpha
	shield_visual.modulate.a = lerp(shield_visual.modulate.a, target_alpha, 10 * delta)

func _draw_shield():
	# This is called by the shield visual node to draw the shield
	# Override in child class or customize at runtime
	
	# Get entity size (assume it has a sprite)
	var radius = 30.0  # Default
	var sprite = entity.get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		radius = max(texture_size.x, texture_size.y) * sprite.scale.x / 2.0 + 5.0
	
	# Draw shield circle
	shield_visual.draw_circle(Vector2.ZERO, radius, shield_color)
