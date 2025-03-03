extends Node
class_name AsteroidSpawner

# Import the existing RandomAsteroid generator
const RandomAsteroidGenerator = preload("res://random_asteroid.gd")

# Asteroid generation parameters
@export var asteroid_percentage = 15
@export var minimum_asteroids = 8
@export var min_asteroids_per_cell = 50
@export var max_asteroids_per_cell = 50
@export var asteroid_scale_min = 0.9
@export var asteroid_scale_max = 1.1
@export var cell_margin = 0.15
@export var cluster_percentage = 60

# Size distribution
@export var large_percentage = 70
@export var medium_percentage = 20
# Small percentage is implied as the remaining 10%

# Reference to the grid
var grid = null

# Arrays to track asteroids
var asteroid_fields = []
var asteroid_data = []

# 2D array to store number of asteroids per cell
var asteroid_counts = []

# BACKWARD COMPATIBILITY: Empty sprite arrays to prevent crashes in asteroid.gd
var large_asteroid_sprites = []
var medium_asteroid_sprites = []
var small_asteroid_sprites = []

# Asteroid scene reference
var asteroid_scene_path = "res://scenes/asteroid.tscn"

# Asteroids texture cache - key: seed value, value: texture
var asteroid_texture_cache = {}
var texture_cache_size_limit = 250

# Asteroid pooling - organized by size category
var asteroid_pool = {
	"large": [],
	"medium": [],
	"small": []
}
var max_pool_size = 300
var current_active_asteroids = []

# Cache of spawned asteroid instances by cell
var cell_asteroid_cache = {}

func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for asteroid spawning!")
		return
	
	# Initialize asteroid pool
	_initialize_pool()
	
	# BACKWARD COMPATIBILITY: Initialize empty sprite arrays with one dummy texture
	_initialize_compat_sprites()
	
	# Connect to grid signals
	if grid.has_signal("_seed_changed"):
		grid.connect("_seed_changed", _on_grid_seed_changed)
	
	if grid.has_signal("_cell_loaded"):
		grid.connect("_cell_loaded", _on_cell_loaded)
	if grid.has_signal("_cell_unloaded"):
		grid.connect("_cell_unloaded", _on_cell_unloaded)

# BACKWARD COMPATIBILITY: Initialize empty sprite arrays with one dummy texture
func _initialize_compat_sprites():
	# Create a simple dummy texture for each size - needed for backward compatibility
	# but the actual textures will be generated procedurally
	large_asteroid_sprites = [_create_dummy_texture(RandomAsteroidGenerator.ASTEROID_SIZE_LARGE)]
	medium_asteroid_sprites = [_create_dummy_texture(RandomAsteroidGenerator.ASTEROID_SIZE_MEDIUM)]
	small_asteroid_sprites = [_create_dummy_texture(RandomAsteroidGenerator.ASTEROID_SIZE_SMALL)]

# BACKWARD COMPATIBILITY: Create a simple dummy texture
func _create_dummy_texture(size: int) -> Texture2D:
	var image = Image.create(size, size, true, Image.FORMAT_RGBA8)
	var center = size / 2
	var radius = size / 2 - 2
	
	for y in range(size):
		for x in range(size):
			var dist = Vector2(x - center, y - center).length()
			if dist < radius:
				image.set_pixel(x, y, Color(0.2, 0.2, 0.2, 1.0))
	
	return ImageTexture.create_from_image(image)

# Initialize the asteroid pool with some pre-created asteroids
func _initialize_pool():
	var initial_count = {
		"large": 25,
		"medium": 15,
		"small": 10
	}
	
	for size_category in asteroid_pool.keys():
		for i in range(initial_count[size_category]):
			var asteroid = _create_new_asteroid_instance()
			if asteroid:
				asteroid.size_category = size_category
				asteroid_pool[size_category].append(asteroid)

