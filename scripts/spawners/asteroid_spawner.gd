# asteroid_spawner.gd
extends Node
class_name AsteroidSpawner

const RandomAsteroidGenerator = preload("res://scripts/generators/asteroid_generator.gd")

# Configuration parameters
@export var asteroid_percentage: int = 30
@export var minimum_asteroids: int = 8
@export var min_asteroids_per_cell: int = 5
@export var max_asteroids_per_cell: int = 10
@export var asteroid_scale_min: float = 0.9
@export var asteroid_scale_max: float = 1.1
@export var cell_margin: float = 0.15
@export var cluster_percentage: int = 60
@export var large_percentage: int = 70
@export var medium_percentage: int = 20

# References and tracking variables
var grid = null
var asteroid_fields = []
var asteroid_data = []
var asteroid_counts = []

# Backward compatibility - maintained for existing code
var large_asteroid_sprites = []
var medium_asteroid_sprites = []
var small_asteroid_sprites = []

# Scene reference and caches
var asteroid_scene_path = "res://scenes/asteroid.tscn"
var asteroid_texture_cache = {}
var texture_cache_size_limit = 250

# Object pooling
var asteroid_pool = {
	"large": [],
	"medium": [],
	"small": []
}
var max_pool_size = 300
var current_active_asteroids = []
var cell_asteroid_cache = {}

func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for asteroid spawning!")
		return
	
	_initialize_pool()
	_initialize_compat_sprites()
	
	if grid.has_signal("_seed_changed"):
		grid.connect("_seed_changed", _on_grid_seed_changed)
	
	if grid.has_signal("_cell_loaded"):
		grid.connect("_cell_loaded", _on_cell_loaded)
	if grid.has_signal("_cell_unloaded"):
		grid.connect("_cell_unloaded", _on_cell_unloaded)

func _initialize_compat_sprites():
	large_asteroid_sprites = [_create_dummy_texture(RandomAsteroidGenerator.ASTEROID_SIZE_LARGE)]
	medium_asteroid_sprites = [_create_dummy_texture(RandomAsteroidGenerator.ASTEROID_SIZE_MEDIUM)]
	small_asteroid_sprites = [_create_dummy_texture(RandomAsteroidGenerator.ASTEROID_SIZE_SMALL)]

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

func generate_asteroids():
	asteroid_fields.clear()
	asteroid_data.clear()
	asteroid_counts = []
	
	if grid.cell_contents.size() == 0:
		return
	
	# Initialize the asteroid counts array
	for y in range(int(grid.grid_size.y)):
		asteroid_counts.append([])
		for x in range(int(grid.grid_size.x)):
			asteroid_counts[y].append(0)
	
	# Get available cells
	var available_cells = []
	for y in range(1, int(grid.grid_size.y) - 1):
		for x in range(1, int(grid.grid_size.x) - 1):
			if grid.is_boundary_cell(x, y) or grid.cell_contents[y][x] != grid.CellContent.EMPTY:
				continue
			available_cells.append(Vector2i(x, y))
	
	# Calculate asteroid count
	var non_boundary_count = available_cells.size()
	var asteroid_count = max(minimum_asteroids, int(non_boundary_count * float(asteroid_percentage) / 100.0))
	asteroid_count = min(asteroid_count, non_boundary_count)
	
	# Setup RNG
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
		
		_generate_asteroids_for_field(x, y, world_pos, rng, min_asteroids_per_cell, cell_margin, 
									large_percentage, medium_percentage, asteroid_scale_min, 
									asteroid_scale_max, cluster_percentage)
		
		if actual_asteroid_count >= asteroid_count:
			break
	
	grid.queue_redraw()

