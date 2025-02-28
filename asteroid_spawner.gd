extends Node
class_name AsteroidSpawner

# Asteroid generation parameters
@export var asteroid_percentage = 15  # Restored to original value
@export var minimum_asteroids = 8     # Minimum number of asteroid fields to generate
@export var min_asteroids_per_cell = 2  # Restored to original
@export var max_asteroids_per_cell = 15  # Restored to original
@export var asteroid_scale_min = 0.5    # Minimum scale for asteroid sprites
@export var asteroid_scale_max = 1.2    # Maximum scale for asteroid sprites
@export var cell_margin = 0.15        # Margin from cell edges (as percentage of cell size)
@export var cluster_percentage = 60   # Percentage of asteroids that form clusters

# Reference to the grid
var grid = null

# Array to track asteroids
var asteroid_fields = []  # Stores positions of asteroid fields
var asteroid_data = []    # Stores additional data like count, sizes, etc.

# 2D array to store number of asteroids per cell
var asteroid_counts = []

# Arrays to store asteroid sprites by size category
var large_asteroid_sprites = []
var medium_asteroid_sprites = []
var small_asteroid_sprites = []

# Asteroid scene reference
var asteroid_scene_path = "res://scenes/asteroid.tscn"

# Asteroid pooling
var asteroid_pool = []
var max_pool_size = 300
var current_active_asteroids = []

func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for asteroid spawning!")
		return
	
	# Connect to grid seed change signal if available
	if grid.has_signal("_seed_changed"):
		grid.connect("_seed_changed", _on_grid_seed_changed)
	
	# Load asteroid sprites
	load_asteroid_sprites()

# Function to load asteroid sprites
func load_asteroid_sprites():
	# Clear existing sprites
	large_asteroid_sprites.clear()
	medium_asteroid_sprites.clear()
	small_asteroid_sprites.clear()
	
	# Load large asteroid sprites
	for i in range(1, 6):  # 1 to 5
		var path = "res://sprites/asteroids/asteroid_large_" + str(i) + ".png"
		if ResourceLoader.exists(path):
			var texture = load(path)
			if texture:
				large_asteroid_sprites.append(texture)
	
	# Load medium asteroid sprites
	for i in range(1, 6):  # 1 to 5
		var path = "res://sprites/asteroids/asteroid_medium_" + str(i) + ".png"
		if ResourceLoader.exists(path):
			var texture = load(path)
			if texture:
				medium_asteroid_sprites.append(texture)
	
	# Load small asteroid sprites
	for i in range(1, 6):  # 1 to 5
		var path = "res://sprites/asteroids/asteroid_small_" + str(i) + ".png"
		if ResourceLoader.exists(path):
			var texture = load(path)
			if texture:
				small_asteroid_sprites.append(texture)
	
	# Create fallbacks if needed
	if large_asteroid_sprites.size() == 0:
		create_fallback_asteroid_texture("large")
	if medium_asteroid_sprites.size() == 0:
		create_fallback_asteroid_texture("medium")
	if small_asteroid_sprites.size() == 0:
		create_fallback_asteroid_texture("small")

# Create fallback asteroid textures
func create_fallback_asteroid_texture(size_category: String):
	var texture_size = 48
	if size_category == "medium":
		texture_size = 32
	elif size_category == "small":
		texture_size = 16
	
	var image = Image.create(texture_size, texture_size, false, Image.FORMAT_RGBA8)
	var radius = float(texture_size) / 2.0 - 2.0  # Convert to float for precise radius
	
	for x in range(texture_size):
		for y in range(texture_size):
			var dist = Vector2(x - texture_size/2.0, y - texture_size/2.0).length()  # Using floats for division
			if dist < radius:
				image.set_pixel(x, y, Color(0.7, 0.3, 0, 1))  # Brownish color for asteroids
	
	var fallback_texture = ImageTexture.create_from_image(image)
	
	# Add to appropriate array
	if size_category == "large":
		large_asteroid_sprites.append(fallback_texture)
	elif size_category == "medium":
		medium_asteroid_sprites.append(fallback_texture)
	elif size_category == "small":
		small_asteroid_sprites.append(fallback_texture)

