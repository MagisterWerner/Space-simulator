class_name Laser
extends Node2D

@export var speed = 1000
@export var damage = 10
@export var lifetime = 2.0
@export var is_player_laser = true

var direction = Vector2.RIGHT
var life_timer = 0.0

func _ready():
	# Set properties
	z_index = 8
	life_timer = lifetime
	add_to_group("lasers")

func _process(delta):
	# Move in the current direction
	position += direction * speed * delta
	
	# Update lifetime
	life_timer -= delta
	if life_timer <= 0:
		queue_free()

func _draw():
	# This is a fallback in case the Sprite2D child isn't present
	if not has_node("Sprite2D"):
		var color = Color.GREEN if is_player_laser else Color.RED
		draw_rect(Rect2(-8, -2, 16, 4), color)

func hit_target():
	queue_free()

func get_collision_rect():
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		var scaled_size = texture_size * sprite.scale
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	else:
		# Fallback collision rect
		return Rect2(-8, -2, 16, 4)