func _generate_asteroids_for_field(grid_x, grid_y, _center_pos, _rng, asteroid_count, 
								cell_margin_value, large_pct, medium_pct,
								scale_min, scale_max, cluster_pct):
	var field_asteroids = []
	
	# Apply cell margins
	var safe_width = grid.cell_size.x * (1.0 - 2 * cell_margin_value)
	var safe_height = grid.cell_size.y * (1.0 - 2 * cell_margin_value)
	var margin_x = grid.cell_size.x * cell_margin_value
	var margin_y = grid.cell_size.y * cell_margin_value
	
	# Calculate size distribution
	var large_count = int(asteroid_count * large_pct / 100.0)
	var medium_count = int(asteroid_count * medium_pct / 100.0)
	var small_count = asteroid_count - large_count - medium_count
	
	var size_distribution = []
	for i in range(large_count): size_distribution.append("large")
	for i in range(medium_count): size_distribution.append("medium")
	for i in range(small_count): size_distribution.append("small")
	
	size_distribution.shuffle()
	
	# Track positions and sizes for overlap prevention
	var placed_asteroids = []
	
	for j in range(asteroid_count):
		# Generate a unique seed for each asteroid
		var asteroid_seed = grid.seed_value + grid_y * 10000 + grid_x * 100 + j
		var asteroid_rng = RandomNumberGenerator.new()
		asteroid_rng.seed = asteroid_seed
		
		# Get size category and pixel size
		var size_category = size_distribution[j]
		var pixel_size = 0
		match size_category:
			"large": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_LARGE
			"medium": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_MEDIUM
			"small": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_SMALL
		
		# Set asteroid properties
		var base_scale = asteroid_rng.randf_range(scale_min, scale_max)
		var rotation = asteroid_rng.randf_range(0, TAU)
		var initial_rotation = asteroid_rng.randf_range(0, TAU)
		var rotation_speed = asteroid_rng.randf_range(-0.8, 0.8)
		
		# Ensure some rotation
		if abs(rotation_speed) < 0.1:
			rotation_speed = 0.1 if rotation_speed >= 0 else -0.1
		
		var collision_radius = pixel_size * 0.5 * base_scale
		
		# Handle clustering
		var in_cluster = asteroid_rng.randf() * 100 < cluster_pct
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
					
					# Place this asteroid near the parent
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
				
				var section_width = safe_width / 10.0
				var section_height = safe_height / 10.0
				
				pos_offset = Vector2(
					margin_x + (cell_x * section_width) + asteroid_rng.randf_range(0, section_width) - grid.cell_size.x / 2.0,
					margin_y + (cell_y * section_height) + asteroid_rng.randf_range(0, section_height) - grid.cell_size.y / 2.0
				)
			
			# Keep within margins
			pos_offset.x = clamp(pos_offset.x, -safe_width/2.0 + collision_radius, safe_width/2.0 - collision_radius)
			pos_offset.y = clamp(pos_offset.y, -safe_height/2.0 + collision_radius, safe_height/2.0 - collision_radius)
			
			# Check for overlap
			valid_position = true
			for existing in placed_asteroids:
				var distance = pos_offset.distance_to(existing.offset)
				if distance < (collision_radius + existing.radius) * 1.05:
					valid_position = false
					break
			
			attempts += 1
			
			# If clustering is causing problems, try without it
			if attempts > max_attempts / 2:
				in_cluster = false
		
		# Try with smaller size if position is invalid
		if !valid_position:
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
		
		# Add asteroid data
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

func generate_asteroid_texture(seed_value: int, size_category: String) -> ImageTexture:
	# Check cache
	var cache_key = str(seed_value) + "_" + size_category
	if asteroid_texture_cache.has(cache_key):
		return asteroid_texture_cache[cache_key]
	
	# Get pixel size
	var pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_MEDIUM
	match size_category:
		"large": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_LARGE
		"medium": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_MEDIUM
		"small": pixel_size = RandomAsteroidGenerator.ASTEROID_SIZE_SMALL
	
	# Create generator
	var generator = RandomAsteroidGenerator.new()
	generator.seed_value = seed_value
	generator.main_rng = RandomNumberGenerator.new()
	generator.main_rng.seed = seed_value
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
	
	# Generate texture
	var texture = generator.create_asteroid_texture()
	
	# Cache texture and manage cache size
	asteroid_texture_cache[cache_key] = texture
	if asteroid_texture_cache.size() > texture_cache_size_limit:
		var oldest_key = asteroid_texture_cache.keys()[0]
		asteroid_texture_cache.erase(oldest_key)
	
	return texture

func reset_asteroids():
	asteroid_texture_cache.clear()
	cell_asteroid_cache.clear()
	_return_all_asteroids_to_pool()
	call_deferred("generate_asteroids")

func _on_grid_seed_changed(_new_seed = null):
	call_deferred("reset_asteroids")