# Function to generate asteroids in grid cells
func generate_asteroids():
	asteroid_fields.clear()
	asteroid_data.clear()
	asteroid_counts = []
	
	if grid.cell_contents.size() == 0:
		return
	
	# Initialize the asteroid counts array to match grid size
	for y in range(int(grid.grid_size.y)):
		asteroid_counts.append([])
		for x in range(int(grid.grid_size.x)):
			asteroid_counts[y].append(0)
	
	# Get a list of non-boundary cells that don't already contain planets
	var available_cells = []
	for y in range(1, int(grid.grid_size.y) - 1):
		for x in range(1, int(grid.grid_size.x) - 1):
			if grid.is_boundary_cell(x, y):
				continue
			
			if grid.cell_contents[y][x] != grid.CellContent.EMPTY:
				continue
			
			available_cells.append(Vector2i(x, y))
	
	# Determine how many asteroid fields to spawn
	var non_boundary_count = available_cells.size()
	var asteroid_count = max(minimum_asteroids, int(non_boundary_count * float(asteroid_percentage) / 100.0))
	asteroid_count = min(asteroid_count, non_boundary_count)
	
	# Setup RNG with the grid's seed
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value + 1000
	
	var actual_asteroid_count = 0
	
	# Generate asteroid fields
	for i in range(asteroid_count * 2):
		if available_cells.size() == 0:
			break
		
		var idx = rng.randi() % available_cells.size()
		var asteroid_pos = available_cells[idx]
		var x = asteroid_pos.x
		var y = asteroid_pos.y
		
		available_cells.remove_at(idx)
		
		grid.cell_contents[y][x] = grid.CellContent.ASTEROID
		actual_asteroid_count += 1
		
		asteroid_counts[y][x] = min_asteroids_per_cell
		
		var world_pos = Vector2(
			x * grid.cell_size.x + grid.cell_size.x / 2,
			y * grid.cell_size.y + grid.cell_size.y / 2
		)
		
		asteroid_fields.append({
			"position": world_pos,
			"grid_x": x,
			"grid_y": y
		})
		
		_generate_asteroids_for_field(x, y, world_pos, rng)
		
		if actual_asteroid_count >= asteroid_count:
			break
	
	grid.queue_redraw()

