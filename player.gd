extends Node2D

@export var movement_speed = 300
@export var player_size = Vector2(32, 32)
@export var player_color = Color(1.0, 0.5, 0.0, 1.0)  # Orange

# Reference to the state machine
@onready var state_machine = $StateMachine

# Track previous position for cell change detection
var previous_cell_x = -1
var previous_cell_y = -1

# Boundary detection variables (initially disabled)
var is_immobilized = false  # Start as not immobilized
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
	
	# Ensure the player starts in the normal state
	if state_machine and state_machine.has_method("change_state"):
		state_machine.change_state("Normal")
		print("Player state initialized to Normal")

func _process(delta):
	# When not using the state machine, handle movement directly here
	if not state_machine:
		handle_movement(delta)
	
	# Check for grid cell changes regardless of state
	check_grid_position()
	
	# Handle boundary detection separately from movement
	check_boundaries(delta)

func handle_movement(delta):
	# This is a fallback if state machine doesn't work
	var direction = Vector2.ZERO
	
	if not is_immobilized:
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
			global_position += direction * movement_speed * delta

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

func check_boundaries(delta):
	# Only handle boundary checking if not currently immobilized
	if is_immobilized:
		respawn_timer -= delta
		if respawn_timer <= 0:
			var main = get_node_or_null("/root/Main")
			if main and main.has_method("respawn_player_at_initial_planet"):
				print("Respawning player at initial planet")
				main.respawn_player_at_initial_planet()
				is_immobilized = false
				was_in_boundary_cell = false
				was_outside_grid = false
				# Ensure the player is in Normal state after respawning
				if state_machine:
					state_machine.change_state("Normal")
		return

	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		var current_cell_x = int(floor(global_position.x / grid.cell_size.x))
		var current_cell_y = int(floor(global_position.y / grid.cell_size.y))
		
		# Skip boundary checks if position is invalid
		if not grid.is_valid_position(current_cell_x, current_cell_y):
			return
			
		# Check if player is in a boundary cell
		var is_boundary = grid.is_boundary_cell(current_cell_x, current_cell_y)
		
		# Store last valid position when player is in a non-boundary cell
		if not is_boundary:
			last_valid_position = global_position
			was_in_boundary_cell = false
		elif not was_in_boundary_cell:
			# Player just entered a boundary cell, show warning
			was_in_boundary_cell = true
			var main = get_node_or_null("/root/Main")
			if main and main.has_method("show_message"):
				main.show_message("WARNING: Approaching boundary of known space!")

func _draw():
	# Draw the player as an orange square
	var rect = Rect2(-player_size.x/2, -player_size.y/2, player_size.x, player_size.y)
	draw_rect(rect, player_color)
	
	# Add a border
	draw_rect(rect, Color.WHITE, false, 2.0)

# Method to completely immobilize the player
func set_immobilized(value):
	is_immobilized = value
	
	if state_machine:
		if value:
			state_machine.change_state("Immobilized")
		else:
			state_machine.change_state("Normal")
	
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
