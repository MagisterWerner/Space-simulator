extends Node

@onready var galaxy_generator = %GalaxyGenerator
@onready var noise_seed = galaxy_generator.noise_generator.seed
@onready var world_seed = %ParallaxBackground/ParallaxLayer1/Stars.texture.noise.seed

var previous_cell_coordinates: Vector2


# `pre_start()` is called when a scene is loaded.
# Use this function to receive params from `Game.change_scene(params)`.
func pre_start(params):
	var cur_scene: Node = get_tree().current_scene
	print("Scene loaded: ", cur_scene.name, " (", cur_scene.scene_file_path, ")")
	if params:
		for key in params:
			var val = params[key]
			printt("", key, val)
	$PlayerShip.position = (Globals.sector_size * Globals.sector_number)/2
	$PauseLayer.visible = true


# `start()` is called after pre_start and after the graphic transition ends.
func start():
	print("gameplay.gd: start() called")


func _process(_delta):
	# Get the player's world position
	var player_position: Vector2 = $PlayerShip/Ship.global_position
	
	# Convert the world position to tilemap cell coordinates
	var cell_coordinates: Vector2 = %GalaxyGenerator/TileMap.local_to_map(player_position)
	
	# Check if the cell coordinates have changed
	if cell_coordinates != previous_cell_coordinates:
		# Update the print statement and the previous cell coordinates
		print("Sector: (%d, %d)" % [cell_coordinates.x, cell_coordinates.y])
		previous_cell_coordinates = cell_coordinates
		if cell_coordinates.x < 0 or cell_coordinates.y < 0:
			print("You are outside of mapped space!")


func _ready():
	generate_from_seed()
	# Initialize the previous cell coordinates with an invalid value
	previous_cell_coordinates = Vector2(-1, -1)
	

func generate_from_seed():
	if Globals.random_seed:
		var _random_seed = randi() % 999999999
		galaxy_generator.noise_generator.seed = _random_seed
		noise_seed = _random_seed
		world_seed = _random_seed
		galaxy_generator.noise_generator.settings.noise.seed = _random_seed
	else:
		galaxy_generator.noise_generator.seed = Globals.world_seed
		noise_seed = Globals.world_seed
		world_seed = Globals.world_seed
		galaxy_generator.noise_generator.settings.noise.seed = Globals.world_seed
