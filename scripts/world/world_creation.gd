# Example usage in a game scene
extends Node2D

# Reference to world generator
var world_generator: WorldGenerator

func _ready():
	# Create the world generator
	world_generator = WorldGenerator.new()
	world_generator.default_grid_size = 5
	world_generator.default_cell_size = 1024
	world_generator.debug_mode = true
	add_child(world_generator)
	
	# Connect to signals
	world_generator.world_generation_completed.connect(_on_world_generated)
	
	# Generate a procedural world
	var params = {
		"grid_size": 5,
		"cell_size": 1024,
		"planet_density": 0.4,  # 40% of cells will have planets
		"terran_probability": 0.7  # 70% of planets will be terran
	}
	
	world_generator.generate_world(params)
	
	# You can also generate individual planets
	var specific_planet_params = {
		"category": "terran",
		"theme": "lush",
		"moon_chance": 100,  # Force moons to spawn
		"min_moons": 2,
		"max_moons": 4
	}
	
	world_generator.generate_planet_in_cell(Vector2i(2, 2), specific_planet_params)

func _on_world_generated():
	print("World generation complete!")
	print("Generated planets: ", world_generator.get_generated_planets().size())
