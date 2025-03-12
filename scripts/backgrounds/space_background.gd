# scripts/backgrounds/space_background.gd - Highly optimized implementation
extends ParallaxBackground
class_name ImprovedSpaceBackground

# Star layer configuration
@export var star_count_far: int = 3000  # Reduced from 5000
@export var star_count_mid: int = 600   # Reduced from 750
@export var star_count_near: int = 300  # Reduced from 350
@export var parallax_scale: float = 1.0
@export var use_game_seed: bool = true

# Clustering configuration - combined into single group
@export_group("Star Clustering")
@export var enable_clustering: bool = true
@export var cluster_count: int = 10
@export var cluster_size_min: float = 0.15
@export var cluster_size_max: float = 0.4
@export var cluster_density: float = 0.85
@export var background_stars_percent: float = 0.15
@export var elongated_clusters: bool = true

# Animation flags
@export var enable_twinkle: bool = true
@export var twinkle_speed: float = 0.5
@export var twinkle_amount: float = 0.3

# Background properties
@export var background_color: Color = Color(0, 0, 0, 1)
@export var add_background_layer: bool = true

# Debug options
@export var debug_mode: bool = false
@export var visualize_clusters: bool = false

# Constants
const DEFAULT_SEED: int = 12345

# Internal state - cached
var camera: Camera2D
var viewport_size: Vector2
var initialized: bool = false
var background_seed: int = DEFAULT_SEED
var layers_per_type := {"far": [], "mid": [], "near": []}
var _cluster_data: Array = []
var _twinkle_time: float = 0.0
var background_layer: ParallaxLayer

# Cached colors for reuse
var _far_color := Color(0.8, 0.8, 1.0, 0.4)
var _mid_color := Color(0.9, 0.9, 1.0, 0.6)
var _near_color := Color(1.0, 1.0, 1.0, 0.8)

# Lookup tables for performance
var _sin_lookup: Array = []
var _cos_lookup: Array = []

signal background_initialized

# Cluster data class with direct properties for faster access
class ClusterData:
	var center: Vector2
	var size: float
	var elongation: float = 1.0
	var rotation: float = 0.0

