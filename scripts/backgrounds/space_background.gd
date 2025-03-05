# scripts/backgrounds/space_background.gd
# Procedural parallax space background with multiple star layers
# Integrates with the game's camera and seed systems
extends ParallaxBackground
class_name SpaceBackground

## Configuration for star layers
@export_group("Star Layer Configuration")
@export var star_count_far: int = 1500
@export var star_count_mid: int = 500
@export var star_count_near: int = 250
@export var parallax_scale: float = 1.0
@export var use_game_seed: bool = true  # Use global seed system if available

## Star animation options
@export_group("Star Animation")
@export var enable_twinkle: bool = true
@export var twinkle_speed: float = 0.5
@export var twinkle_amount: float = 0.3

## Debug options
@export_group("Debug")
@export var debug_mode: bool = false

# Internal state
var camera: Camera2D
var viewport_size: Vector2
var initialized: bool = false
var star_layers: Array[ParallaxLayer] = []
var _twinkle_time: float = 0.0

# Signal emitted when the background is fully initialized
signal background_initialized

func _ready() -> void:
	# Wait one frame to ensure all other nodes are initialized
	await get_tree().process_frame
	
	# Setup the background
	call_deferred("setup_background")

func setup_background() -> void:
	if initialized:
		return
		
	viewport_size = get_viewport().get_visible_rect().size
	
	# Find the camera in the scene
	find_camera()
	
	# If requested, use the global seed
	var background_seed: int = 0
	if use_game_seed and has_node("/root/Seed") and Seed.has_method("get_seed"):
		background_seed = Seed.get_seed()
		if debug_mode:
			print("SpaceBackground: Using global seed: ", background_seed)
	else:
		# Create a seed based on the current time
		background_seed = int(Time.get_unix_time_from_system())
		if debug_mode:
			print("SpaceBackground: Using time-based seed: ", background_seed)
	
	# Create star layers with different parallax factors
	create_star_layer("FarStars", 0.05 * parallax_scale, star_count_far, 
		Color(0.8, 0.8, 1.0, 0.4), Vector2(1, 1), background_seed + 1)
	
	create_star_layer("MidStars", 0.1 * parallax_scale, star_count_mid, 
		Color(0.9, 0.9, 1.0, 0.6), Vector2(1.5, 1.5), background_seed + 2)
	
	create_star_layer("NearStars", 0.2 * parallax_scale, star_count_near, 
		Color(1.0, 1.0, 1.0, 0.8), Vector2(2, 2), background_seed + 3)
	
	# Ignore camera zoom to maintain proper parallax effect
	scroll_ignore_camera_zoom = true
	initialized = true
	
	if debug_mode:
		print("SpaceBackground: Setup complete with ", star_layers.size(), " layers")
	
	# Emit signal for other systems to respond
	background_initialized.emit()

func find_camera() -> void:
	# First try finding the player ship through the EntityManager
	if has_node("/root/Entities") and Entities.has_method("get_nearest_entity"):
		var player = Entities.get_nearest_entity(Vector2.ZERO, "player")
		if player and player.get_viewport().get_camera_2d():
			camera = player.get_viewport().get_camera_2d()
			if debug_mode:
				print("SpaceBackground: Found camera through EntityManager")
			return
	
	# Try finding through the current game's camera in Main
	var main_camera = get_node_or_null("/root/Main/Camera2D")
	if main_camera and main_camera is Camera2D:
		camera = main_camera
		if debug_mode:
			print("SpaceBackground: Found camera in Main scene")
		return
	
	# Try finding the camera attached to the player ship
	var player_ship = get_node_or_null("/root/Main/PlayerShip")
	if player_ship and player_ship.get_viewport().get_camera_2d():
		camera = player_ship.get_viewport().get_camera_2d()
		if debug_mode:
			print("SpaceBackground: Found camera attached to PlayerShip")
		return
	
	# Try finding any camera in the "camera" group
	var cameras = get_tree().get_nodes_in_group("camera")
	if not cameras.is_empty():
		camera = cameras[0]
		if debug_mode:
			print("SpaceBackground: Found camera in 'camera' group")
		return
	
	# Last resort: recursive search through the scene tree
	camera = find_camera_in_tree(get_tree().root)
	if camera and debug_mode:
		print("SpaceBackground: Found camera through recursive search")
	else:
		push_warning("SpaceBackground: No camera found, background will not follow player")

# Recursively search for a camera in the scene tree
func find_camera_in_tree(node: Node) -> Camera2D:
	if node is Camera2D and node.current:
		return node
	
	for child in node.get_children():
		var found = find_camera_in_tree(child)
		if found:
			return found
	
	return null