func draw_asteroids(_canvas: CanvasItem, loaded_cells: Dictionary):
	if not grid:
		return
	
	clear_asteroid_instances(loaded_cells)
	current_active_asteroids = []
	
	var player = get_node_or_null("/root/Main/Player")
	var max_draw_distance = 2500
	
	for cell_pos in loaded_cells.keys():
		var x = int(cell_pos.x)
		var y = int(cell_pos.y)
		
		if y >= grid.cell_contents.size() or x >= grid.cell_contents[y].size() or grid.cell_contents[y][x] != grid.CellContent.ASTEROID:
			continue
			
		var cell_center = Vector2(
			x * grid.cell_size.x + grid.cell_size.x / 2.0,
			y * grid.cell_size.y + grid.cell_size.y / 2.0
		)
		
		if player and cell_center.distance_to(player.global_position) > max_draw_distance:
			continue
		
		# Find the asteroid field data
		var field_index = -1
		for i in range(asteroid_fields.size()):
			if asteroid_fields[i].grid_x == x and asteroid_fields[i].grid_y == y:
				field_index = i
				break
		
		if field_index == -1 or field_index >= asteroid_data.size():
			continue
		
		var field_data = asteroid_data[field_index]
		
		# Check for cached asteroids
		var cell_key = Vector2i(x, y)
		if cell_asteroid_cache.has(cell_key):
			var cached_asteroids = cell_asteroid_cache[cell_key]
			
			for asteroid in cached_asteroids:
				if is_instance_valid(asteroid) and !asteroid.is_inside_tree():
					get_tree().current_scene.add_child(asteroid)
				
				if is_instance_valid(asteroid):
					asteroid.visible = true
					asteroid.set_process(true)
					current_active_asteroids.append(asteroid)
		else:
			# Create new asteroids
			var cell_asteroids = []
			
			for asteroid_item in field_data.asteroids:
				var asteroid = spawn_procedural_asteroid(
					cell_center + asteroid_item.offset,
					asteroid_item.size_category,
					asteroid_item.seed,
					asteroid_item.scale,
					asteroid_item.rotation_speed,
					asteroid_item.initial_rotation
				)
				
				if asteroid:
					cell_asteroids.append(asteroid)
					current_active_asteroids.append(asteroid)
			
			cell_asteroid_cache[cell_key] = cell_asteroids

func spawn_procedural_asteroid(position, size_category, seed_value, scale_value, rotation_speed, initial_rotation = 0.0):
	var asteroid_instance = get_asteroid_from_pool(size_category)
	if not asteroid_instance:
		return null
	
	asteroid_instance.global_position = position
	asteroid_instance.setup(size_category, 0, scale_value, rotation_speed, initial_rotation)
	
	var texture = generate_asteroid_texture(seed_value, size_category)
	
	var sprite = asteroid_instance.get_node_or_null("Sprite2D")
	if not sprite:
		sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		asteroid_instance.add_child(sprite)
	
	sprite.texture = texture
	sprite.scale = Vector2(scale_value, scale_value)
	sprite.rotation = initial_rotation
	
	if asteroid_instance.get_parent():
		asteroid_instance.get_parent().remove_child(asteroid_instance)
	
	get_tree().current_scene.add_child(asteroid_instance)
	
	return asteroid_instance

func get_asteroid_from_pool(size_category = "medium"):
	# Try specific size pool
	if asteroid_pool[size_category].size() > 0:
		var asteroid = asteroid_pool[size_category].pop_back()
		if is_instance_valid(asteroid):
			_reset_asteroid_state(asteroid, size_category)
			return asteroid
	
	# Try other size pools
	var alternative_pools = ["large", "medium", "small"]
	for alt_size in alternative_pools:
		if alt_size != size_category and asteroid_pool[alt_size].size() > 0:
			var asteroid = asteroid_pool[alt_size].pop_back()
			if is_instance_valid(asteroid):
				asteroid.size_category = size_category
				_reset_asteroid_state(asteroid, size_category)
				return asteroid
	
	# Create new if no pooled asteroids available
	return _create_new_asteroid_instance()

func _reset_asteroid_state(asteroid, size_category):
	asteroid.visible = true
	asteroid.set_process(true)
	
	if asteroid.has_node("Sprite2D"):
		asteroid.get_node("Sprite2D").modulate = Color.WHITE
	
	if asteroid.has_node("HealthComponent"):
		var health_comp = asteroid.get_node("HealthComponent")
		match size_category:
			"small": health_comp.max_health = 20.0
			"medium": health_comp.max_health = 50.0
			"large": health_comp.max_health = 100.0
		health_comp.current_health = health_comp.max_health
		health_comp.is_invulnerable = false

func _create_new_asteroid_instance():
	if ResourceLoader.exists(asteroid_scene_path):
		return load(asteroid_scene_path).instantiate()
	else:
		push_error("ERROR: Asteroid scene not found at path: " + asteroid_scene_path)
		return null

