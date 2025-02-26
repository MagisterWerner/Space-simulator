class_name PlayerStateNormal
extends PlayerStateBase

func enter():
	super.enter()
	print("Player entered Normal state")
	
	# Ensure player is not immobilized
	if player.has_method("set_immobilized"):
		player.is_immobilized = false

func process(delta):
	# Skip if player is immobilized (belt-and-suspenders approach)
	if player.has_method("set_immobilized") and player.is_immobilized:
		return
	
	# Handle movement
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
		# Store previous position for cell change check
		var prev_position = player.global_position
		
		# Move the player
		direction = direction.normalized()
		player.global_position += direction * player.movement_speed * delta
		
		# Check if player changed cells and update grid chunks if needed
		var grid = get_node_or_null("/root/Main/Grid")
		if grid:
			var prev_cell_x = int(floor(prev_position.x / grid.cell_size.x))
			var prev_cell_y = int(floor(prev_position.y / grid.cell_size.y))
			
			var current_cell_x = int(floor(player.global_position.x / grid.cell_size.x))
			var current_cell_y = int(floor(player.global_position.y / grid.cell_size.y))
			
			# Update chunks if cell position changed
			if prev_cell_x != current_cell_x or prev_cell_y != current_cell_y:
				print("State Normal: Player moved to new cell: (", current_cell_x, ",", current_cell_y, ")")
				grid.update_loaded_chunks(current_cell_x, current_cell_y)
	
	# Keep the player visible at all times by forcing a redraw
	player.queue_redraw()
