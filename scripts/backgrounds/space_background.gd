# scripts/backgrounds/improved_space_background.gd
# Procedural parallax space background with multiple star layers
# Enhanced with clustered star distribution for the farthest layer
extends ParallaxBackground
class_name ImprovedSpaceBackground

## Configuration for star layers
@export_group("Star Layer Configuration")
@export var star_count_far: int = 5000  # Increased for more visible stars
@export var star_count_mid: int = 750
@export var star_count_near: int = 350
@export var parallax_scale: float = 1.0
@export var use_game_seed: bool = true  # Use global seed system if available

## Clustering parameters for far stars
@export_group("Far Stars Clustering")
@export var enable_clustering: bool = true
@export var cluster_count: int = 15  # Increased number of clusters for more galactic feel
@export var cluster_size_min: float = 0.15  # Minimum cluster size (0-1 relative to screen)
@export var cluster_size_max: float = 0.4  # Maximum cluster size (0-1 relative to screen)
@export var cluster_density: float = 0.85  # Increased for denser star clusters
@export var background_stars_percent: float = 0.15  # Reduced for more clustered appearance
@export var elongated_clusters: bool = true  # Create elliptical clusters for milky way bands

## Star animation options
@export_group("Star Animation")
@export var enable_twinkle: bool = true
@export var twinkle_speed: float = 0.5
@export var twinkle_amount: float = 0.3

## Background color options
@export_group("Background Options")
@export var background_color: Color = Color(0, 0, 0, 1)  # Pure black background
@export var add_background_layer: bool = true

## Debug options
@export_group("Debug")
@export var debug_mode: bool = false
@export var visualize_clusters: bool = false

# Default seed to use if SeedManager is not available
const DEFAULT_SEED: int = 12345

# Internal state
var camera: Camera2D
var viewport_size: Vector2
var initialized: bool = false
var star_layers: Array[ParallaxLayer] = []
var _twinkle_time: float = 0.0
var background_layer: ParallaxLayer = null
var background_seed: int = DEFAULT_SEED

# Cluster data for far stars
var _cluster_centers: Array = []
var _cluster_sizes: Array = []
var _cluster_elongation: Array = []  # How stretched the cluster is (1.0 = circle, >1.0 = ellipse)
var _cluster_rotation_angle: Array = []    # Rotation angle of cluster in radians

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
	background_seed = DEFAULT_SEED  # Default deterministic seed
	
	if use_game_seed:
		# Try to get seed from SeedManager
		if has_node("/root/SeedManager"):
			# Wait for SeedManager to be fully initialized if needed
			if SeedManager.has_method("is_initialized") and not SeedManager.is_initialized and SeedManager.has_signal("seed_initialized"):
				await SeedManager.seed_initialized
			
			background_seed = SeedManager.get_seed()
			
			# Listen for seed changes
			if SeedManager.has_signal("seed_changed") and not SeedManager.is_connected("seed_changed", _on_seed_changed):
				SeedManager.connect("seed_changed", _on_seed_changed)
			
			if debug_mode:
				print("SpaceBackground: Using global seed: ", background_seed)
		else:
			# Log error but use default seed
			push_warning("SpaceBackground: SeedManager not found, using default seed: " + str(DEFAULT_SEED))
			if debug_mode:
				print("SpaceBackground: Using default seed: ", background_seed)
	
	# Generate cluster data if clustering is enabled
	if enable_clustering:
		_generate_clusters(background_seed)
	
	# Add a solid black background layer first
	if add_background_layer:
		create_background_layer()
	
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

# Handle seed changes
func _on_seed_changed(new_seed: int) -> void:
	if debug_mode:
		print("SpaceBackground: Seed changed from ", background_seed, " to ", new_seed)
	
	# Update seed and regenerate background
	background_seed = new_seed
	reset()

func find_camera() -> void:
	# First try finding the player ship through the EntityManager
	if has_node("/root/EntityManager") and EntityManager.has_method("get_nearest_entity"):
		var player = EntityManager.get_nearest_entity(Vector2.ZERO, "player")
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

