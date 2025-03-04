# star_field.gd
extends Node2D

@export var star_count := 1000
@export var field_size := Vector2(5000, 5000)
@export var star_colors := [
	Color(1, 1, 1),            # White
	Color(0.8, 0.8, 1.0),      # Light blue
	Color(1.0, 0.9, 0.7),      # Yellow-white
	Color(1.0, 0.8, 0.8),      # Pinkish
	Color(0.7, 0.8, 1.0)       # Light blue
]

func _ready() -> void:
	_generate_stars()

func _generate_stars() -> void:
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	for i in range(star_count):
		var star = ColorRect.new()
		
		# Random position within field size
		var pos_x = rng.randf_range(-field_size.x/2, field_size.x/2)
		var pos_y = rng.randf_range(-field_size.y/2, field_size.y/2)
		
		# Random size between 1-3 pixels
		var size = rng.randi_range(1, 3)
		
		# Random color from our palette
		var color_idx = rng.randi_range(0, star_colors.size() - 1)
		
		# Configure the star
		star.position = Vector2(pos_x, pos_y)
		star.size = Vector2(size, size)
		star.color = star_colors[color_idx]
		
		# Add to scene
		add_child(star)
