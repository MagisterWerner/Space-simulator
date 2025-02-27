extends Node2D

@export var speed = 1000
@export var damage = 10
@export var lifetime = 2.0  # Seconds before auto-destruction
@export var is_player_laser = true  # Whether this is from player (affects collision)

var direction = Vector2.RIGHT  # Default direction
var life_timer = 0.0

func _ready():
	# Set a z-index that's high but below the player/enemy
	z_index = 8
	
	# Start the lifetime timer
	life_timer = lifetime
	
	# Add to lasers group for collision detection
	add_to_group("lasers")
	
	# Ensure the sprite is oriented in the direction of travel
	if has_node("Sprite2D"):
		get_node("Sprite2D").rotation = 0

func _process(delta):
	# Move in the current direction
	position += direction * speed * delta
	
	# Update lifetime
	life_timer -= delta
	if life_timer <= 0:
		queue_free()
	
	# Keep visible
	queue_redraw()

func _draw():
	# This is a fallback in case the Sprite2D child isn't present
	if not has_node("Sprite2D"):
		var color = Color.GREEN if is_player_laser else Color.RED
		draw_rect(Rect2(-8, -2, 16, 4), color)

# Called when the laser hits something
func hit_target():
	# Destroy the laser on hit
	queue_free()

# Get the collision shape for hit detection
func get_collision_rect():
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		var scaled_size = texture_size * sprite.scale
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	else:
		# Fallback collision rect if no sprite
		return Rect2(-8, -2, 16, 4)
