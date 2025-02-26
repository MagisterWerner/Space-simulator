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
		print("Added camera to player")
	
	print("Player ready at position: ", global_position)
	
	# Initialize previous cell position
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		previous_cell_x = int(floor(global_position.x / grid.cell_size.x))
		previous_cell_y = int(floor(global_position.y / grid.cell_size.y))
		
		# Initialize last valid position
		last_valid_position = global_position

func _process(delta):
	# Handle player movement
	handle_movement(delta)
	
	# Check for grid cell changes
	check_grid_position()
	
	# Keep the player visible by forcing a redraw
	queue_redraw()

func handle_movement(delta):
	# Skip movement if player is immobilized
	if is_immobilized:
		respawn_timer -= delta
		if respawn_timer <= 0:
			# Reset immobilized state
			is_immobilized = false
			
			# Respawn at initial planet
			var main = get_node_or_null("/root/Main")
			if main and main.has_method("respawn_player_at_initial_planet"):
				main.respawn_player_at_initial_planet()
		return
	
	var direction = Vector2.ZERO
	
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	
	if direction.length() > 0:
		direction = direction.normalized()
		
		# Store last position before moving
		var prev_position = global_position
		
		# Move the player
		global_position += direction * movement_speed * delta
		
		# Check for grid boundaries
		check_boundaries()

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

func check_boundaries():
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		var cell_x = int(floor(global_position.x / grid.cell_size.x))
		var cell_y = int(floor(global_position.y / grid.cell_size.y))
		
		# Check if player is outside the grid
		var outside_grid = not grid.is_valid_position(cell_x, cell_y)
		
		# Store the last valid position when player is inside the grid
		if not outside_grid and not is_immobilized:
			last_valid_position = global_position
		
		# Handle player leaving the grid entirely
		if outside_grid:
			# Hard stop: don't allow player to move beyond the boundary
			global_position = last_valid_position
			
			if not was_outside_grid:
				var main = get_tree().current_scene
				if main.has_method("show_message"):
					main.show_message("You abandoned all logic and were lost in space!")
				
				print("CRITICAL: Player left the grid entirely!")
				is_immobilized = true
				respawn_timer = 5.0  # 5 seconds until respawn
				
				# Disable movement
				movement_speed = 0
		
		# Update outside grid tracking
		was_outside_grid = outside_grid
		
		# Skip boundary checks if we're outside the grid
		if outside_grid:
			return
		
		# Check if player is in a boundary cell
		var is_in_boundary = grid.is_boundary_cell(cell_x, cell_y)
		
		# Show warning message only when first entering a boundary cell
		if is_in_boundary and not was_in_boundary_cell:
			var main = get_tree().current_scene
			if main.has_method("show_message"):
				main.show_message("WARNING: You are leaving known space!")
			
			was_in_boundary_cell = true
		elif not is_in_boundary:
			was_in_boundary_cell = false

func _draw():
	# Draw the player as an orange square
	var rect = Rect2(-player_size.x/2, -player_size.y/2, player_size.x, player_size.y)
	draw_rect(rect, player_color)
	
	# Add a white border
	draw_rect(rect, Color.WHITE, false, 2.0)

# Method to completely immobilize the player
func set_immobilized(value):
	is_immobilized = value
	
	if value:
		movement_speed = 0
	else:
		movement_speed = 300
	
	print("Player immobilized state set to: ", value)

# Method to update cell position (called from main.gd)
func update_cell_position(cell_x, cell_y):
	previous_cell_x = cell_x
	previous_cell_y = cell_y
	print("Player cell position initialized to: (", cell_x, ",", cell_y, ")")
	
	# Force grid update when cell position is set
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		grid.update_loaded_chunks(cell_x, cell_y)
