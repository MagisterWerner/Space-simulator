class_name PlayerStateNormal
extends PlayerStateBase

func process(delta):
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
		direction = direction.normalized()
		player.global_position += direction * player.movement_speed * delta
	
	# Keep the player visible at all times by forcing a redraw
	player.queue_redraw()