# Star field implementation - optimized for batched rendering
class StarField extends Node2D:
	var star_count: int = 200
	var star_positions: PackedVector2Array = []
	var star_sizes: PackedFloat32Array = []
	var star_colors: Array = []
	var star_twinkle_offset: PackedFloat32Array = []
	var star_color: Color = Color(1, 1, 1, 0.7)
	var max_size: Vector2 = Vector2(2, 2)
	var viewport_size: Vector2 = Vector2(3000, 3000)
	var seed_value: int = 0
	var enable_twinkle: bool = true
	var twinkle_time: float = 0.0
	var twinkle_amount: float = 0.3
	
	# Clustering parameters
	var use_clustering: bool = false
	var cluster_data: Array = []
	var cluster_density: float = 0.7
	var background_stars_percent: float = 0.2
	var visualize_clusters: bool = false
	var use_color_variation: bool = false
	
	# Random number generator - cached
	var rng: RandomNumberGenerator
	
	func _ready() -> void:
		rng = RandomNumberGenerator.new()
		rng.seed = seed_value if seed_value != 0 else 12345
		generate_stars()
	
	# Get star color with optional variation
	func _get_star_color(cluster_idx: int, distance_factor: float) -> Color:
		if not use_color_variation:
			return star_color
			
		# Predefined colors - caching common ones
		var colors = [
			Color(0.8, 0.85, 1.0, 0.8),  # Blue-white
			Color(1.0, 0.9, 0.7, 0.8),   # Yellow
			Color(1.0, 0.8, 0.6, 0.8),   # Orange
			Color(1.0, 0.7, 0.7, 0.8),   # Red
			Color(0.7, 0.8, 1.0, 0.8)    # Blue
		]
		
		var color = colors[cluster_idx % colors.size()]
		
		# Apply distance-based variation
		var color_shift = 0.1 * distance_factor
		color.r = clamp(color.r + rng.randf_range(-0.1, 0.1) + color_shift, 0.3, 1.0)
		color.g = clamp(color.g + rng.randf_range(-0.1, 0.1) + color_shift, 0.3, 1.0)
		color.b = clamp(color.b + rng.randf_range(-0.1, 0.1) + color_shift, 0.3, 1.0)
		
		return color
	
	# Generate star data
	func generate_stars() -> void:
		# Preallocate arrays for better performance
		star_positions.resize(star_count)
		star_sizes.resize(star_count)
		star_twinkle_offset.resize(star_count)
		star_colors.resize(star_count)
		
		if use_clustering and not cluster_data.is_empty():
			_generate_clustered_stars()
		else:
			_generate_uniform_stars()
	
	# Generate clustered stars - separated for clarity
	func _generate_clustered_stars() -> void:
		var background_stars = int(star_count * background_stars_percent)
		var clustered_stars = star_count - background_stars
		
		# Generate background stars
		for i in range(background_stars):
			star_positions[i] = Vector2(rng.randf_range(0, viewport_size.x), rng.randf_range(0, viewport_size.y))
			star_sizes[i] = rng.randf_range(0.5, max_size.x)
			star_twinkle_offset[i] = rng.randf() * TAU
			
			# Simplified color variation for background stars
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
		
		# Generate clustered stars
		var stars_per_cluster = clustered_stars / max(1, cluster_data.size())
		var star_index = background_stars
		
		for cluster_idx in range(cluster_data.size()):
			var cluster = cluster_data[cluster_idx]
			var stars_for_this_cluster = stars_per_cluster
			
			# Add more stars to elongated clusters
			if cluster.elongation > 2.0:
				stars_for_this_cluster = int(stars_for_this_cluster * 1.5)
			
			stars_for_this_cluster = min(stars_for_this_cluster, star_count - star_index)
			
			for i in range(stars_for_this_cluster):
				if star_index >= star_count:
					break
				
				# Fast density distribution with fewer calculations
				var distance_factor = pow(rng.randf(), 1.0 / cluster_density)
				var angle = rng.randf() * TAU
				
				var adjusted_distance = distance_factor
				if cluster.elongation > 1.0:
					var relative_angle = angle - cluster.rotation
					var stretch_factor = 1.0 - 0.5 * (1.0 - 1.0/cluster.elongation) * abs(cos(relative_angle))
					adjusted_distance *= stretch_factor
				
				var distance = cluster.size * adjusted_distance
				var pos = cluster.center + Vector2(cos(angle) * distance, sin(angle) * distance)
				
				# Ensure stars wrap around viewport
				pos.x = fmod(pos.x + viewport_size.x, viewport_size.x)
				pos.y = fmod(pos.y + viewport_size.y, viewport_size.y)
				
				star_positions[star_index] = pos
				star_sizes[star_index] = rng.randf_range(0.5, max_size.x) * (0.7 + 0.6 * distance_factor)
				star_twinkle_offset[star_index] = rng.randf() * TAU
				star_colors[star_index] = _get_star_color(cluster_idx, distance_factor)
				
				star_index += 1
	
	# Generate uniform stars
	func _generate_uniform_stars() -> void:
		for i in range(star_count):
			star_positions[i] = Vector2(rng.randf_range(0, viewport_size.x), rng.randf_range(0, viewport_size.y))
			star_sizes[i] = rng.randf_range(0.5, max_size.x)
			star_twinkle_offset[i] = rng.randf() * TAU
			star_colors[i] = star_color
	
	# Optimized draw function with batches
	func _draw() -> void:
		# Draw clusters first if debugging
		if use_clustering and visualize_clusters:
			_draw_clusters()
		
		# Draw all stars at once
		for i in range(star_positions.size()):
			var pos = star_positions[i]
			var base_size = star_sizes[i]
			var size = base_size
			
			# Get color with null check
			var color = star_colors[i] if i < star_colors.size() else star_color
				
			# Apply twinkle effect
			if enable_twinkle:
				var twinkle_factor = sin(twinkle_time + star_twinkle_offset[i]) * 0.5 + 0.5
				size = base_size * (1.0 - twinkle_amount + twinkle_amount * twinkle_factor)
				color.a = color.a * (0.7 + 0.3 * twinkle_factor)
			
			draw_rect(Rect2(pos.x - size/2, pos.y - size/2, size, size), color)
	
	# Separated cluster drawing for better performance
	func _draw_clusters() -> void:
		for cluster in cluster_data:
			if cluster.elongation > 1.0:
				var points = PackedVector2Array()
				for p in range(33):
					var angle = TAU * p / 32.0
					var x = cos(angle) * cluster.size
					var y = sin(angle) * cluster.size / cluster.elongation
					var rotated_x = x * cos(cluster.rotation) - y * sin(cluster.rotation)
					var rotated_y = x * sin(cluster.rotation) + y * cos(cluster.rotation)
					points.append(cluster.center + Vector2(rotated_x, rotated_y))
				
				draw_polyline(points, Color(1, 0, 0, 0.3), 2.0)
			else:
				draw_circle(cluster.center, cluster.size, Color(1, 0, 0, 0.1))
			
			draw_circle(cluster.center, 5, Color(1, 0, 0, 0.5))

