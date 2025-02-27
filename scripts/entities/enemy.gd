# scripts/entities/enemy.gd
extends Node2D

# Components 
@onready var entity_component = $EntityComponent
@onready var state_machine = $StateMachine

# Enemy-specific properties
@export var fire_range: float = 250.0
var original_position: Vector2 = Vector2.ZERO
var cell_x: int = -1
var cell_y: int = -1

# --- For direct access by states ---
var movement_speed: float = 150.0:
	get: return entity_component.movement_speed if entity_component else 150.0
	set(value): 
		if entity_component:
			entity_component.movement_speed = value

# Cached nodes
var grid: Node2D
var main: Node2D

# Signals - prefixed with underscore to indicate they're used externally
signal _active_state_changed(is_active)

func _ready():
	# Enemy-specific setup
	z_index = 5
	add_to_group("enemies")
	
	# Get references to commonly used nodes
	grid = get_node_or_null("/root/Main/Grid")
	main = get_node_or_null("/root/Main")
	
	# Store the original position
	original_position = global_position
	
	# Calculate initial cell position
	update_cell_position()
	
	# Initialize state machine
	if state_machine:
		# Set initial state based on player presence
		call_deferred("check_for_player")
	
	print("Enemy ready at position: ", global_position, " in cell: (", cell_x, ",", cell_y, ")")

func _process(_delta):
	# Check if should fire
	var player = get_node_or_null("/root/Main/Player")
	if player and entity_component and entity_component.current_cooldown <= 0 and can_see_player(player):
		shoot_at_player(player)
	
	# Update the health bar
	update_health_bar()

func is_player_in_same_cell() -> bool:
	var player = get_node_or_null("/root/Main/Player")
	
	if player and grid:
		var player_cell_x = int(floor(player.global_position.x / grid.cell_size.x))
		var player_cell_y = int(floor(player.global_position.y / grid.cell_size.y))
		
		return player_cell_x == cell_x and player_cell_y == cell_y
	
	return false

func check_for_player() -> void:
	if state_machine:
		if is_player_in_same_cell():
			state_machine.change_state("Follow")
		else:
			state_machine.change_state("Idle")

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
	emit_signal("_active_state_changed", is_active)

func update_cell_position() -> bool:
	if grid:
		var new_cell_x = int(floor(global_position.x / grid.cell_size.x))
		var new_cell_y = int(floor(global_position.y / grid.cell_size.y))
		
		if new_cell_x != cell_x or new_cell_y != cell_y:
			cell_x = new_cell_x
			cell_y = new_cell_y
			return true
	
	return false

func can_see_player(player) -> bool:
	# Check distance first (optimization)
	var distance = global_position.distance_to(player.global_position)
	if distance > fire_range:
		return false
	
	# Only shoot if in the same cell
	if not is_player_in_same_cell():
		return false
	
	# Check if player is invulnerable
	if player.is_immobilized:
		return false
	
	# Calculate direction to player for turret rotation
	var direction = player.global_position - global_position
	var angle = direction.angle()
	
	# Update sprite rotation to face player
	if has_node("Sprite2D"):
		get_node("Sprite2D").rotation = angle
	
	return true

func shoot_at_player(player) -> void:
	# Calculate direction to player
	var direction = (player.global_position - global_position).normalized()
	
	# Use the component to shoot
	if entity_component:
		entity_component.shoot(global_position, direction, false, 10.0)

func take_damage(amount: float) -> void:
	if entity_component:
		entity_component.take_damage(amount)

func on_death() -> void:
	print("Enemy destroyed at position: ", global_position)
	
	# Remove the enemy
	queue_free()

func check_laser_hit(laser) -> bool:
	if entity_component:
		return entity_component.check_laser_hit(laser, get_collision_rect(), false)
	return false

func get_collision_rect() -> Rect2:
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		# Make the collision rect a bit smaller than the sprite for better gameplay
		var scaled_size = texture_size * 0.7
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	else:
		# Fallback collision rect if no sprite
		return Rect2(-16, -16, 32, 32)

func update_health_bar() -> void:
	var health_bar = get_node_or_null("HealthBar")
	if health_bar and entity_component:
		# Update width based on current health percentage
		var health_percent = float(entity_component.current_health) / entity_component.max_health
		health_bar.size.x = 30 * health_percent
		
		# Center the health bar
		health_bar.position.x = -15
