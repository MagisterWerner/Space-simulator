extends Node2D
class_name AsyncPlanetSpawner

# Signals
signal planet_ready(planet_node)
signal generation_started
signal generation_failed(error)

# Generation parameters
@export var auto_generate: bool = true
@export var planet_seed: int = 0
@export var is_gaseous: bool = false
@export var theme_override: int = -1
@export var generate_atmosphere: bool = true
@export var use_loading_texture: bool = true
@export var loading_color: Color = Color(0.3, 0.3, 0.3, 1.0)

# Node references
var planet_sprite: Sprite2D
var atmosphere_sprite: Sprite2D
var loading_sprite: Sprite2D
var generator_component: AsyncGeneratorComponent

# State tracking
var planet_size: int = 0
var is_planet_ready: bool = false
var planet_theme: int = -1
var generation_step: int = 0  # 0=not started, 1=planet, 2=atmosphere

func _ready():
	# Create component for async generation
	generator_component = AsyncGeneratorComponent.new()
	generator_component.name = "AsyncGenerator"
	add_child(generator_component)
	
	# Connect signals
	generator_component.generation_completed.connect(_on_generation_completed)
	generator_component.generation_failed.connect(_on_generation_failed)
	
	# Create basic structure
	planet_sprite = Sprite2D.new()
	planet_sprite.name = "PlanetSprite"
	add_child(planet_sprite)
	
	atmosphere_sprite = Sprite2D.new()
	atmosphere_sprite.name = "AtmosphereSprite"
	atmosphere_sprite.z_index = -1  # Behind planet
	add_child(atmosphere_sprite)
	
	# Create loading sprite
	if use_loading_texture:
		loading_sprite = Sprite2D.new()
		loading_sprite.name = "LoadingSprite"
		add_child(loading_sprite)
		_create_loading_texture()
	
	# Auto-generate if set
	if auto_generate:
		generate_planet()

# Start planet generation
func generate_planet(seed_value = null):
	# Use provided seed or default
	if seed_value != null:
		planet_seed = seed_value
	
	# Reset state
	is_planet_ready = false
	generation_step = 1
	
	# Check for SeedManager integration
	if has_node("/root/SeedManager") and SeedManager.is_initialized:
		# Get reproducible seed based on object ID
		var object_id = get_instance_id()
		if seed_value != null:
			object_id = seed_value
		
		# Get deterministic seed for this planet
		planet_seed = SeedManager.get_random_int(object_id, 0, 9999999)
	
	# Show loading sprite
	if loading_sprite:
		loading_sprite.visible = true
		planet_sprite.visible = false
		atmosphere_sprite.visible = false
	
	# Request planet texture generation
	emit_signal("generation_started")
	generator_component.request_planet(planet_seed, is_gaseous, theme_override)

# Handle completion of planet generation
func _on_generation_completed(result):
	if not is_instance_valid(self):
		return
	
	# This could be either the planet or atmosphere
	if generation_step == 1 and result is Array and result.size() >= 3:
		# This is the planet texture result
		var planet_texture = result[0]
		var atmosphere_texture = result[1]
		planet_size = result[2]
		
		# Set planet texture
		if is_instance_valid(planet_sprite) and planet_texture:
			planet_sprite.texture = planet_texture
			planet_sprite.visible = true
			
			# Determine theme if needed
			if theme_override >= 0:
				planet_theme = theme_override
			else:
				# Use the result's theme or figure it out based on appearance
				if result.size() >= 4:
					planet_theme = result[3]
				else:
					# Try to guess theme based on is_gaseous
					var base_theme = PlanetGeneratorBase.PlanetTheme.ARID  # Default
					if is_gaseous:
						base_theme = PlanetGeneratorBase.PlanetTheme.JUPITER
					planet_theme = base_theme
		
		# Request atmosphere if needed
		if generate_atmosphere and planet_theme >= 0:
			generation_step = 2
			generator_component.request_atmosphere(planet_theme, planet_seed, planet_size)
		else:
			# No atmosphere needed
			if loading_sprite:
				loading_sprite.visible = false
			
			# Done with generation
			_finalize_planet()
			
	elif generation_step == 2 and (result is ImageTexture or result is Texture2D):
		# This is the atmosphere texture
		if is_instance_valid(atmosphere_sprite):
			atmosphere_sprite.texture = result
			atmosphere_sprite.visible = true
			
			# Center the atmosphere
			if planet_size > 0:
				var atmosphere_size = result.get_width()
				var offset = (atmosphere_size - planet_size) / 2.0
				atmosphere_sprite.position = Vector2(-offset, -offset)
		
		# Hide loading sprite
		if loading_sprite:
			loading_sprite.visible = false
		
		# Done with generation
		_finalize_planet()

# Handle generation failures
func _on_generation_failed(error):
	push_error("Planet generation failed: " + str(error))
	emit_signal("generation_failed", error)
	
	# Try to create a simple fallback planet
	var fallback = _create_fallback_planet()
	if fallback:
		if loading_sprite:
			loading_sprite.visible = false
		planet_sprite.visible = true
		_finalize_planet()

# Create a simple fallback planet if generation fails
func _create_fallback_planet():
	var planet_size = 256
	var image = Image.create(planet_size, planet_size, true, Image.FORMAT_RGBA8)
	
	# Draw a simple circle
	for y in range(planet_size):
		for x in range(planet_size):
			var dx = x - planet_size/2
			var dy = y - planet_size/2
			var dist = sqrt(dx*dx + dy*dy)
			
			if dist <= planet_size/2:
				# Simple color based on is_gaseous
				var color = Color(0.2, 0.5, 0.8) if is_gaseous else Color(0.5, 0.3, 0.2)
				image.set_pixel(x, y, color)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	var texture = ImageTexture.create_from_image(image)
	planet_sprite.texture = texture
	return texture

# Create a loading placeholder texture
func _create_loading_texture():
	var size = 128
	var image = Image.create(size, size, true, Image.FORMAT_RGBA8)
	
	# Draw a simple placeholder circle
	for y in range(size):
		for x in range(size):
			var dx = x - size/2
			var dy = y - size/2
			var dist = sqrt(dx*dx + dy*dy)
			
			if dist <= size/2:
				# Checkerboard pattern
				var checker = (int(x / 8) + int(y / 8)) % 2 == 0
				var color = loading_color if checker else loading_color.lightened(0.2)
				image.set_pixel(x, y, color)
			else:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
	
	var texture = ImageTexture.create_from_image(image)
	loading_sprite.texture = texture

# Finalize planet setup
func _finalize_planet():
	is_planet_ready = true
	planet_ready.emit(self)

# Get planet type name
func get_planet_type_name():
	if planet_theme >= 0:
		return PlanetGeneratorBase.get_theme_name(planet_theme)
	return "Unknown"

# Get planet diameter in game units
func get_planet_diameter():
	return planet_size

# Cancel any in-progress generation
func cancel_generation():
	if generator_component:
		generator_component.cancel_request()
	
	if loading_sprite:
		loading_sprite.visible = false