func _ready() -> void:
	# Initialize lookup tables
	_initialize_lookup_tables()
	# Wait one frame to ensure the viewport is properly set up
	await get_tree().process_frame
	setup_background()

# Initialize lookup tables for sine and cosine
func _initialize_lookup_tables() -> void:
	_sin_lookup.resize(360)
	_cos_lookup.resize(360)
	for i in range(360):
		var angle = deg_to_rad(i)
		_sin_lookup[i] = sin(angle)
		_cos_lookup[i] = cos(angle)

# Setup background with improved initialization
func setup_background() -> void:
	if initialized:
		return
		
	viewport_size = get_viewport().get_visible_rect().size
	find_camera()
	
	# Get seed from SeedManager if available
	if use_game_seed and has_node("/root/SeedManager"):
		var seed_manager = get_node("/root/SeedManager")
		if not seed_manager.is_initialized and seed_manager.has_signal("seed_initialized"):
			await seed_manager.seed_initialized
		
		background_seed = seed_manager.get_seed()
		if not seed_manager.is_connected("seed_changed", _on_seed_changed):
			seed_manager.connect("seed_changed", _on_seed_changed)
	
	# Generate clusters if enabled
	if enable_clustering:
		_generate_clusters(background_seed)
	
	# Create background layer first
	if add_background_layer:
		create_background_layer()
	
	# Create star layers in order from back to front
	create_star_layer("FarStars", 0.05 * parallax_scale, star_count_far, 
		_far_color, Vector2(1, 1), background_seed + 1)
	
	create_star_layer("MidStars", 0.1 * parallax_scale, star_count_mid, 
		_mid_color, Vector2(1.5, 1.5), background_seed + 2)
	
	create_star_layer("NearStars", 0.2 * parallax_scale, star_count_near, 
		_near_color, Vector2(2, 2), background_seed + 3)
	
	scroll_ignore_camera_zoom = true
	initialized = true
	background_initialized.emit()

# Handle seed changes
func _on_seed_changed(new_seed: int) -> void:
	background_seed = new_seed
	reset()

# Simplified camera finding logic
func find_camera() -> void:
	# Try direct viewport camera first
	camera = get_viewport().get_camera_2d()
	if camera:
		return
	
	# Try cameras in the "camera" group
	var cameras = get_tree().get_nodes_in_group("camera")
	if not cameras.is_empty():
		camera = cameras[0]
		return
	
	# Fall back to common camera path
	camera = get_node_or_null("/root/Main/Camera2D")

# Generate cluster data with optimized calculations
func _generate_clusters(seed_value: int) -> void:
	var rng = RandomNumberGenerator.new()
	rng.seed = seed_value + 54321
	
	_cluster_data.clear()
	var extended_size = viewport_size * 3
	
	if elongated_clusters:
		# Create main galactic band
		var main_cluster = ClusterData.new()
		main_cluster.center = Vector2(extended_size.x * 0.5, extended_size.y * 0.5)
		main_cluster.size = min(extended_size.x, extended_size.y) * 0.7
		main_cluster.elongation = 3.0 + rng.randf() * 2.0
		main_cluster.rotation = rng.randf() * PI
		_cluster_data.append(main_cluster)
		
		# Generate arm structures
		var arm_count = 2 + rng.randi() % 3
		for arm in range(arm_count):
			var angle = main_cluster.rotation + (arm * TAU / float(arm_count)) + rng.randf_range(-0.2, 0.2)
			var arm_cluster = ClusterData.new()
			arm_cluster.center = main_cluster.center + Vector2(cos(angle), sin(angle)) * (main_cluster.size * 0.7)
			arm_cluster.size = main_cluster.size * rng.randf_range(0.3, 0.5)
			arm_cluster.elongation = 2.0 + rng.randf() * 1.5
			arm_cluster.rotation = angle + PI/2
			_cluster_data.append(arm_cluster)
	
	# Generate additional clusters
	var remaining_clusters = cluster_count - (_cluster_data.size() if elongated_clusters else 0)
	for i in range(remaining_clusters):
		var cluster = ClusterData.new()
		cluster.center = Vector2(
			rng.randf_range(0, extended_size.x),
			rng.randf_range(0, extended_size.y)
		)
		
		var size_factor = rng.randf()
		cluster.size = lerp(
			cluster_size_min * min(extended_size.x, extended_size.y),
			cluster_size_max * min(extended_size.x, extended_size.y),
			size_factor
		)
		
		if rng.randf() < 0.7:
			cluster.elongation = 1.0 + rng.randf() * 1.5
		cluster.rotation = rng.randf() * TAU
		
		_cluster_data.append(cluster)