# Create a single star layer with the given parameters
func create_star_layer(layer_name: String, scroll_factor: float, count: int, 
					  star_color: Color, max_size: Vector2, seed_value: int) -> void:
	var parallax_layer = ParallaxLayer.new()
	parallax_layer.name = layer_name
	parallax_layer.motion_scale = Vector2(scroll_factor, scroll_factor)
	parallax_layer.motion_mirroring = viewport_size * 3  # Make the layer repeat seamlessly
	add_child(parallax_layer)
	star_layers.append(parallax_layer)
	
	var star_field = StarField.new()
	star_field.name = "StarField"
	star_field.star_count = count
	star_field.viewport_size = viewport_size * 3
	star_field.star_color = star_color
	star_field.max_size = max_size
	star_field.seed_value = seed_value
	star_field.enable_twinkle = enable_twinkle
	star_field.parent_background = self
	parallax_layer.add_child(star_field)

# Update the background position based on the camera position
func _process(delta: float) -> void:
	if not initialized:
		return
		
	if camera and is_instance_valid(camera):
		set_scroll_offset(camera.get_screen_center_position())
	
	if enable_twinkle:
		_twinkle_time += delta * twinkle_speed
		# Update all star fields
		for parallax_layer in star_layers:
			var star_field = parallax_layer.get_node_or_null("StarField")
			if star_field and star_field is StarField:
				star_field.twinkle_time = _twinkle_time
				star_field.twinkle_amount = twinkle_amount
				star_field.queue_redraw()

# StarField class that renders the stars for a layer
class StarField extends Node2D:
	var star_count: int = 200
	var star_positions: PackedVector2Array = []
	var star_sizes: PackedFloat32Array = []
	var star_twinkle_offset: PackedFloat32Array = []
	var star_color: Color = Color(1, 1, 1, 0.7)
	var max_size: Vector2 = Vector2(2, 2)
	var viewport_size: Vector2 = Vector2(3000, 3000)
	var seed_value: int = 0
	var enable_twinkle: bool = true
	var twinkle_time: float = 0.0
	var twinkle_amount: float = 0.3
	var parent_background: Node = null
	
	var rng: RandomNumberGenerator
	
	func _ready() -> void:
		rng = RandomNumberGenerator.new()
		rng.seed = seed_value if seed_value != 0 else hash(str(star_count) + str(Time.get_unix_time_from_system()))
		
		generate_stars()
	
	# Generate the star data
	func generate_stars() -> void:
		star_positions.resize(star_count)
		star_sizes.resize(star_count)
		star_twinkle_offset.resize(star_count)
		
		for i in range(star_count):
			star_positions[i] = Vector2(
				rng.randf_range(0, viewport_size.x),
				rng.randf_range(0, viewport_size.y)
			)
			star_sizes[i] = rng.randf_range(0.5, max_size.x)
			star_twinkle_offset[i] = rng.randf() * TAU
	
	# Draw the stars
	func _draw() -> void:
		for i in range(star_positions.size()):
			var pos = star_positions[i]
			var base_size = star_sizes[i]
			var size = base_size
			
			# Apply twinkle effect if enabled
			if enable_twinkle:
				var twinkle_factor = sin(twinkle_time + star_twinkle_offset[i]) * 0.5 + 0.5
				size = base_size * (1.0 - twinkle_amount + twinkle_amount * twinkle_factor)
				
				# Adjust alpha for twinkle effect
				var alpha_factor = 0.7 + 0.3 * twinkle_factor
				var color = star_color
				color.a = color.a * alpha_factor
				
				draw_rect(Rect2(pos.x - size/2, pos.y - size/2, size, size), color)
			else:
				draw_rect(Rect2(pos.x - size/2, pos.y - size/2, size, size), star_color)

# Reset the background (can be called when changing scenes or restarting game)
func reset() -> void:
	initialized = false
	camera = null
	
	# Clear existing layers
	for parallax_layer in star_layers:
		parallax_layer.queue_free()
	star_layers.clear()
	
	# Setup again
	call_deferred("setup_background")

# Public method to update viewport size (call if window is resized)
func update_viewport_size() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	
	# Update mirroring size for all layers
	for parallax_layer in star_layers:
		parallax_layer.motion_mirroring = viewport_size * 3
		
		var star_field = parallax_layer.get_node_or_null("StarField")
		if star_field and star_field is StarField:
			star_field.viewport_size = viewport_size * 3
			star_field.generate_stars()
			star_field.queue_redraw()