# Generate cluster centers for the far star layer
func _generate_clusters(seed_value: int) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 54321
	
	_cluster_centers.clear()
	_cluster_sizes.clear()
	_cluster_elongation.clear()
	_cluster_rotation_angle.clear()
	
	# Generate milky way band (large elongated central cluster)
	if elongated_clusters:
		var extended_size = viewport_size * 3
		
		# Create main galactic band
		var central_pos = Vector2(extended_size.x * 0.5, extended_size.y * 0.5)
		var main_radius = min(extended_size.x, extended_size.y) * 0.7
		var main_elongation = 3.0 + rng.randf() * 2.0  # 3.0-5.0 elongation for main band
		var main_rotation = rng.randf() * PI  # Random rotation
		
		_cluster_centers.append(central_pos)
		_cluster_sizes.append(main_radius)
		_cluster_elongation.append(main_elongation)
		_cluster_rotation_angle.append(main_rotation)
		
		# Generate some arm-like structures coming from the main band
		var arm_count = 2 + rng.randi() % 3  # 2-4 arms
		for arm in range(arm_count):
			var angle = main_rotation + (arm * TAU / float(arm_count)) + rng.randf_range(-0.2, 0.2)
			var distance = main_radius * 0.7
			var arm_pos = central_pos + Vector2(cos(angle), sin(angle)) * distance
			var arm_radius = main_radius * rng.randf_range(0.3, 0.5)
			var arm_elongation = 2.0 + rng.randf() * 1.5  # 2.0-3.5 elongation
			var arm_rotation = angle + PI/2  # Perpendicular to arm direction
			
			_cluster_centers.append(arm_pos)
			_cluster_sizes.append(arm_radius)
			_cluster_elongation.append(arm_elongation)
			_cluster_rotation_angle.append(arm_rotation)
	
	# Generate additional smaller clusters
	var remaining_clusters = cluster_count - (_cluster_centers.size() if elongated_clusters else 0)
	for i in range(remaining_clusters):
		# Position cluster within extended viewport
		var extended_size = viewport_size * 3
		var cluster_pos = Vector2(
			rng.randf_range(0, extended_size.x),
			rng.randf_range(0, extended_size.y)
		)
		
		# Randomize cluster size
		var cluster_radius = lerp(
			cluster_size_min * min(extended_size.x, extended_size.y),
			cluster_size_max * min(extended_size.x, extended_size.y),
			rng.randf()
		)
		
		# Some clusters are slightly elongated to create natural variations
		var is_elongated = rng.randf() < 0.7  # 70% chance of elongation
		var this_elongation = 1.0
		if is_elongated:
			this_elongation = 1.0 + rng.randf() * 1.5  # Elongation between 1.0-2.5
		
		var this_rotation = rng.randf() * TAU
		
		_cluster_centers.append(cluster_pos)
		_cluster_sizes.append(cluster_radius)
		_cluster_elongation.append(this_elongation)
		_cluster_rotation_angle.append(this_rotation)
		
		if debug_mode:
			print("Generated cluster ", i, " at ", cluster_pos, " with radius ", cluster_radius, 
				  ", elongation ", this_elongation, ", rotation ", this_rotation)