# Function to generate asteroids in grid cells
func generate_asteroids():
	# Clear existing asteroid data
	asteroid_fields.clear()
	asteroid_data.clear()
	
	# Initialize asteroid counts array
	asteroid_counts = []
	
	# Make sure grid is ready
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
			# Skip boundary cells
			if grid.is_boundary_cell(x, y):
				continue
			
			# Skip if already has content
			if grid.cell_contents[y][x] != grid.CellContent.EMPTY:
				continue
			
			# Add valid cells
			available_cells.append(Vector2i(x, y))
	
	# Determine how many asteroid fields to spawn
	var non_boundary_count = available_cells.size()
	var asteroid_count = max(minimum_asteroids, int(non_boundary_count * float(asteroid_percentage) / 100.0))  # Using floats for division
	asteroid_count = min(asteroid_count, non_boundary_count)  # Cap at available cells
	
	# Setup RNG with the grid's seed
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value + 1000  # Add offset to get different pattern from planets
	
	var actual_asteroid_count = 0
	
	# Generate asteroid fields
	for i in range(asteroid_count * 2):
		if available_cells.size() == 0:
			break  # No more available cells
		
		# Choose a random available cell
		var idx = rng.randi() % available_cells.size()
		var asteroid_pos = available_cells[idx]
		var x = asteroid_pos.x
		var y = asteroid_pos.y
		
		# Remove this cell from available cells
		available_cells.remove_at(idx)
		
		# Set cell as asteroid in the grid
		grid.cell_contents[y][x] = grid.CellContent.ASTEROID
		actual_asteroid_count += 1
		
		# Generate random number of asteroids for this cell
		var num_asteroids = rng.randi_range(min_asteroids_per_cell, max_asteroids_per_cell)
		asteroid_counts[y][x] = num_asteroids
		
		# Store asteroid field position and data
		var world_pos = Vector2(
			x * grid.cell_size.x + grid.cell_size.x / 2,
			y * grid.cell_size.y + grid.cell_size.y / 2
		)
		
		asteroid_fields.append({
			"position": world_pos,
			"grid_x": x,
			"grid_y": y
		})
		
		# Store asteroid details for each asteroid in the field
		var field_asteroids = []
		# Track positions and sizes for overlap detection
		var placed_asteroids = []
		
		# Apply cell margins for this field
		var safe_width = grid.cell_size.x * (1.0 - 2 * cell_margin)
		var safe_height = grid.cell_size.y * (1.0 - 2 * cell_margin)
		var margin_x = grid.cell_size.x * cell_margin
		var margin_y = grid.cell_size.y * cell_margin
		
		for j in range(num_asteroids):
			# Generate a unique seed for each asteroid
			var asteroid_seed = grid.seed_value + y * 1000 + x + j
			var asteroid_rng = RandomNumberGenerator.new()
			asteroid_rng.seed = asteroid_seed
			
			# Determine asteroid size category
			# Adjusted to 40% small, 30% medium, 30% large
			var size_category = "small"
			var size_roll = asteroid_rng.randf() * 100
			if size_roll < 30:
				size_category = "large"
			elif size_roll < 60:
				size_category = "medium"
			
			# Select appropriate sprite array
			var sprite_array = []
			match size_category:
				"large":
					sprite_array = large_asteroid_sprites
				"medium":
					sprite_array = medium_asteroid_sprites
				"small":
					sprite_array = small_asteroid_sprites
			
			# Select a random sprite variant
			var sprite_variant = 0
			if sprite_array.size() > 0:
				sprite_variant = asteroid_rng.randi() % sprite_array.size()
			
			# Scale variation based on size category
			var base_scale = 1.0
			match size_category:
				"large":
					base_scale = asteroid_rng.randf_range(asteroid_scale_min, asteroid_scale_max * 0.9)
				"medium":
					base_scale = asteroid_rng.randf_range(asteroid_scale_min, asteroid_scale_max * 0.95)
				"small":
					base_scale = asteroid_rng.randf_range(asteroid_scale_min, asteroid_scale_max)
			
			# Random rotation angle
			var rotation = asteroid_rng.randf_range(0, TAU)  # 0 to 2π
			
			# Random initial rotation angle for the sprite
			var initial_rotation = asteroid_rng.randf_range(0, TAU)
			
			# Random rotation speed - MUCH LARGER range for clearly visible rotation
			var rotation_speed = asteroid_rng.randf_range(-1.0, 1.0)
			
			# Make sure ALL asteroids rotate at least a little bit
			if abs(rotation_speed) < 0.2:
				rotation_speed = 0.2 if rotation_speed >= 0 else -0.2
			
			# Estimate collision radius for this asteroid
			var collision_radius = 0
			if sprite_array.size() > 0 and sprite_variant < sprite_array.size():
				var texture = sprite_array[sprite_variant]
				var texture_size = texture.get_size()
				collision_radius = max(texture_size.x, texture_size.y) * base_scale * 0.5
			else:
				# Fallback collision radius based on size category
				match size_category:
					"large":
						collision_radius = 20.0 * base_scale
					"medium":
						collision_radius = 15.0 * base_scale
					"small":
						collision_radius = 10.0 * base_scale
			
			# Determine if this asteroid should be part of a cluster
			var in_cluster = asteroid_rng.randf() * 100 < cluster_percentage
			var pos_offset = Vector2.ZERO
			var valid_position = false
			var attempts = 0
			var max_attempts = 10  # Maximum attempts to find a non-overlapping position
			
			while !valid_position and attempts < max_attempts:
				if in_cluster && j > 0:  # Only cluster if not the first asteroid
					# Select a random existing asteroid to cluster around
					var parent_idx = asteroid_rng.randi() % j
					if parent_idx < field_asteroids.size():
						var parent_offset = field_asteroids[parent_idx].offset
						
						# Place this asteroid near the parent, but with some randomness
						var cluster_radius = min(safe_width, safe_height) * 0.25  # Increased radius for better spacing
						var angle = asteroid_rng.randf_range(0, TAU)
						var distance = asteroid_rng.randf_range(collision_radius * 1.1, cluster_radius)  # Minimum distance to avoid overlap
						
						pos_offset = parent_offset + Vector2(
							cos(angle) * distance,
							sin(angle) * distance
						)
				else:
					# For non-clustered asteroids or the first asteroid in a cell, use quadrant-based positioning
					var quadrant_x = asteroid_rng.randi() % 4  # 0-3
					var quadrant_y = asteroid_rng.randi() % 4  # 0-3
					
					# Calculate position within the chosen quadrant, respecting margins
					var quad_width = safe_width / 4.0
					var quad_height = safe_height / 4.0
					
					pos_offset = Vector2(
						margin_x + (quadrant_x * quad_width) + asteroid_rng.randf_range(0, quad_width) - grid.cell_size.x / 2.0,
						margin_y + (quadrant_y * quad_height) + asteroid_rng.randf_range(0, quad_height) - grid.cell_size.y / 2.0
					)
				
				# Make sure the asteroid stays within margins
				pos_offset.x = clamp(pos_offset.x, -safe_width/2.0 + collision_radius, safe_width/2.0 - collision_radius)
				pos_offset.y = clamp(pos_offset.y, -safe_height/2.0 + collision_radius, safe_height/2.0 - collision_radius)
				
				# Check for overlap with existing asteroids
				valid_position = true
				for existing in placed_asteroids:
					var distance = pos_offset.distance_to(existing.offset)
					if distance < (collision_radius + existing.radius):
						valid_position = false
						break
				
				attempts += 1
				
				# If clustering is causing problems, try without clustering on later attempts
				if attempts > max_attempts / 2:
					in_cluster = false
			
			# Skip this asteroid if we couldn't find a valid position
			if !valid_position:
				continue
			
			# Track this asteroid for future collision detection
			placed_asteroids.append({
				"offset": pos_offset,
				"radius": collision_radius
			})
			
			# Add asteroid data
			field_asteroids.append({
				"size_category": size_category,
				"sprite_variant": sprite_variant,
				"scale": base_scale,
				"offset": pos_offset,
				"rotation": rotation,
				"rotation_speed": rotation_speed,
				"initial_rotation": initial_rotation,  # Added initial rotation for the sprite
				"seed": asteroid_seed
			})
		
		asteroid_data.append({
			"count": field_asteroids.size(),  # Update count to match actual placed asteroids
			"asteroids": field_asteroids
		})
		
		# Stop if we've placed enough asteroid fields
		if actual_asteroid_count >= asteroid_count:
			break
	
	# Force grid redraw
	grid.queue_redraw()

