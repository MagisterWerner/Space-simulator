# scripts/world/world_creation.gd
# Main script for procedural world generation that integrates with the main game scene
extends Node2D

# Reference to world generator
var world_generator: WorldGenerator = null

# Track state to prevent multiple initializations
var _initialization_in_progress: bool = false
var _world_generation_requested: bool = false
var _specific_planet_generation_requested: bool = false

func _ready():
	# Initialize the world generator with proper timing to ensure scene is ready
	call_deferred("_init_world_generator")

func _exit_tree() -> void:
	# Perform cleanup when node exits the tree
	if world_generator != null and is_instance_valid(world_generator):
		world_generator.queue_free()
		world_generator = null

func _init_world_generator() -> void:
	# Guard against double initialization
	if _initialization_in_progress or world_generator != null:
		return
	
	_initialization_in_progress = true
	
	# Wait until after a frame to make sure the scene is fully loaded
	await get_tree().process_frame
	
	# Create world generator
	var generator = WorldGenerator.new()
	generator.name = "WorldGenerator"
	generator.default_grid_size = 5  # Match the grid_size in Main scene
	generator.default_cell_size = 1024
	generator.debug_mode = true
	add_child(generator)
	
	# Store reference AFTER it's added to the scene tree
	world_generator = generator
	
	# Connect to signals with error checking
	if world_generator.has_signal("world_generation_completed"):
		if not world_generator.is_connected("world_generation_completed", _on_world_generated):
			world_generator.connect("world_generation_completed", _on_world_generated)
	
	if world_generator.has_signal("dependencies_found"):
		if not world_generator.is_connected("dependencies_found", _on_dependencies_found):
			world_generator.connect("dependencies_found", _on_dependencies_found)
	
	print("WorldGenerator created, waiting for dependencies...")
	_initialization_in_progress = false
	
	# If generation was requested before initialization completed, do it now
	if _world_generation_requested:
		_generate_world()

func _on_dependencies_found() -> void:
	# Now that we have confirmed our dependencies are initialized, 
	# we can safely start world generation
	print("WorldGenerator dependencies found, starting generation...")
	_generate_world()

func _generate_world() -> void:
	# Check if we have a valid world generator
	if world_generator == null or not is_instance_valid(world_generator):
		print("WorldCreation: Can't generate world - invalid generator reference. Retrying initialization...")
		_world_generation_requested = true
		call_deferred("_init_world_generator")
		return
	
	_world_generation_requested = false
	
	# Generate a procedural world
	var params = {
		"grid_size": 5,  # Match the grid_size in Main scene
		"cell_size": 1024,
		"planet_density": 0.4,  # 40% of cells will have planets
		"terran_probability": 0.7  # 70% of planets will be terran
	}
	
	# Start the procedural generation process
	await world_generator.generate_world(params)

func _on_world_generated() -> void:
	print("World generation complete!")
	
	# Get planets safely with null checking
	var generated_planets = []
	if world_generator != null and is_instance_valid(world_generator):
		generated_planets = world_generator.get_generated_planets()
	
	print("Generated planets: ", generated_planets.size())
	
	# Generate a specific planet after a short delay
	_generate_specific_planet()

func _generate_specific_planet() -> void:
	# Guard against multiple calls
	if _specific_planet_generation_requested:
		return
	
	_specific_planet_generation_requested = true
	
	# Wait a moment before adding a special planet
	await get_tree().create_timer(0.5).timeout
	
	# Reset flag
	_specific_planet_generation_requested = false
	
	# Verify world generator is still valid
	if world_generator == null or not is_instance_valid(world_generator):
		print("WorldCreation: Can't generate specific planet - invalid generator reference")
		return
	
	# You can also generate individual planets with specific parameters
	var specific_planet_params = {
		"category": "terran",
		"theme": "lush",
		"moon_chance": 100,  # Force moons to spawn
		"min_moons": 2,
		"max_moons": 4
	}
	
	# Generate a specific planet in the center of the grid
	# Must use await since generate_planet_in_cell is a coroutine
	var planet = await world_generator.generate_planet_in_cell(Vector2i(2, 2), specific_planet_params)
	
	if planet != null and is_instance_valid(planet):
		print("Special planet generated successfully at grid cell (2,2)")
		_setup_game_after_generation()
	else:
		print("Failed to generate special planet - will retry")
		# Try again after a delay
		await get_tree().create_timer(1.0).timeout
		await _generate_specific_planet()

func _setup_game_after_generation() -> void:
	# Optional: Add any post-generation setup
	# For example, you might want to center the camera on a particular planet
	# or trigger initial game events
	
	# Find player node
	var player = get_node_or_null("/root/Main/PlayerShip")
	if player != null and is_instance_valid(player):
		# Position player near a planet if desired
		var planets = []
		if world_generator != null and is_instance_valid(world_generator):
			planets = world_generator.get_generated_planets()
		
		if not planets.is_empty():
			var target_planet = planets[0]
			if is_instance_valid(target_planet):
				# Place the player near the first planet
				var offset = Vector2(50, 0)  # Offset from planet position
				player.global_position = target_planet.global_position + offset
				print("Positioned player near planet")