# Generate asteroid data for a specific field
func _generate_asteroids_for_field(grid_x, grid_y, center_pos, rng):
	var field_asteroids = []
	
	# Apply cell margins for this field
	var safe_width = grid.cell_size.x * (1.0 - 2 * cell_margin)
	var safe_height = grid.cell_size.y * (1.0 - 2 * cell_margin)
	var margin_x = grid.cell_size.x * cell_margin
	var margin_y = grid.cell_size.y * cell_margin
	
	var num_asteroids = min_asteroids_per_cell
	
	# Calculate how many of each size based on percentages
	var large_count = int(num_asteroids * large_percentage / 100.0)
	var medium_count = int(num_asteroids * medium_percentage / 100.0)
	var small_count = num_asteroids - large_count - medium_count
	
	# Create distribution of sizes
	var size_distribution = []
	for i in range(large_count): size_distribution.append("large")
	for i in range(medium_count): size_distribution.append("medium")
	for i in range(small_count): size_distribution.append("small")
	
	size_distribution.shuffle()
	
	# Track positions and sizes for overlap prevention
	var placed_asteroids = []
	
	for j in range(num_asteroids):
		# Generate a unique seed for each asteroid
		var asteroid_seed = grid.seed_value + grid_y * 10000 + grid_x * 100 + j
		var asteroid_rng = RandomNumberGenerator.new()
		asteroid_rng.seed = asteroid_seed
		
		# Get size category from distribution
		var size_category = size_distribution[j]
		
		# Get actual pixel size based on category
		var pixel_size = 0
		match size_category:
			"large": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_LARGE
			"medium": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_MEDIUM
			"small": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_SMALL
		
		# Scale variation based on size category
		var base_scale = asteroid_rng.randf_range(asteroid_scale_min, asteroid_scale_max)
		
		# Random rotation angle
		var rotation = asteroid_rng.randf_range(0, TAU)
		
		# Random initial rotation angle for the sprite
		var initial_rotation = asteroid_rng.randf_range(0, TAU)
		
		# Random rotation speed with visible rotation
		var rotation_speed = asteroid_rng.randf_range(-0.8, 0.8)
		
		# Make sure ALL asteroids rotate at least a little bit
		if abs(rotation_speed) < 0.1:
			rotation_speed = 0.1 if rotation_speed >= 0 else -0.1
		
		# Estimate collision radius for this asteroid
		var collision_radius = pixel_size * 0.5 * base_scale
		
		# Determine if this asteroid should be part of a cluster
		var in_cluster = asteroid_rng.randf() * 100 < cluster_percentage
		var pos_offset = Vector2.ZERO
		var valid_position = false
		var attempts = 0
		var max_attempts = 20
		
		while !valid_position and attempts < max_attempts:
			if in_cluster && j > 0:  # Only cluster if not the first asteroid
				# Select a random existing asteroid to cluster around
				var parent_idx = asteroid_rng.randi() % j
				if parent_idx < placed_asteroids.size():
					var parent_offset = placed_asteroids[parent_idx].offset
					
					# Place this asteroid near the parent, but with some randomness
					var cluster_radius = min(safe_width, safe_height) * 0.25
					var angle = asteroid_rng.randf_range(0, TAU)
					var distance = asteroid_rng.randf_range(
						collision_radius + placed_asteroids[parent_idx].radius, 
						cluster_radius
					)
					
					pos_offset = parent_offset + Vector2(
						cos(angle) * distance,
						sin(angle) * distance
					)
			else:
				# For non-clustered asteroids, use grid-based positioning
				var cell_x = asteroid_rng.randi() % 10
				var cell_y = asteroid_rng.randi() % 10
				
				# Calculate position within the chosen grid section
				var section_width = safe_width / 10.0
				var section_height = safe_height / 10.0
				
				pos_offset = Vector2(
					margin_x + (cell_x * section_width) + asteroid_rng.randf_range(0, section_width) - grid.cell_size.x / 2.0,
					margin_y + (cell_y * section_height) + asteroid_rng.randf_range(0, section_height) - grid.cell_size.y / 2.0
				)
			
			# Make sure the asteroid stays within margins
			pos_offset.x = clamp(pos_offset.x, -safe_width/2.0 + collision_radius, safe_width/2.0 - collision_radius)
			pos_offset.y = clamp(pos_offset.y, -safe_height/2.0 + collision_radius, safe_height/2.0 - collision_radius)
			
			# Check for overlap with existing asteroids
			valid_position = true
			for existing in placed_asteroids:
				var distance = pos_offset.distance_to(existing.offset)
				if distance < (collision_radius + existing.radius) * 1.05:
					valid_position = false
					break
			
			attempts += 1
			
			# If clustering is causing problems, try without clustering
			if attempts > max_attempts / 2:
				in_cluster = false
		
		# Skip this asteroid if we couldn't find a valid position
		if !valid_position:
			# Try with smaller size
			if size_category == "large":
				size_category = "medium"
				pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_MEDIUM
			elif size_category == "medium":
				size_category = "small"
				pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_SMALL
			else:
				continue  # Skip if even small doesn't work
			
			collision_radius = pixel_size * 0.5 * base_scale
			
			# Quick retry with new size
			pos_offset = Vector2(
				asteroid_rng.randf_range(-safe_width/2.0 + collision_radius, safe_width/2.0 - collision_radius),
				asteroid_rng.randf_range(-safe_height/2.0 + collision_radius, safe_height/2.0 - collision_radius)
			)
			
			# Final overlap check
			valid_position = true
			for existing in placed_asteroids:
				var distance = pos_offset.distance_to(existing.offset)
				if distance < (collision_radius + existing.radius) * 1.05:
					valid_position = false
					break
					
			if !valid_position:
				continue  # Skip this asteroid
		
		# Track this asteroid for future collision detection
		placed_asteroids.append({
			"offset": pos_offset,
			"radius": collision_radius
		})
		
		# Add asteroid data with seed for texture generation
		field_asteroids.append({
			"size_category": size_category,
			"seed": asteroid_seed,
			"scale": base_scale,
			"offset": pos_offset,
			"rotation": rotation,
			"rotation_speed": rotation_speed,
			"initial_rotation": initial_rotation,
			"pixel_size": pixel_size
		})
	
	# Store the asteroid data for this field
	asteroid_data.append({
		"count": field_asteroids.size(),
		"asteroids": field_asteroids,
		"grid_x": grid_x,
		"grid_y": grid_y
	})

