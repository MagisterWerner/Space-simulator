extends Component
class_name HealthComponent

signal health_changed(current, maximum)
signal died()

@export var max_health: float = 100.0
@export var invulnerability_time: float = 1.0
@export var hit_flash_duration: float = 0.2

var current_health: float = 100.0
var is_invulnerable: bool = false
var invulnerability_timer: float = 0.0
var hit_flash_timer: float = 0.0
var sprite: Sprite2D = null
var health_bar: ColorRect = null

func _initialize():
	current_health = max_health
	
	# Find the sprite if it exists
	sprite = entity.get_node_or_null("Sprite2D")
	
	# Try to find a health bar
	health_bar = entity.get_node_or_null("HealthBar")
	
	# Initial update for any health bars
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
	
	# Visual feedback if sprite exists
	if sprite:
		sprite.modulate = Color.RED
	
	# Signal that health changed
	emit_signal("health_changed", current_health, max_health)
	
	# Update health bar if it exists
	update_health_bar()
	
	if current_health <= 0:
		emit_signal("died")
		return true
	else:
		set_invulnerable(invulnerability_time)
		return false

func heal(amount: float):
	current_health = min(current_health + amount, max_health)
	emit_signal("health_changed", current_health, max_health)
	
	# Update health bar if it exists
	update_health_bar()

func set_invulnerable(duration: float):
	is_invulnerable = true
	invulnerability_timer = duration
	
	if sprite:
		sprite.modulate.a = 0.5

func get_health_percent() -> float:
	return current_health / max_health

func reset_health():
	# Fully restore health
	current_health = max_health
	
	# Reset invulnerability and visual states
	is_invulnerable = false
	invulnerability_timer = 0.0
	hit_flash_timer = 0.0
	
	# Reset sprite appearance if it exists
	if sprite:
		sprite.modulate = Color.WHITE
		sprite.modulate.a = 1.0
	
	# Update health bar to show full health
	emit_signal("health_changed", current_health, max_health)
	update_health_bar()
	
	# Optional: Set brief invulnerability period after respawn
	set_invulnerable(2.0)

func update_health_bar():
	# Update the attached health bar if one exists
	if health_bar:
		# Get the original parent rect size (for full health)
		var original_rect = Rect2(health_bar.position, health_bar.size)
		var parent_width = original_rect.size.x
		
		# Calculate new width based on health percentage
		var percent = get_health_percent()
		var new_width = parent_width * percent
		
		# Update the width of the health bar
		health_bar.size.x = new_width
		
		# Optional: Change color based on health percentage
		if percent < 0.25:
			health_bar.color = Color(1, 0, 0)  # Red when low
		elif percent < 0.5:
			health_bar.color = Color(1, 0.5, 0)  # Orange when medium
		else:
			health_bar.color = Color(0, 0.8, 0)  # Green when high
