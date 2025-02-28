extends Node2D

# Reference to the charge beam
var charge_beam = null

func _process(delta):
	# Force redraw every frame
	queue_redraw()

func _draw():
	if not charge_beam or charge_beam.current_charge <= 0:
		return
	
	# Draw charge circle with pulsing effect
	var charge_percent = charge_beam.current_charge / charge_beam.charge_time
	var pulse = abs(sin(Time.get_ticks_msec() / 150.0)) * 0.3 + 0.7
	var radius = 20.0 * charge_percent * pulse
	
	# Calculate color based on charge level
	var color = charge_beam.beam_color
	color.a = charge_percent * pulse
	
	# Draw outer circle
	draw_circle(Vector2.ZERO, radius, color.darkened(0.3))
	
	# Draw inner circle
	draw_circle(Vector2.ZERO, radius * 0.7, color)
	
	# Draw charge level text
	var font = ThemeDB.fallback_font
	var percentage = int(charge_percent * 100)
	var text = str(percentage) + "%"
	var text_size = font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12)
	draw_string(font, Vector2(-text_size.x/2, 4), text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, Color.WHITE)