# Generate a procedural asteroid texture using the existing RandomAsteroid generator
func generate_asteroid_texture(seed_value: int, size_category: String) -> ImageTexture:
	# Check if already in cache
	var cache_key = str(seed_value) + "_" + size_category
	if asteroid_texture_cache.has(cache_key):
		return asteroid_texture_cache[cache_key]
	
	# Get actual pixel size based on category
	var pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_MEDIUM
	match size_category:
		"large": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_LARGE
		"medium": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_MEDIUM
		"small": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_SMALL
	
	# Create a temporary instance of RandomAsteroidGenerator
	var generator = RandomAsteroidGenerator.new()
	
	# Set parameters for the generator
	generator.seed_value = seed_value
	generator.main_rng = RandomNumberGenerator.new()
	generator.main_rng.seed = seed_value
	
	# Generate random shape parameters based on seed
	generator.set_random_shape_params()
	
	# Scale crater count based on asteroid size
	match size_category:
		"large":
			generator.CRATER_COUNT_MIN = 3
			generator.CRATER_COUNT_MAX = 5
			generator.CRATER_PIXEL_SIZE_MIN = 4
			generator.CRATER_PIXEL_SIZE_MAX = 5
		"medium":
			generator.CRATER_COUNT_MIN = 2
			generator.CRATER_COUNT_MAX = 4
			generator.CRATER_PIXEL_SIZE_MIN = 4
			generator.CRATER_PIXEL_SIZE_MAX = 4
		"small":
			generator.CRATER_COUNT_MIN = 1
			generator.CRATER_COUNT_MAX = 2
			generator.CRATER_PIXEL_SIZE_MIN = 3
			generator.CRATER_PIXEL_SIZE_MAX = 3
	
	generator.CRATER_SIZE_MIN = float(generator.CRATER_PIXEL_SIZE_MIN) / float(generator.PIXEL_RESOLUTION)
	generator.CRATER_SIZE_MAX = float(generator.CRATER_PIXEL_SIZE_MAX) / float(generator.PIXEL_RESOLUTION)
	
	# Generate the asteroid texture
	var texture = generator.create_asteroid_texture()
	
	# Cache the texture
	asteroid_texture_cache[cache_key] = texture
	
	# Limit cache size
	if asteroid_texture_cache.size() > texture_cache_size_limit:
		var oldest_key = asteroid_texture_cache.keys()[0]
		asteroid_texture_cache.erase(oldest_key)
	
	return texture

# Function to reset asteroids (used when seed changes)
func reset_asteroids():
	# Clear all caches
	asteroid_texture_cache.clear()
	cell_asteroid_cache.clear()
	
	# Return all active asteroids to pool
	_return_all_asteroids_to_pool()
	
	# Generate new asteroids
	call_deferred("generate_asteroids")

# Handler for grid seed change
func _on_grid_seed_changed(_new_seed = null):
	call_deferred("reset_asteroids")

# Method to draw asteroids using procedural generation
func draw_asteroids(_canvas: CanvasItem, loaded_cells: Dictionary):
	if not grid:
		return
	
	# Clear existing asteroid instances that aren't in loaded cells
	clear_asteroid_instances(loaded_cells)
	
	# Reset track of active asteroids
	current_active_asteroids = []
	
	# Get player for distance culling
	var player = get_node_or_null("/root/Main/Player")
	var max_draw_distance = 2500
	
	# Process each loaded cell
	for cell_pos in loaded_cells.keys():
		var x = int(cell_pos.x)
		var y = int(cell_pos.y)
		
		# Only process if this cell contains asteroids
		if y < grid.cell_contents.size() and x < grid.cell_contents[y].size() and grid.cell_contents[y][x] == grid.CellContent.ASTEROID:
			var cell_center = Vector2(
				x * grid.cell_size.x + grid.cell_size.x / 2.0,
				y * grid.cell_size.y + grid.cell_size.y / 2.0
			)
			
			# Skip cell if too far from player for optimization
			if player and cell_center.distance_to(player.global_position) > max_draw_distance:
				continue
			
			# Find the asteroid field data for this cell
			var field_index = -1
			for i in range(asteroid_fields.size()):
				if asteroid_fields[i].grid_x == x and asteroid_fields[i].grid_y == y:
					field_index = i
					break
			
			# Skip if we can't find the asteroid field data
			if field_index == -1 or field_index >= asteroid_data.size():
				continue
			
			var field_data = asteroid_data[field_index]
			
			# Check if we have cached asteroids for this cell
			var cell_key = Vector2i(x, y)
			if cell_asteroid_cache.has(cell_key):
				# Reuse cached asteroid instances
				var cached_asteroids = cell_asteroid_cache[cell_key]
				
				# Just ensure they're properly added to the scene and active
				for asteroid in cached_asteroids:
					if is_instance_valid(asteroid) and !asteroid.is_inside_tree():
						get_tree().current_scene.add_child(asteroid)
					
					if is_instance_valid(asteroid):
						asteroid.visible = true
						asteroid.set_process(true)
						current_active_asteroids.append(asteroid)
			else:
				# No cache for this cell, create new asteroid instances
				var cell_asteroids = []
				
				# Draw each asteroid in the field
				for asteroid_item in field_data.asteroids:
					# Spawn procedurally generated asteroid
					var asteroid = spawn_procedural_asteroid(
						cell_center + asteroid_item.offset,  # position
						asteroid_item.size_category,         # size category
						asteroid_item.seed,                  # seed value
						asteroid_item.scale,                 # scale
						asteroid_item.rotation_speed,        # rotation speed
						asteroid_item.initial_rotation       # initial rotation
					)
					
					# Track the asteroid if successfully created
					if asteroid:
						cell_asteroids.append(asteroid)
						current_active_asteroids.append(asteroid)
				
				# Cache the asteroids for this cell
				cell_asteroid_cache[cell_key] = cell_asteroids