# Create a background layer with solid color
func create_background_layer() -> void:
	background_layer = ParallaxLayer.new()
	background_layer.name = "BackgroundLayer"
	background_layer.motion_scale = Vector2.ZERO  # Fixed background
	background_layer.motion_mirroring = viewport_size  # Make it repeat seamlessly
	add_child(background_layer)
	
	# Create a ColorRect for the background
	var background_rect = ColorRect.new()
	background_rect.name = "BackgroundRect"
	background_rect.color = background_color
	background_rect.size = viewport_size * 1.5  # Make it larger to ensure full coverage
	background_rect.position = -viewport_size * 0.25  # Center it
	background_layer.add_child(background_rect)
	
	# Ensure it's at the bottom of the visual stack
	move_child(background_layer, 0)

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
	
	# Set up clustering for far stars only
	if layer_name == "FarStars" and enable_clustering:
		star_field.use_clustering = true
		star_field.cluster_centers = _cluster_centers
		star_field.cluster_sizes = _cluster_sizes
		star_field.cluster_elongation = _cluster_elongation  # Pass elongation data
		star_field.cluster_rotation_angle = _cluster_rotation_angle  # Pass rotation data
		star_field.cluster_density = cluster_density
		star_field.background_stars_percent = background_stars_percent
		star_field.visualize_clusters = visualize_clusters
		star_field.use_color_variation = true  # Enable color variation for far stars
	
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
	var star_colors: Array = []  # Store individual colors for each star
	var star_color: Color = Color(1, 1, 1, 0.7)  # Base color for non-colorful stars
	var max_size: Vector2 = Vector2(2, 2)
	var viewport_size: Vector2 = Vector2(3000, 3000)
	var seed_value: int = 0
	var enable_twinkle: bool = true
	var twinkle_time: float = 0.0
	var twinkle_amount: float = 0.3
	var parent_background: Node = null
	
	# Clustering parameters
	var use_clustering: bool = false
	var cluster_centers: Array = []
	var cluster_sizes: Array = []
	var cluster_elongation: Array = []  # How stretched each cluster is
	var cluster_rotation_angle: Array = []    # Rotation angle for each cluster
	var cluster_density: float = 0.7
	var background_stars_percent: float = 0.2
	var visualize_clusters: bool = false
	var use_color_variation: bool = false  # Enable different colored stars
	
	var rng: RandomNumberGenerator
	
	func _ready() -> void:
		rng = RandomNumberGenerator.new()
		rng.seed = seed_value if seed_value != 0 else 12345
		
		generate_stars()
	
	# Get a random star color with variation
	func _get_star_color(cluster_idx: int, distance_factor: float) -> Color:
		if not use_color_variation:
			return star_color
			
		# Base colors for different cluster types
		var blue_white = Color(0.8, 0.85, 1.0, 0.8)    # Blue-white stars
		var yellow = Color(1.0, 0.9, 0.7, 0.8)         # Yellow stars
		var orange = Color(1.0, 0.8, 0.6, 0.8)         # Orange stars
		var red = Color(1.0, 0.7, 0.7, 0.8)            # Reddish stars
		var blue = Color(0.7, 0.8, 1.0, 0.8)           # Bluish stars
		
		# The base color depends on the cluster number (for consistent cluster colors)
		var base_color = blue_white
		
		# Each cluster gets its own dominant color palette
		# This creates the effect of different star types in different regions
		match cluster_idx % 5:
			0: base_color = blue_white
			1: base_color = yellow
			2: base_color = orange 
			3: base_color = red
			4: base_color = blue
		
		# Distance factor affects color - center stars might be different from edge stars
		var color_shift = 0.1 * distance_factor
		
		# Add subtle random variation
		var r_shift = rng.randf_range(-0.1, 0.1)
		var g_shift = rng.randf_range(-0.1, 0.1)
		var b_shift = rng.randf_range(-0.1, 0.1)
		
		return Color(
			clamp(base_color.r + r_shift + color_shift, 0.3, 1.0),
			clamp(base_color.g + g_shift + color_shift, 0.3, 1.0), 
			clamp(base_color.b + b_shift + color_shift, 0.3, 1.0),
			base_color.a
		)
	
	# Generate the star data with optional clustering
	func generate_stars() -> void:
		star_positions.resize(star_count)
		star_sizes.resize(star_count)
		star_twinkle_offset.resize(star_count)
		star_colors.resize(star_count)
		
		if use_clustering and not cluster_centers.is_empty():
			# Calculate how many background stars vs. cluster stars
			var background_stars = int(star_count * background_stars_percent)
			var clustered_stars = star_count - background_stars
			
			# First generate background stars
			for i in range(background_stars):
				star_positions[i] = Vector2(
					rng.randf_range(0, viewport_size.x),
					rng.randf_range(0, viewport_size.y)
				)
				star_sizes[i] = rng.randf_range(0.5, max_size.x)
				star_twinkle_offset[i] = rng.randf() * TAU
				
				# Background stars are mostly white with slight variations
				var bg_color = star_color
				if use_color_variation:
					var slight_variation = 0.05
					bg_color = Color(
						clamp(star_color.r + rng.randf_range(-slight_variation, slight_variation), 0.7, 1.0),
						clamp(star_color.g + rng.randf_range(-slight_variation, slight_variation), 0.7, 1.0),
						clamp(star_color.b + rng.randf_range(-slight_variation, slight_variation), 0.7, 1.0),
						star_color.a
					)
				star_colors[i] = bg_color
			
			# Then generate clustered stars
			var stars_per_cluster = int(clustered_stars / float(cluster_centers.size()))
			var remaining_stars = clustered_stars - (stars_per_cluster * cluster_centers.size())
			
			var star_index = background_stars
			
			# Distribute stars among clusters
			for cluster_idx in range(cluster_centers.size()):
				var center = cluster_centers[cluster_idx]
				var radius = cluster_sizes[cluster_idx]
				var elongation = 1.0
				var rotation_angle = 0.0
				
				# Use elongation and rotation data if available
				if cluster_idx < cluster_elongation.size():
					elongation = cluster_elongation[cluster_idx]
				if cluster_idx < cluster_rotation_angle.size():
					rotation_angle = cluster_rotation_angle[cluster_idx]
				
				# Add the base number of stars to this cluster
				var stars_for_this_cluster = stars_per_cluster
				
				# Large elongated clusters get more stars
				if elongation > 2.0:
					stars_for_this_cluster = int(stars_for_this_cluster * 1.5)
				
				# Add one extra star to some clusters if we have remaining stars
				if remaining_stars > 0:
					stars_for_this_cluster += 1
					remaining_stars -= 1
					
				# Make sure we don't exceed the star count
				stars_for_this_cluster = min(stars_for_this_cluster, star_count - star_index)
				
				# Populate this cluster
				for i in range(stars_for_this_cluster):
					if star_index >= star_count:
						break
					
					# Use gaussian-like distribution for star positions
					# More stars near center, fewer at edges
					var distance_factor = pow(rng.randf(), 1.0 / cluster_density)
					var angle = rng.randf() * TAU
					
					# For elongated clusters, adjust the distance based on angle
					var adjusted_distance = distance_factor
					if elongation > 1.0:
						# Transform angle relative to the rotation angle
						var relative_angle = angle - rotation_angle
						# Elongate along the main axis
						var stretch_factor = 1.0 - 0.5 * (1.0 - 1.0/elongation) * abs(cos(relative_angle))
						adjusted_distance *= stretch_factor
					
					var distance = radius * adjusted_distance
					
					# Calculate position with consideration for rotation
					var pos = center + Vector2(
						cos(angle) * distance,
						sin(angle) * distance
					)
					
					# Wrap positions to ensure they're within viewport bounds
					pos.x = fmod(pos.x + viewport_size.x, viewport_size.x)
					pos.y = fmod(pos.y + viewport_size.y, viewport_size.y)
					
					star_positions[star_index] = pos
					
					# Stars in clusters have varying sizes
					var size_multiplier = 0.7 + 0.6 * distance_factor
					star_sizes[star_index] = rng.randf_range(0.5, max_size.x) * size_multiplier
					star_twinkle_offset[star_index] = rng.randf() * TAU
					
					# Assign color based on cluster and position
					star_colors[star_index] = _get_star_color(cluster_idx, distance_factor)
					
					star_index += 1
		else:
			# Original uniform distribution
			for i in range(star_count):
				star_positions[i] = Vector2(
					rng.randf_range(0, viewport_size.x),
					rng.randf_range(0, viewport_size.y)
				)
				star_sizes[i] = rng.randf_range(0.5, max_size.x)
				star_twinkle_offset[i] = rng.randf() * TAU
				star_colors[i] = star_color
	
	# Draw the stars
	func _draw() -> void:
		# Optionally visualize clusters
		if use_clustering and visualize_clusters:
			for i in range(cluster_centers.size()):
				var center = cluster_centers[i]
				var radius = cluster_sizes[i]
				
				if i < cluster_elongation.size() and i < cluster_rotation_angle.size():
					# Draw elliptical clusters
					var elongation = cluster_elongation[i]
					var rotation_angle = cluster_rotation_angle[i]
					
					# Draw the elliptical boundary
					var points = 32  # Number of points to approximate the ellipse
					var ellipse_points = PackedVector2Array()
					for p in range(points + 1):
						var angle = TAU * p / float(points)
						var x = cos(angle) * radius
						var y = sin(angle) * radius / elongation
						var rotated_x = x * cos(rotation_angle) - y * sin(rotation_angle)
						var rotated_y = x * sin(rotation_angle) + y * cos(rotation_angle)
						ellipse_points.append(center + Vector2(rotated_x, rotated_y))
					
					draw_polyline(ellipse_points, Color(1, 0, 0, 0.3), 2.0)
					draw_circle(center, 5, Color(1, 0, 0, 0.5))
				else:
					# Draw circular clusters
					draw_circle(center, radius, Color(1, 0, 0, 0.1))
					draw_circle(center, 5, Color(1, 0, 0, 0.5))
		
		# Draw all stars
		for i in range(star_positions.size()):
			var pos = star_positions[i]
			var base_size = star_sizes[i]
			var size = base_size
			
			# Get the star's color (either from array or default)
			var color = star_color
			if i < star_colors.size() and star_colors[i] != null:
				color = star_colors[i]
				
			# Apply twinkle effect if enabled
			if enable_twinkle:
				var twinkle_factor = sin(twinkle_time + star_twinkle_offset[i]) * 0.5 + 0.5
				size = base_size * (1.0 - twinkle_amount + twinkle_amount * twinkle_factor)
				
				# Adjust alpha for twinkle effect
				var alpha_factor = 0.7 + 0.3 * twinkle_factor
				color.a = color.a * alpha_factor
				
				draw_rect(Rect2(pos.x - size/2, pos.y - size/2, size, size), color)
			else:
				draw_rect(Rect2(pos.x - size/2, pos.y - size/2, size, size), color)