# Create solid color background
func create_background_layer() -> void:
	background_layer = ParallaxLayer.new()
	background_layer.name = "BackgroundLayer"
	background_layer.motion_scale = Vector2.ZERO
	background_layer.motion_mirroring = viewport_size
	add_child(background_layer)
	
	var background_rect = ColorRect.new()
	background_rect.name = "BackgroundRect"
	background_rect.color = background_color
	background_rect.size = viewport_size * 1.5
	background_rect.position = -viewport_size * 0.25
	background_layer.add_child(background_rect)
	
	move_child(background_layer, 0)

# Create star layer with specified parameters
func create_star_layer(layer_name: String, scroll_factor: float, count: int, 
					star_color: Color, max_size: Vector2, seed_value: int) -> void:
	var parallax_layer = ParallaxLayer.new()
	parallax_layer.name = layer_name
	parallax_layer.motion_scale = Vector2(scroll_factor, scroll_factor)
	parallax_layer.motion_mirroring = viewport_size * 3
	add_child(parallax_layer)
	
	# Store in type-based dictionary for easy access
	var layer_type = "far"
	if "Mid" in layer_name:
		layer_type = "mid"
	elif "Near" in layer_name:
		layer_type = "near"
	
	layers_per_type[layer_type].append(parallax_layer)
	
	var star_field = StarField.new()
	star_field.name = "StarField"
	star_field.star_count = count
	star_field.viewport_size = viewport_size * 3
	star_field.star_color = star_color
	star_field.max_size = max_size
	star_field.seed_value = seed_value
	star_field.enable_twinkle = enable_twinkle
	star_field.twinkle_amount = twinkle_amount
	
	if layer_name == "FarStars" and enable_clustering:
		star_field.use_clustering = true
		star_field.cluster_data = _cluster_data
		star_field.cluster_density = cluster_density
		star_field.background_stars_percent = background_stars_percent
		star_field.visualize_clusters = visualize_clusters
		star_field.use_color_variation = true
	
	parallax_layer.add_child(star_field)

# Update background position and animation
func _process(delta: float) -> void:
	if not initialized:
		return
		
	# Update scroll position if camera exists
	if camera and is_instance_valid(camera):
		set_scroll_offset(camera.get_screen_center_position())
	
	# Update twinkle animation
	if enable_twinkle:
		_twinkle_time += delta * twinkle_speed
		
		# Update all star layers at once
		for layer_type in layers_per_type:
			for parallax_layer in layers_per_type[layer_type]:
				var star_field = parallax_layer.get_node_or_null("StarField")
				if star_field and star_field is StarField:
					star_field.twinkle_time = _twinkle_time
					star_field.queue_redraw()

# Reset and regenerate background
func reset() -> void:
	initialized = false
	camera = null
	
	# Clear all star layers
	for layer_type in layers_per_type:
		for parallax_layer in layers_per_type[layer_type]:
			parallax_layer.queue_free()
		layers_per_type[layer_type].clear()
	
	if background_layer:
		background_layer.queue_free()
		background_layer = null
	
	_cluster_data.clear()
	
	# Setup again
	call_deferred("setup_background")

# Update when viewport size changes
func update_viewport_size() -> void:
	if not initialized:
		return
		
	viewport_size = get_viewport().get_visible_rect().size
	
	if background_layer:
		var background_rect = background_layer.get_node_or_null("BackgroundRect")
		if background_rect:
			background_rect.size = viewport_size * 1.5
			background_rect.position = -viewport_size * 0.25
	
	if enable_clustering:
		_generate_clusters(background_seed)
	
	# Update all layers
	for layer_type in layers_per_type:
		for parallax_layer in layers_per_type[layer_type]:
			parallax_layer.motion_mirroring = viewport_size * 3
			
			var star_field = parallax_layer.get_node_or_null("StarField")
			if star_field and star_field is StarField:
				star_field.viewport_size = viewport_size * 3
				
				if star_field.use_clustering:
					star_field.cluster_data = _cluster_data
				
				star_field.generate_stars()
				star_field.queue_redraw()
