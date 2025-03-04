extends Label

func show_value(value, travel, duration, spread, crit=false):
	var tween = create_tween().set_parallel(true)
	text = value
	
	# For scaling, set the pivot offset to the center.
	pivot_offset = size / 2
	var movement = travel.rotated(randf_range(-spread/2, spread/2))
	
	# Animate the position.
	tween.tween_property(self, "position", position + movement, duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	
	# Animate the fade-out.
	tween.tween_property(self, "modulate:a", 0.0, duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
	
	if crit:
		# Set the color and animate size for criticals.
		modulate = Color(1, 0, 0)
		tween.tween_property(self, "scale", Vector2(2,2), 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		
	tween.play()
	await tween.finished
	queue_free()