# Function to reset asteroids (used when seed changes)
func reset_asteroids():
	call_deferred("generate_asteroids")

# Handler for grid seed change
func _on_grid_seed_changed(_new_seed = null):
	call_deferred("generate_asteroids")

# Method to draw asteroids using sprites and instantiating actual asteroid entities
func draw_asteroids(_canvas: CanvasItem, loaded_cells: Dictionary):
	if not grid:
		return
	
	# Clear existing asteroid instances first
	clear_asteroid_instances()
	
	# Reset track of active asteroids
	current_active_asteroids = []
	
	# Get player for distance culling - still keep moderate culling for performance
	var player = get_node_or_null("/root/Main/Player")
	var max_draw_distance = 2000  # Increased draw distance
	
	# For each loaded cell
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
			
			# Draw each asteroid in the field
			for asteroid_item in field_data.asteroids:
				# Get the appropriate sprite array based on size category
				var sprite_array = []
				match asteroid_item.size_category:
					"large":
						sprite_array = large_asteroid_sprites
					"medium":
						sprite_array = medium_asteroid_sprites
					"small":
						sprite_array = small_asteroid_sprites
				
				# Skip if no sprites available or invalid variant
				if sprite_array.size() == 0 or asteroid_item.sprite_variant >= sprite_array.size():
					continue
				
				# Get the sprite texture
				var texture = sprite_array[asteroid_item.sprite_variant]
				
				# Instead of drawing directly, instantiate an actual asteroid entity
				var asteroid = spawn_asteroid_entity(
					cell_center + asteroid_item.offset,  # position
					asteroid_item.size_category,         # size category
					asteroid_item.sprite_variant,        # sprite variant
					asteroid_item.scale,                 # scale
					asteroid_item.rotation_speed,        # rotation speed
					texture,                             # texture
					asteroid_item.initial_rotation       # initial rotation
				)
				
				# Track this asteroid as active
				if asteroid:
					current_active_asteroids.append(asteroid)

