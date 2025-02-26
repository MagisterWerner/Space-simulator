extends Node2D

@export var movement_speed = 300
@export var player_size = Vector2(32, 32)
@export var player_color = Color(1.0, 0.5, 0.0, 1.0)  # Orange

# Track previous position for cell change detection
var previous_cell_x = -1
var previous_cell_y = -1

# Boundary detection variables
var is_immobilized = false
var respawn_timer = 0.0
var was_in_boundary_cell = false
var was_outside_grid = false
var last_valid_position = Vector2.ZERO

func _ready():
	# Set a high z-index to ensure the player is drawn on top of all other objects
	z_index = 10
	
	# Add a camera if one doesn't exist
	if not has_node("Camera2D"):
		var camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.current = true
		add_child(camera)
		print("Player ready at position: ", global_position)
	
	# Initialize previous cell position
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		previous_cell_x = int(floor(global_position.x / grid.cell_size.x))
		previous_cell_y = int(floor(global_position.y / grid.cell_size.y))
		
		# Initialize last valid position
		last_valid_position = global_position
		
		print("Player initialized at cell: (", previous_cell_x, ", ", previous_cell_y, ")")

func _process(delta):
	# Handle player movement
	handle_movement(delta)
	
	# Check for grid cell changes
	check_grid_position()
	
	# Keep the player visible by forcing a redraw
	queue_redraw()

func handle_movement(delta):
	# Prevent movement if immobilized
	if is_immobilized:
		respawn_timer -= delta
		if respawn_timer <= 0:
			var main = get_node_or_null("/root/Main")
			if main and main.has_method("respawn_player_at_initial_planet"):
				is_immobilized = false
				movement_speed = 300
				main.respawn_player_at_initial_planet()
		return
	
	# Immediate direction calculation
	var direction = Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	
	# Normalize and move in a single frame
	if direction.length() > 0:
		direction = direction.normalized()
		var movement = direction * movement_speed * delta
		
		# Store current position before moving
		var old_position = global_position
		
		# Immediate position update
		global_position += movement
		
		# Strict boundary check after movement
		if not check_boundaries():
			# Revert to previous position if outside grid
			global_position = old_position

func check_grid_position():
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		var current_cell_x = int(floor(global_position.x / grid.cell_size.x))
		var current_cell_y = int(floor(global_position.y / grid.cell_size.y))
		
		# Check if player moved to a new cell
		if current_cell_x != previous_cell_x or current_cell_y != previous_cell_y:
			print("Player moved to new cell: (", current_cell_x, ",", current_cell_y, ")")
			grid.update_loaded_chunks(current_cell_x, current_cell_y)
			
			# Update previous cell position
			previous_cell_x = current_cell_x
			previous_cell_y = current_cell_y

# Returns true if the player is in a valid position, false otherwise
func check_boundaries():
	var grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		return true
	
	# Prevent multiple immobilization attempts
	if is_immobilized:
		return false
	
	# Precise cell coordinate calculation
	var cell_x = int(floor(global_position.x / grid.cell_size.x))
	var cell_y = int(floor(global_position.y / grid.cell_size.y))
	
	# Precise grid size as integers
	var grid_width = int(grid.grid_size.x)
	var grid_height = int(grid.grid_size.y)
	
	# Detailed boundary checks
	var is_left_exit = cell_x < 0
	var is_right_exit = cell_x >= grid_width
	var is_top_exit = cell_y < 0
	var is_bottom_exit = cell_y >= grid_height
	
	# Combine all exit conditions
	var is_outside_grid = is_left_exit or is_right_exit or is_top_exit or is_bottom_exit
	
	# If outside grid, always immobilize
	if is_outside_grid:
		# Detailed exit direction logging
		var exit_direction = ""
		if is_left_exit:
			exit_direction = "LEFT"
		elif is_right_exit:
			exit_direction = "RIGHT"
		elif is_top_exit:
			exit_direction = "TOP"
		elif is_bottom_exit:
			exit_direction = "BOTTOM"
		
		print("CRITICAL: Player Attempting Grid Exit")
		print("  Exit Direction: ", exit_direction)
		print("  Current Position: ", global_position)
		print("  Cell Coordinates: (", cell_x, ", ", cell_y, ")")
		
		# Show immobilization message
		var main = get_tree().current_scene
		if main and main.has_method("show_message"):
			main.show_message("You abandoned all logic and were lost in space!")
		
		# Ensure immobilization works for ALL exits
		set_immobilized(true)
		respawn_timer = 5.0  # Full 5-second wait
		
		# Always revert to last valid position
		global_position = last_valid_position
		
		return false
	
	# Position tracking only when not immobilized
	last_valid_position = global_position
	
	return true

# Method to completely immobilize the player
func set_immobilized(value):
	# Ensure atomic state change
	if value and not is_immobilized:
		is_immobilized = true
		movement_speed = 0
		respawn_timer = 5.0
		print("Player immobilized with full 5-second timer")
	elif not value:
		is_immobilized = false
		movement_speed = 300
		respawn_timer = 0.0
		print("Player movement restored")

func _draw():
	# Draw the player as an orange square
	var rect = Rect2(-player_size.x/2, -player_size.y/2, player_size.x, player_size.y)
	draw_rect(rect, player_color)
	
	# Add a white border
	draw_rect(rect, Color.WHITE, false, 2.0)

# Method to update cell position (called from main.gd)
func update_cell_position(cell_x, cell_y):
	previous_cell_x = cell_x
	previous_cell_y = cell_y
	print("Player cell position initialized to: (", cell_x, ",", cell_y, ")")
	
	# Force grid update when cell position is set
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		grid.update_loaded_chunks(cell_x, cell_y)