# Spawn a procedurally generated asteroid entity
func spawn_procedural_asteroid(position, size_category, seed_value, scale_value, rotation_speed, initial_rotation = 0.0):
	# Get asteroid from pool or create new
	var asteroid_instance = get_asteroid_from_pool(size_category)
	if not asteroid_instance:
		return null
	
	# Set position and other properties
	asteroid_instance.global_position = position
	asteroid_instance.setup(size_category, 0, scale_value, rotation_speed, initial_rotation)
	
	# Get procedural texture for this asteroid
	var texture = generate_asteroid_texture(seed_value, size_category)
	
	# Get or create sprite
	var sprite = asteroid_instance.get_node_or_null("Sprite2D")
	if not sprite:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		asteroid_instance.add_child(sprite)
	
	# Set sprite texture and transform
	sprite.texture = texture
	sprite.scale = Vector2(scale_value, scale_value)
	sprite.rotation = initial_rotation
	
	# Make sure the asteroid hasn't been added before
	if asteroid_instance.get_parent():
		asteroid_instance.get_parent().remove_child(asteroid_instance)
	
	# Add to the scene
	get_tree().current_scene.add_child(asteroid_instance)
	
	return asteroid_instance

# Get an asteroid from the appropriate pool or create a new one
func get_asteroid_from_pool(size_category = "medium"):
	# Try to get from the specific size pool first
	if asteroid_pool[size_category].size() > 0:
		var asteroid = asteroid_pool[size_category].pop_back()
		if is_instance_valid(asteroid):
			# Reset the asteroid state before reusing
			asteroid.visible = true
			asteroid.set_process(true)
			
			if asteroid.has_node("Sprite2D"):
				asteroid.get_node("Sprite2D").modulate = Color.WHITE
			
			if asteroid.has_node("HealthComponent"):
				var health_comp = asteroid.get_node("HealthComponent")
				health_comp.current_health = health_comp.max_health
				health_comp.is_invulnerable = false
			
			return asteroid
	
	# Try other size pools if primary pool is empty
	var alternative_pools = ["large", "medium", "small"]
	for alt_size in alternative_pools:
		if alt_size != size_category and asteroid_pool[alt_size].size() > 0:
			var asteroid = asteroid_pool[alt_size].pop_back()
			if is_instance_valid(asteroid):
				asteroid.visible = true
				asteroid.set_process(true)
				asteroid.size_category = size_category  # Update to correct size
				
				# Adjust health based on new size
				if asteroid.has_node("HealthComponent"):
					var health_comp = asteroid.get_node("HealthComponent")
					match size_category:
						"small": health_comp.max_health = 20.0
						"medium": health_comp.max_health = 50.0
						"large": health_comp.max_health = 100.0
					health_comp.current_health = health_comp.max_health
				
				return asteroid
	
	# If no pooled asteroids available, create new
	return _create_new_asteroid_instance()

# Create a new asteroid instance
func _create_new_asteroid_instance():
	if ResourceLoader.exists(asteroid_scene_path):
		var asteroid = load(asteroid_scene_path).instantiate()
		return asteroid
	else:
		push_error("ERROR: Asteroid scene not found at path: " + asteroid_scene_path)
		return null

# Return asteroid to pool instead of destroying
func return_asteroid_to_pool(asteroid):
	if not is_instance_valid(asteroid):
		return
	
	var size_category = asteroid.size_category
	
	# Ensure size_category is valid
	if not size_category in ["large", "medium", "small"]:
		size_category = "medium"  # Default to medium if invalid
	
	# Check if the pool for this size is under the limit
	var total_pool_size = asteroid_pool.large.size() + asteroid_pool.medium.size() + asteroid_pool.small.size()
	if total_pool_size < max_pool_size:
		# Reset the asteroid for pooling
		asteroid.visible = false
		asteroid.set_process(false)
		
		# Remove from scene but don't free
		if asteroid.get_parent():
			asteroid.get_parent().remove_child(asteroid)
		
		# Add to pool based on size
		asteroid_pool[size_category].append(asteroid)
	else:
		# Too many in pool, destroy it
		asteroid.queue_free()

