extends Node2D

@export var movement_speed = 150
@export var max_health = 50
@export var fire_cooldown = 1.5  # Seconds between shots
@export var fire_range = 250  # Maximum firing range

# Reference to the state machine
@onready var state_machine = $StateMachine

# Original spawn position
var original_position = Vector2.ZERO

# Grid cell coordinates
var cell_x = -1
var cell_y = -1

# Combat variables
var current_health = max_health
var current_cooldown = 0.0
var laser_scene = preload("res://laser.tscn")
var is_hit = false
var hit_flash_timer = 0.0
var hit_flash_duration = 0.2

func _ready():
	# Set a high z-index but lower than player to ensure drawing order
	z_index = 5
	
	# Store the original position
	original_position = global_position
	
	# Calculate initial cell position
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		cell_x = int(floor(global_position.x / grid.cell_size.x))
		cell_y = int(floor(global_position.y / grid.cell_size.y))
	
	# Set up the sprite if it doesn't exist
	if not has_node("Sprite2D"):
		var sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		sprite.texture = load("res://sprites/ships_enemy/enemy_ship_1.png")
		add_child(sprite)
	
	# Initialize health
	current_health = max_health
	
	print("Enemy ready at position: ", global_position, " in cell: (", cell_x, ",", cell_y, ")")

func _process(delta):
	# Update shooting cooldown
	if current_cooldown > 0:
		current_cooldown -= delta
	
	# Update hit flash effect
	if is_hit:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0:
			is_hit = false
			if has_node("Sprite2D"):
				get_node("Sprite2D").modulate = Color.WHITE
	
	# Check if should fire
	var player = get_node_or_null("/root/Main/Player")
	if player and current_cooldown <= 0 and can_see_player(player):
		shoot_at_player(player)
		
	# Update the health bar
	var health_bar = get_node_or_null("HealthBar")
	if health_bar:
		# Update width based on current health percentage
		var health_percent = float(current_health) / max_health
		health_bar.size.x = 30 * health_percent
		
		# Center the health bar
		health_bar.position.x = -15

func _draw():
	# Only draw if sprite is missing
	if not has_node("Sprite2D"):
		# Draw the enemy as a red square with yellow border (fallback)
		var rect = Rect2(-16, -16, 32, 32)
		draw_rect(rect, Color(1.0, 0.0, 0.0, 1.0))
		draw_rect(rect, Color(1.0, 1.0, 0.0, 1.0), false, 2.0)

# Check if player is in the same cell
func is_player_in_same_cell():
	var player = get_node_or_null("/root/Main/Player")
	var grid = get_node_or_null("/root/Main/Grid")
	
	if player and grid:
		var player_cell_x = int(floor(player.global_position.x / grid.cell_size.x))
		var player_cell_y = int(floor(player.global_position.y / grid.cell_size.y))
		
		return player_cell_x == cell_x and player_cell_y == cell_y
	
	return false

# Update the current cell position
func update_cell_position():
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		var new_cell_x = int(floor(global_position.x / grid.cell_size.x))
		var new_cell_y = int(floor(global_position.y / grid.cell_size.y))
		
		if new_cell_x != cell_x or new_cell_y != cell_y:
			cell_x = new_cell_x
			cell_y = new_cell_y
			return true
	
	return false

# Set the state based on player presence
func check_for_player():
	if is_player_in_same_cell():
		state_machine.change_state("Follow")
	else:
		state_machine.change_state("Idle")

# Update enemy and state machine visibility and processing state
func update_active_state(is_active):
	# Update visibility
	visible = is_active
	
	# Update process states without using the overridden methods
	process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
	
	# Update state machine
	if state_machine:
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED

# Check if enemy is in a loaded chunk
func is_in_loaded_chunk():
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		var enemy_cell_x = int(floor(global_position.x / grid.cell_size.x))
		var enemy_cell_y = int(floor(global_position.y / grid.cell_size.y))
		return grid.loaded_cells.has(Vector2(enemy_cell_x, enemy_cell_y))
	return false

# Check if player is in firing range and visible
func can_see_player(player):
	# Check distance first (optimization)
	var distance = global_position.distance_to(player.global_position)
	if distance > fire_range:
		return false
	
	# Only shoot if in the same cell
	if not is_player_in_same_cell():
		return false
	
	# Check if player is invulnerable (don't shoot at respawning players)
	if player.is_invulnerable:
		return false
	
	# Calculate direction to player for turret rotation
	var direction = player.global_position - global_position
	var angle = direction.angle()
	
	# Update sprite rotation to face player
	if has_node("Sprite2D"):
		get_node("Sprite2D").rotation = angle
	
	return true

# Shoot at the player
func shoot_at_player(player):
	# Create the laser instance
	var laser = laser_scene.instantiate()
	
	# Calculate direction to player
	var direction = player.global_position - global_position
	direction = direction.normalized()
	
	# Set position slightly in front of the enemy
	var spawn_offset = direction * 30
	laser.global_position = global_position + spawn_offset
	
	# Set laser direction and rotation
	laser.direction = direction
	laser.rotation = direction.angle()
	
	# Configure the laser
	laser.is_player_laser = false
	laser.damage = 10
	
	# Change laser color for enemy
	var sprite = laser.get_node("Sprite2D")
	if sprite:
		sprite.texture = load("res://sprites/weapons/laser_red.png")
	
	# Add laser to scene
	get_tree().current_scene.add_child(laser)
	
	# Reset cooldown
	current_cooldown = fire_cooldown
	
	print("Enemy fired laser at player")

# Take damage from player
func take_damage(amount):
	# Apply damage
	current_health -= amount
	print("Enemy took", amount, "damage. Health:", current_health)
	
	# Visual feedback for taking damage
	is_hit = true
	hit_flash_timer = hit_flash_duration
	if has_node("Sprite2D"):
		get_node("Sprite2D").modulate = Color.RED
	
	# Check for death
	if current_health <= 0:
		die()

# Death function
func die():
	print("Enemy destroyed")
	
	# Spawn explosion effect (if we had one)
	
	# Remove the enemy
	queue_free()

# Check if a laser has hit this enemy
func check_laser_hit(laser):
	# Only player lasers can hit enemies
	if not laser.is_player_laser:
		return false
	
	# Get collision shapes
	var enemy_rect = get_collision_rect()
	var laser_rect = laser.get_collision_rect()
	
	# Offset to global coordinates
	enemy_rect.position += global_position
	laser_rect.position += laser.global_position
	
	# Check for intersection
	return enemy_rect.intersects(laser_rect)

# Get enemy collision rectangle for hit detection
func get_collision_rect():
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		# Make the collision rect a bit smaller than the sprite for better gameplay
		var scaled_size = texture_size * 0.7
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	else:
		# Fallback collision rect if no sprite
		return Rect2(-16, -16, 32, 32)
