extends ParallaxBackground

@export var star_count_far: int = 400
@export var star_count_mid: int = 200 
@export var star_count_near: int = 80
@export var parallax_scale: float = 1.0

var camera: Camera2D
var viewport_size: Vector2
var initialized: bool = false

func _ready():
	# Wait one frame for the viewport to have the correct size
	await get_tree().process_frame
	setup_background()
	
func setup_background():
	# Ensure we only initialize once
	if initialized:
		return
		
	# Get viewport size
	viewport_size = get_viewport().get_visible_rect().size
	
	# Find camera
	find_camera()
	
	# Create the star layers
	create_star_layer("FarStars", 0.05 * parallax_scale, star_count_far, Color(0.8, 0.8, 1.0, 0.4), Vector2(1, 1))
	create_star_layer("MidStars", 0.1 * parallax_scale, star_count_mid, Color(0.9, 0.9, 1.0, 0.6), Vector2(1.5, 1.5))
	create_star_layer("NearStars", 0.2 * parallax_scale, star_count_near, Color(1.0, 1.0, 1.0, 0.8), Vector2(2, 2))
	
	initialized = true
	
	# Set scroll ignore to respond to camera movement
	scroll_ignore_camera_zoom = true

func find_camera():
	# Try to find camera from player if possible
	var player = get_node_or_null("/root/Main/Player")
	if player and player.has_node("Camera2D"):
		camera = player.get_node("Camera2D")
	else:
		# Look for any camera in the scene
		var cameras = get_tree().get_nodes_in_group("camera") 
		if cameras.size() > 0:
			camera = cameras[0]
		else:
			camera = find_camera_in_tree(get_tree().root)
			
	if camera:
		print("Space background: Camera found")
	else:
		print("Space background: No camera found, using default viewport")

func find_camera_in_tree(node: Node) -> Camera2D:
	if node is Camera2D and node.current:
		return node
	
	for child in node.get_children():
		var found = find_camera_in_tree(child)
		if found:
			return found
	
	return null

func create_star_layer(_name: String, scroll_factor: float, count: int, star_color: Color, max_size: Vector2):
	# Create parallax layer
	var layer = ParallaxLayer.new()
	layer.name = name
	layer.motion_scale = Vector2(scroll_factor, scroll_factor)
	layer.motion_offset = Vector2.ZERO
	layer.motion_mirroring = viewport_size * 3  # 3x viewport size to ensure coverage
	add_child(layer)
	
	# Create canvas item for drawing stars
	var star_field = StarField.new()
	star_field.name = "StarField"
	star_field.star_count = count
	star_field.viewport_size = viewport_size * 3
	star_field.star_color = star_color
	star_field.max_size = max_size
	layer.add_child(star_field)

func _process(_delta):
	if camera:
		# Update background to follow the camera
		set_scroll_offset(camera.get_screen_center_position())

class StarField extends Node2D:
	var star_count: int = 200
	var star_positions: PackedVector2Array = []
	var star_sizes: PackedFloat32Array = []
	var star_twinkle_offset: PackedFloat32Array = []
	var star_color: Color = Color(1, 1, 1, 0.7)
	var max_size: Vector2 = Vector2(2, 2)
	var viewport_size: Vector2 = Vector2(3000, 3000)
	var rng = RandomNumberGenerator.new()
	
	func _ready():
		# Generate stars with a consistent RNG seed
		rng.seed = star_count * int(star_color.r * 255) * int(star_color.b * 255)
		
		# Generate star positions
		for i in range(star_count):
			var pos = Vector2(
				rng.randf_range(0, viewport_size.x),
				rng.randf_range(0, viewport_size.y)
			)
			star_positions.append(pos)
			
			# Random size
			star_sizes.append(rng.randf_range(0.5, max_size.x))
			
			# Random twinkle offset
			star_twinkle_offset.append(rng.randf() * TAU)  # 0 to 2π
	
	func _draw():
		# Draw all stars
		for i in range(star_positions.size()):
			var pos = star_positions[i]
			var size = star_sizes[i]
			
			# Draw star as simple rect
			draw_rect(Rect2(pos.x - size/2, pos.y - size/2, size, size), star_color)
