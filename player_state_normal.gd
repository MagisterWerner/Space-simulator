class_name PlayerStateNormal
extends State

func enter() -> void:
	super.enter()
	print("Player entered Normal state")
	
	# Ensure player is not immobilized
	entity.is_immobilized = false
	entity.movement_speed = 300

func process(delta: float) -> void:
	# Skip if player is immobilized (this is a safety check)
	if entity.is_immobilized:
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
		# Store previous position
		var prev_position = entity.global_position
		
		# Move the player
		direction = direction.normalized()
		entity.global_position += direction * entity.movement_speed * delta
		
		# Update sprite rotation to face movement direction
		if entity.has_node("Sprite2D"):
			var angle = direction.angle()
			entity.get_node("Sprite2D").rotation = angle
		
		# Check boundaries
		if not entity.check_boundaries():
			# The check_boundaries function will handle returning to last valid position
			return
		
		# Check if cell position changed
		entity.update_cell_position()
	
	# Handle shooting with Space key (ui_select)
	if Input.is_action_pressed("ui_select") and entity.current_cooldown <= 0:
		entity.shoot()