# Reset the background (can be called when changing scenes or restarting game)
func reset() -> void:
	initialized = false
	camera = null
	
	# Clear existing layers
	for parallax_layer in star_layers:
		parallax_layer.queue_free()
	star_layers.clear()
	
	if background_layer:
		background_layer.queue_free()
		background_layer = null
	
	# Reset cluster data
	_cluster_centers.clear()
	_cluster_sizes.clear()
	_cluster_elongation.clear()
	_cluster_rotation_angle.clear()
	
	# Setup again
	call_deferred("setup_background")

# Public method to update viewport size (call if window is resized)
func update_viewport_size() -> void:
	viewport_size = get_viewport().get_visible_rect().size
	
	# Update background color rect
	if background_layer:
		var background_rect = background_layer.get_node_or_null("BackgroundRect")
		if background_rect:
			background_rect.size = viewport_size * 1.5
			background_rect.position = -viewport_size * 0.25
	
	# If using clustering, recalculate clusters for the new viewport size
	if enable_clustering:
		_generate_clusters(background_seed)
	
	# Update mirroring size for all layers
	for parallax_layer in star_layers:
		parallax_layer.motion_mirroring = viewport_size * 3
		
		var star_field = parallax_layer.get_node_or_null("StarField")
		if star_field and star_field is StarField:
			star_field.viewport_size = viewport_size * 3
			
			# Update clustering data if this is the far layer
			if star_field.use_clustering:
				star_field.cluster_centers = _cluster_centers
				star_field.cluster_sizes = _cluster_sizes
				star_field.cluster_elongation = _cluster_elongation
				star_field.cluster_rotation_angle = _cluster_rotation_angle
			
			star_field.generate_stars()
			star_field.queue_redraw()
