class_name Enemy
extends Entity

signal active_state_changed(is_active)

# Enemy-specific properties
@export var fire_range: float = 250.0  # Maximum firing range
var original_position: Vector2 = Vector2.ZERO

func _ready():
	# Call parent ready function
	super._ready()
	
	# Enemy-specific setup
	z_index = 5
	add_to_group("enemies")
	
	# Store the original position
	original_position = global_position
	
	# Ensure sprite exists
	if not has_node("Sprite2D"):
		var sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		sprite.texture = load("res://sprites/ships_enemy/enemy_ship_1.png")
		add_child(sprite)
	
	# Ensure health bar exists
	if not has_node("HealthBar"):
		var health_bar = ColorRect.new()
		health_bar.name = "HealthBar"
		health_bar.color = Color(1, 0, 0, 1)
		health_bar.size = Vector2(30, 3)
		health_bar.position = Vector2(-15, -25)
		add_child(health_bar)
	
	# Initialize state machine
	if state_machine:
		# Set initial state based on player presence
		call_deferred("check_for_player")
	
	print("Enemy ready at position: ", global_position, " in cell: (", cell_x, ",", cell_y, ")")

func _process(delta):
	# Call parent process function
	super._process(delta)
	
	# Check if should fire
	var player = get_node_or_null("/root/Main/Player")
	if player and current_cooldown <= 0 and can_see_player(player):
		shoot_at_player(player)
	
	# Update the health bar
	update_health_bar()

# Check if player is in the same cell
func is_player_in_same_cell() -> bool:
	var player = get_node_or_null("/root/Main/Player")
	
	if player and grid:
		var player_cell_x = int(floor(player.global_position.x / grid.cell_size.x))
		var player_cell_y = int(floor(player.global_position.y / grid.cell_size.y))
		
		return player_cell_x == cell_x and player_cell_y == cell_y
	
	return false

# Set the state based on player presence
func check_for_player() -> void:
	if state_machine:
		if is_player_in_same_cell():
			state_machine.change_state("Follow")
		else:
			state_machine.change_state("Idle")

# Update enemy and state machine visibility and processing state
func update_active_state(is_active: bool) -> void:
	# Skip if no change
	if visible == is_active:
		return
		
	# Update visibility
	visible = is_active
	
	# Update process states
	process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
	
	# Update state machine
	if state_machine:
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
	
	# Emit signal about active state change
	emit_signal("active_state_changed", is_active)

# Check if enemy is in a loaded chunk
func is_in_loaded_chunk() -> bool:
	if grid:
		return grid.loaded_cells.has(Vector2i(cell_x, cell_y))
	return false

# Check if player is in firing range and visible
func can_see_player(player) -> bool:
	# Check distance first (optimization)
	var distance = global_position.distance_to(player.global_position)
	if distance > fire_range:
		return false
	
	# Only shoot if in the same cell
	if not is_player_in_same_cell():
		return false
	
	# Check if player is invulnerable
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
func shoot_at_player(player) -> void:
	# Calculate direction to player
	var direction = (player.global_position - global_position).normalized()
	
	# Call the base class shoot method with enemy-specific parameters
	super.shoot(false, direction, 10, Color.RED)

# Override the take_damage method
func take_damage(amount: float) -> void:
	super.take_damage(amount)
	
	# Enemy-specific behavior after taking damage can be added here

# Override the die method
func die() -> void:
	print("Enemy destroyed at position: ", global_position)
	
	# Later can add effects, score, etc.
	
	# Remove the enemy
	queue_free()

# Update the health bar position and size based on current health
func update_health_bar() -> void:
	var health_bar = get_node_or_null("HealthBar")
	if health_bar:
		# Update width based on current health percentage
		var health_percent = float(current_health) / max_health
		health_bar.size.x = 30 * health_percent
		
		# Center the health bar
		health_bar.position.x = -15

# Draw the enemy if sprite is missing
func _draw() -> void:
	# Only draw if the sprite is missing
	if not has_node("Sprite2D"):
		# Draw the enemy as a red square with yellow border (fallback)
		var rect = Rect2(-16, -16, 32, 32)
		draw_rect(rect, Color(1.0, 0.0, 0.0, 1.0))
		draw_rect(rect, Color(1.0, 1.0, 0.0, 1.0), false, 2.0)
