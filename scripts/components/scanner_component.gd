# shield_component.gd
extends Component
class_name ShieldComponent

signal shield_damaged(current, maximum)
signal shield_depleted()
signal shield_recharged()
signal shield_hit(damage, position)

@export var max_shield: float = 100.0
@export var recharge_rate: float = 5.0
@export var recharge_delay: float = 3.0
@export var damage_reduction: float = 0.2
@export var shield_color: Color = Color(0.2, 0.5, 1.0, 0.7)
@export var hit_flash_duration: float = 0.2

var current_shield: float = max_shield
var recharge_timer: float = 0.0
var is_recharging: bool = true
var is_depleted: bool = false
var hit_flash_timer: float = 0.0
var shield_visual: Node2D

func _initialize():
	create_shield_visual()

func _process(delta):
	if !is_recharging and recharge_timer > 0:
		recharge_timer -= delta
		if recharge_timer <= 0:
			is_recharging = true
	
	if is_recharging and current_shield < max_shield:
		current_shield = min(current_shield + recharge_rate * delta, max_shield)
		emit_signal("shield_damaged", current_shield, max_shield)
		
		if is_depleted and current_shield > 0:
			is_depleted = false
			emit_signal("shield_recharged")
	
	update_shield_visual(delta)

func absorb_damage(damage: float, impact_position: Vector2 = Vector2.ZERO) -> float:
	if current_shield <= 0:
		return damage
	
	var absorbed = min(damage * (1.0 - damage_reduction), current_shield)
	var remaining_damage = damage - absorbed
	
	current_shield -= absorbed
	recharge_timer = recharge_delay
	is_recharging = false
	hit_flash_timer = hit_flash_duration
	
	emit_signal("shield_damaged", current_shield, max_shield)
	emit_signal("shield_hit", absorbed, impact_position)
	
	if current_shield <= 0 and !is_depleted:
		is_depleted = true
		emit_signal("shield_depleted")
	
	return remaining_damage

func create_shield_visual():
	if shield_visual != null:
		shield_visual.queue_free()
	
	shield_visual = Node2D.new()
	shield_visual.name = "ShieldVisual"
	shield_visual.z_index = 10
	entity.add_child(shield_visual)
	
	shield_visual.modulate = shield_color
	shield_visual.modulate.a = current_shield / max_shield * shield_color.a

func update_shield_visual(delta):
	if !shield_visual:
		return
	
	var target_alpha = (current_shield / max_shield) * shield_color.a
	
	if hit_flash_timer > 0:
		hit_flash_timer -= delta
		target_alpha = min(1.0, target_alpha * 2.0)
	
	shield_visual.modulate.a = lerp(shield_visual.modulate.a, target_alpha, 10 * delta)

func _draw_shield():
	var radius = 30.0
	var sprite = entity.get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		radius = max(texture_size.x, texture_size.y) * sprite.scale.x / 2.0 + 5.0
	
	shield_visual.draw_circle(Vector2.ZERO, radius, shield_color)