# Return all asteroids to pool when not needed
func _return_all_asteroids_to_pool():
	# Get all active asteroids in the scene
	var existing_asteroids = get_tree().get_nodes_in_group("asteroids")
	
	for asteroid in existing_asteroids:
		return_asteroid_to_pool(asteroid)
	
	# Clear active tracking
	current_active_asteroids.clear()

# Clear existing asteroid instances when redrawing
func clear_asteroid_instances(current_loaded_cells = null):
	# Get all active asteroids in the scene
	var existing_asteroids = get_tree().get_nodes_in_group("asteroids")
	
	# If we have specific loaded cells, only clear asteroids not in those cells
	if current_loaded_cells != null:
		for asteroid in existing_asteroids:
			if is_instance_valid(asteroid):
				# Get the cell position of this asteroid
				var asteroid_cell_x = int(floor(asteroid.global_position.x / grid.cell_size.x))
				var asteroid_cell_y = int(floor(asteroid.global_position.y / grid.cell_size.y))
				var asteroid_cell = Vector2i(asteroid_cell_x, asteroid_cell_y)
				
				# Return to pool if not in a loaded cell
				if not current_loaded_cells.has(asteroid_cell):
					return_asteroid_to_pool(asteroid)
	else:
		# Return all asteroids to pool
		for asteroid in existing_asteroids:
			return_asteroid_to_pool(asteroid)

# Handler for cell loading
func _on_cell_loaded(cell_x, cell_y):
	# Check if this cell contains asteroids
	if cell_x < 0 or cell_y < 0 or cell_y >= grid.cell_contents.size() or cell_x >= grid.cell_contents[cell_y].size():
		return
	
	if grid.cell_contents[cell_y][cell_x] == grid.CellContent.ASTEROID:
		# Force quick drawing of this cell's asteroids
		var loaded_cells = {Vector2i(cell_x, cell_y): true}
		call_deferred("draw_asteroids", null, loaded_cells)

# Handler for cell unloading
func _on_cell_unloaded(cell_x, cell_y):
	# Return asteroids in this cell to the pool
	var cell_key = Vector2i(cell_x, cell_y)
	
	if cell_asteroid_cache.has(cell_key):
		var cached_asteroids = cell_asteroid_cache[cell_key]
		
		for asteroid in cached_asteroids:
			if is_instance_valid(asteroid):
				# Cache keeps the reference, just deactivate the asteroid
				asteroid.visible = false
				asteroid.set_process(false)
				
				# Remove from scene but keep in cache
				if asteroid.get_parent():
					asteroid.get_parent().remove_child(asteroid)
				
				# Remove from active list
				var idx = current_active_asteroids.find(asteroid)
				if idx != -1:
					current_active_asteroids.remove_at(idx)

# BACKWARD COMPATIBILITY: Handles asteroid fragments
# This function is called by the original asteroid.gd script when asteroids are destroyed
func _spawn_fragments(position, size_category, fragment_count=3, base_scale=1.0):
	# Determine the next smaller size category for fragments
	var fragment_size = "small"
	if size_category == "large":
		fragment_size = "medium"
	
	# Get actual size values from the RandomAsteroidGenerator
	var fragment_actual_size = RandomAsteroidGenerator.ASTEROID_SIZE_SMALL
	if fragment_size == "medium":
		fragment_actual_size = RandomAsteroidGenerator.ASTEROID_SIZE_MEDIUM
	
	# Create a random generator
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	# Spawn fragments
	for i in range(fragment_count):
		# Create unique seed for this fragment
		var fragment_seed = int(position.x * 1000) + int(position.y * 1000) + rng.randi() + i * 12345
		
		# Randomize position with offset
		var angle = rng.randf_range(0, TAU)
		var distance = 20 * base_scale
		var offset = Vector2(cos(angle), sin(angle)) * distance
		var fragment_pos = position + offset
		
		# Random scale and rotation
		var fragment_scale = base_scale * rng.randf_range(0.6, 0.9)
		var rot_speed = rng.randf_range(-2.0, 2.0)  # Faster rotation for fragments
		
		# Spawn the procedurally generated fragment
		spawn_procedural_asteroid(
			fragment_pos,
			fragment_size,
			fragment_seed,
			fragment_scale,
			rot_speed,
			rng.randf_range(0, TAU)
		)