# Get an asteroid from the pool or create a new one
func get_asteroid_from_pool():
	# Try to get from pool first
	while asteroid_pool.size() > 0:
		var asteroid = asteroid_pool.pop_back()
		if is_instance_valid(asteroid):
			# Reset the asteroid state before reusing
			asteroid.visible = true
			asteroid.set_process(true)  # Make sure processing is enabled
			
			if asteroid.has_node("Sprite2D"):
				asteroid.get_node("Sprite2D").modulate = Color.WHITE
				# Don't reset rotation here - let setup handle it
			
			if asteroid.has_node("HealthComponent"):
				var health_comp = asteroid.get_node("HealthComponent")
				health_comp.current_health = health_comp.max_health
				health_comp.is_invulnerable = false
			
			return asteroid
	
	# If pool empty, create new
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
		
	if asteroid_pool.size() < max_pool_size:
		# Reset the asteroid for pooling
		asteroid.visible = false
		asteroid.set_process(false)  # Disable processing while in pool
		
		# Remove from scene but don't free
		if asteroid.get_parent():
			asteroid.get_parent().remove_child(asteroid)
			
		# Add to pool
		asteroid_pool.append(asteroid)
	else:
		# Too many in pool, destroy it
		asteroid.queue_free()

# Method to spawn an actual asteroid entity
func spawn_asteroid_entity(position, size_category, sprite_variant, scale_value, rotation_speed, texture, initial_rotation = 0.0):
	# Get asteroid from pool or create new
	var asteroid_instance = get_asteroid_from_pool()
	if not asteroid_instance:
		return null
		
	# Set position and other properties
	asteroid_instance.global_position = position
	asteroid_instance.setup(size_category, sprite_variant, scale_value, rotation_speed, initial_rotation)
	
	# Get or create sprite
	var sprite = asteroid_instance.get_node_or_null("Sprite2D")
	if not sprite:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		asteroid_instance.add_child(sprite)
	
	# Set sprite texture and transform
	sprite.texture = texture
	sprite.scale = Vector2(scale_value, scale_value)
	sprite.rotation = initial_rotation  # Set initial rotation from seed
	
	# Make sure the asteroid hasn't been added before
	if asteroid_instance.get_parent():
		asteroid_instance.get_parent().remove_child(asteroid_instance)
	
	# Add to the scene
	get_tree().current_scene.add_child(asteroid_instance)
	
	return asteroid_instance

# Clear existing asteroid instances when redrawing
func clear_asteroid_instances():
	# Get all active asteroids in the scene
	var existing_asteroids = get_tree().get_nodes_in_group("asteroids")
	
	# Return all asteroids to pool that aren't in current_active_asteroids
	for asteroid in existing_asteroids:
		if not asteroid in current_active_asteroids:
			return_asteroid_to_pool(asteroid)

# Draw fallback method for asteroids when needed
func draw_fallback_asteroid(canvas, position, size_category, scale, rotation, seed_value):
	var base_size = 10.0
	
	match size_category:
		"large": base_size = 20.0
		"medium": base_size = 15.0
		"small": base_size = 10.0
	
	# Scale the base size
	var size = base_size * scale
	
	# Create a simple asteroid shape (polygon)
	var points = []
	var sides = 5 + (seed_value % 3)  # 5-7 sides
	
	# Create the shape with some irregularity
	var asteroid_rng = RandomNumberGenerator.new()
	asteroid_rng.seed = seed_value
	
	for i in range(sides):
		var angle = TAU * i / float(sides)  # Use float for division
		var radius = size * asteroid_rng.randf_range(0.8, 1.2)
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius))
	
	# Draw the asteroid
	var transformed_points = []
	for point in points:
		var rotated_point = point.rotated(rotation)
		transformed_points.append(position + rotated_point)
	
	# Fill and outline
	canvas.draw_colored_polygon(transformed_points, Color(0.7, 0.3, 0))
	canvas.draw_polyline(transformed_points + [transformed_points[0]], Color(0.9, 0.4, 0), 2.0, true)
