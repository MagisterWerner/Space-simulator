extends Node2D
class_name AsyncAsteroidSpawner

# Signals
signal asteroid_ready(asteroid_node)
signal generation_started
signal generation_failed(error)

# Generation parameters
@export var auto_generate: bool = true
@export var asteroid_seed: int = 0
@export var asteroid_size: int = 32  # Default to medium size
@export var use_loading_texture: bool = true
@export var loading_color: Color = Color(0.3, 0.3, 0.3, 1.0)

# Node references
var asteroid_sprite: Sprite2D
var loading_sprite: Sprite2D
var generator_component: AsyncGeneratorComponent

# State tracking
var is_asteroid_ready: bool = false
var actual_size: int = 0

# Size presets
const SIZE_SMALL = 16
const SIZE_MEDIUM = 32
const SIZE_LARGE = 64

func _ready():
	# Create component for async generation
	generator_component = AsyncGeneratorComponent.new()
	generator_component.name = "AsyncGenerator"
	add_child(generator_component)
	
	# Connect signals
	generator_component.generation_completed.connect(_on_generation_completed)
	generator_component.generation_failed.connect(_on_generation_failed)
	
	# Create basic structure
	asteroid_sprite = Sprite2D.new()
	asteroid_sprite.name = "AsteroidSprite"
	add_child(asteroid_sprite)
	
	# Create loading sprite
	if use_loading_texture:
		loading_sprite = Sprite2D.new()
		loading_sprite.name = "LoadingSprite"
		add_child(loading_sprite)
		_create_loading_texture()
	
	# Auto-generate if set
	if auto_generate:
		generate_asteroid()

# Start asteroid generation
func generate_asteroid(seed_value = null, size = null):
	# Use provided seed or default
	if seed_value != null:
		asteroid_seed = seed_value
	
	# Use provided size or default
	if size != null:
		asteroid_size = size
	
	# Reset state
	is_asteroid_ready = false
	
	# Check for SeedManager integration
	if has_node("/root/SeedManager") and SeedManager.is_initialized:
		# Get reproducible seed based on object ID
		var object_id = get_instance_id()
		if seed_value != null:
			object_id = seed_value
		
		# Get deterministic seed for this asteroid
		asteroid_seed = SeedManager.get_random_int(object_id, 0, 9999999)
	
	# Show loading sprite
	if loading_sprite:
		loading_sprite.visible = true
		asteroid_sprite.visible = false
	
	# Request asteroid texture generation
	emit_signal("generation_started")
	generator_component.request_asteroid(asteroid_seed, asteroid_size)

# Handle completion of asteroid generation
func _on_generation_completed(result):
	if not is_instance_valid(self):
		return
	
	# Set asteroid texture
	if is_instance_valid(asteroid_sprite) and result is Texture2D:
		asteroid_sprite.texture = result
		asteroid_sprite.visible = true
		
		# Store the actual size (might be different from requested due to randomization)
		actual_size = result.get_width()
		
		# Hide loading sprite
		if loading_sprite:
			loading_sprite.visible = false
		
		# Done with generation
		_finalize_asteroid()

# Handle generation failures
func _on_generation_failed(error):
	push_error("Asteroid generation failed: " + str(error))
	emit_signal("generation_failed", error)
	
	# Try to create a simple fallback asteroid
	var fallback = _create_fallback_asteroid()
	if fallback:
		if loading_sprite:
			loading_sprite.visible = false
		asteroid_sprite.visible = true
		_finalize_asteroid()

# Create a simple fallback asteroid if generation fails
func _create_fallback_asteroid():
	var size = asteroid_size
	var image = Image.create(size, size, true, Image.FORMAT_RGBA8)
	
	# Draw a simple irregular shape
	var center_x = size / 2
	var center_y = size / 2
	var radius = size / 2 - 2
	
	for y in range(size):
		for x in range(size):
			var dx = x - center_x
			var dy = y - center_y
			var dist = sqrt(dx*dx + dy*dy)
			
			# Create irregular shape
			var rng = RandomNumberGenerator.new()
			rng.seed = asteroid_seed + x * 10 + y
			var noise = rng.randf_range(0.8, 1.2)
			
			if dist <= radius * noise:
				# Gray scale with some variation
				var brightness = rng.randf_range(0.2, 0.4)
				var color = Color(brightness, brightness, brightness)
				image.set_pixel(x, y, color)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	var texture = ImageTexture.create_from_image(image)
	asteroid_sprite.texture = texture
	return texture

# Create a loading placeholder texture
func _create_loading_texture():
	var size = min(64, asteroid_size)
	var image = Image.create(size, size, true, Image.FORMAT_RGBA8)
	
	# Draw a simple placeholder shape
	for y in range(size):
		for x in range(size):
			var dx = x - size/2
			var dy = y - size/2
			var dist = sqrt(dx*dx + dy*dy)
			
			if dist <= size/2:
				# Checkerboard pattern
				var checker = (int(x / 4) + int(y / 4)) % 2 == 0
				var color = loading_color if checker else loading_color.lightened(0.2)
				image.set_pixel(x, y, color)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	var texture = ImageTexture.create_from_image(image)
	loading_sprite.texture = texture

# Finalize asteroid setup
func _finalize_asteroid():
	is_asteroid_ready = true
	asteroid_ready.emit(self)

# Get asteroid size (small, medium, large)
func get_size_category():
	if actual_size <= SIZE_SMALL + 4:
		return "Small"
	elif actual_size >= SIZE_LARGE - 4:
		return "Large"
	else:
		return "Medium"

# Cancel any in-progress generation
func cancel_generation():
	if generator_component:
		generator_component.cancel_request()
	
	if loading_sprite:
		loading_sprite.visible = false
