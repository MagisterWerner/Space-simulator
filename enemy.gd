extends Node2D

@export var movement_speed = 150
@export var enemy_size = Vector2(32, 32)
@export var enemy_color = Color(1.0, 0.0, 0.0, 1.0)  # Red
@export var enemy_border_color = Color(1.0, 1.0, 0.0, 1.0)  # Yellow

# Reference to the state machine
@onready var state_machine = $StateMachine

# Original spawn position
var original_position = Vector2.ZERO

# Grid cell coordinates
var cell_x = -1
var cell_y = -1

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
	
	print("Enemy ready at position: ", global_position, " in cell: (", cell_x, ",", cell_y, ")")

func _draw():
	# Draw the enemy as a red square with yellow border
	var rect = Rect2(-enemy_size.x/2, -enemy_size.y/2, enemy_size.x, enemy_size.y)
	draw_rect(rect, enemy_color)
	
	# Add a yellow border
	draw_rect(rect, enemy_border_color, false, 2.0)

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

# Add this function to check if enemy is in a loaded chunk
func is_in_loaded_chunk():
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		var enemy_cell_x = int(floor(global_position.x / grid.cell_size.x))
		var enemy_cell_y = int(floor(global_position.y / grid.cell_size.y))
		return grid.loaded_cells.has(Vector2(enemy_cell_x, enemy_cell_y))
	return false