func return_asteroid_to_pool(asteroid):
	if not is_instance_valid(asteroid):
		return
	
	var size_category = asteroid.size_category
	if not size_category in ["large", "medium", "small"]:
		size_category = "medium"
	
	var total_pool_size = asteroid_pool.large.size() + asteroid_pool.medium.size() + asteroid_pool.small.size()
	if total_pool_size < max_pool_size:
		asteroid.visible = false
		asteroid.set_process(false)
		
		if asteroid.get_parent():
			asteroid.get_parent().remove_child(asteroid)
		
		asteroid_pool[size_category].append(asteroid)
	else:
		asteroid.queue_free()

func _return_all_asteroids_to_pool():
	var existing_asteroids = get_tree().get_nodes_in_group("asteroids")
	
	for asteroid in existing_asteroids:
		return_asteroid_to_pool(asteroid)
	
	current_active_asteroids.clear()

func clear_asteroid_instances(current_loaded_cells = null):
	var existing_asteroids = get_tree().get_nodes_in_group("asteroids")
	
	if current_loaded_cells != null:
		for asteroid in existing_asteroids:
			if is_instance_valid(asteroid):
				var asteroid_cell_x = int(floor(asteroid.global_position.x / grid.cell_size.x))
				var asteroid_cell_y = int(floor(asteroid.global_position.y / grid.cell_size.y))
				var asteroid_cell = Vector2i(asteroid_cell_x, asteroid_cell_y)
				
				if not current_loaded_cells.has(asteroid_cell):
					return_asteroid_to_pool(asteroid)
	else:
		for asteroid in existing_asteroids:
			return_asteroid_to_pool(asteroid)

func _on_cell_loaded(cell_x, cell_y):
	if cell_x < 0 or cell_y < 0 or cell_y >= grid.cell_contents.size() or cell_x >= grid.cell_contents[cell_y].size():
		return
	
	if grid.cell_contents[cell_y][cell_x] == grid.CellContent.ASTEROID:
		var loaded_cells = {Vector2i(cell_x, cell_y): true}
		call_deferred("draw_asteroids", null, loaded_cells)

func _on_cell_unloaded(cell_x, cell_y):
	var cell_key = Vector2i(cell_x, cell_y)
	
	if cell_asteroid_cache.has(cell_key):
		var cached_asteroids = cell_asteroid_cache[cell_key]
		
		for asteroid in cached_asteroids:
			if is_instance_valid(asteroid):
				asteroid.visible = false
				asteroid.set_process(false)
				
				if asteroid.get_parent():
					asteroid.get_parent().remove_child(asteroid)
				
				var idx = current_active_asteroids.find(asteroid)
				if idx != -1:
					current_active_asteroids.remove_at(idx)

func _spawn_fragments(position, size_category, _fragment_count=3, base_scale=1.0):
	if size_category == "small":
		return
	
	var rng = RandomNumberGenerator.new()
	rng.randomize()
	
	var fragments = []
	
	if size_category == "large":
		if rng.randf() < 0.5:
			fragments = [
				{"size": "medium", "scale": base_scale * rng.randf_range(0.7, 0.9)},
				{"size": "medium", "scale": base_scale * rng.randf_range(0.7, 0.9)}
			]
		else:
			fragments = [
				{"size": "medium", "scale": base_scale * rng.randf_range(0.7, 0.9)},
				{"size": "small", "scale": base_scale * rng.randf_range(0.5, 0.7)}
			]
	else: # medium asteroid
		if rng.randf() < 0.6:
			fragments = [
				{"size": "small", "scale": base_scale * rng.randf_range(0.6, 0.8)},
				{"size": "small", "scale": base_scale * rng.randf_range(0.6, 0.8)}
			]
		else:
			fragments = [
				{"size": "small", "scale": base_scale * rng.randf_range(0.6, 0.8)}
			]
	
	for fragment in fragments:
		var fragment_seed = int(position.x * 1000) + int(position.y * 1000) + rng.randi()
		var angle = rng.randf_range(0, TAU)
		var distance = 20 * base_scale
		var offset = Vector2(cos(angle), sin(angle)) * distance
		var fragment_pos = position + offset
		var rot_speed = rng.randf_range(-2.0, 2.0)
		
		spawn_procedural_asteroid(
			fragment_pos,
			fragment.size,
			fragment_seed,
			fragment.scale,
			rot_speed,
			rng.randf_range(0, TAU)
		)
