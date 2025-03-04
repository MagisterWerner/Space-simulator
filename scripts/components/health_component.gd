# health_component.gd
extends Component
class_name HealthComponent

signal health_changed(current, maximum)
signal died

@export var max_health: float = 100.0
@export var invulnerability_time: float = 1.0
@export var hit_flash_duration: float = 0.2

var current_health: float
var is_invulnerable: bool = false
var invulnerability_timer: float = 0.0
var hit_flash_timer: float = 0.0
var sprite: Sprite2D
var health_bar: ColorRect

func _initialize():
	current_health = max_health
	sprite = entity.get_node_or_null("Sprite2D")
	health_bar = entity.get_node_or_null("HealthBar")
	update_health_bar()

func _process(delta):
	if is_invulnerable:
		invulnerability_timer -= delta
		if invulnerability_timer <= 0:
			is_invulnerable = false
			if sprite:
				sprite.modulate.a = 1.0
	
	if hit_flash_timer > 0:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0 and sprite:
			sprite.modulate = Color.WHITE

func take_damage(amount: float) -> bool:
	if is_invulnerable:
		return false
		
	current_health -= amount
	hit_flash_timer = hit_flash_duration
	
	if sprite:
		sprite.modulate = Color.RED
	
	emit_signal("health_changed", current_health, max_health)
	update_health_bar()
	
	if current_health <= 0:
		emit_signal("died")
		return true
	
	set_invulnerable(invulnerability_time)
	return false

func heal(amount: float):
	current_health = min(current_health + amount, max_health)
	emit_signal("health_changed", current_health, max_health)
	update_health_bar()

func set_invulnerable(duration: float):
	is_invulnerable = true
	invulnerability_timer = duration
	
	if sprite:
		sprite.modulate.a = 0.5

func get_health_percent() -> float:
	return current_health / max_health

func reset_health():
	current_health = max_health
	is_invulnerable = false
	invulnerability_timer = 0.0
	hit_flash_timer = 0.0
	
	if sprite:
		sprite.modulate = Color.WHITE
		sprite.modulate.a = 1.0
	
	emit_signal("health_changed", current_health, max_health)
	update_health_bar()
	set_invulnerable(2.0)

func update_health_bar():
	if not health_bar:
		return
		
	var parent_width = health_bar.size.x
	var percent = get_health_percent()
	health_bar.size.x = parent_width * percent
	
	if percent < 0.25:
		health_bar.color = Color(1, 0, 0)
	elif percent < 0.5:
		health_bar.color = Color(1, 0.5, 0)
	else:
		health_bar.color = Color(0, 0.8, 0)
