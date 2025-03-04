extends Node2D

################################################################################
# Shorthand names to identify nodes in the current scene tree
################################################################################
@onready var noise_generator = $NoiseGenerator       # Shorthand for the tile map generator
@onready var tilemap = $TileMap                      # Shorthand for the actual TileMap node
################################################################################


################################################################################
# Preloaded scenes that gets instantiated in the world space
################################################################################
@onready var label_scene = preload("res://scenes/world/label.tscn")
@onready var asteroid_small = preload("res://scenes/objects/asteroids/asteroid_small.tscn")
@onready var asteroid_medium = preload("res://scenes/objects/asteroids/asteroid_medium.tscn")
@onready var asteroid_large = preload("res://scenes/objects/asteroids/asteroid_large.tscn")
@onready var planet_arid: PackedScene = preload("res://scenes/objects/planets/planet_arid.tscn")
@onready var planet_frozen: PackedScene = preload("res://scenes/objects/planets/planet_frozen.tscn")
@onready var planet_humid: PackedScene = preload("res://scenes/objects/planets/planet_humid.tscn")
@onready var planet_volcanic: PackedScene = preload("res://scenes/objects/planets/planet_volcanic.tscn")
################################################################################


################################################################################
# Stuff I'm not sure what to sort under...
################################################################################
@onready var tiles_black: Array
@onready var tiles_yellow: Array
@onready var tiles_green: Array
@onready var half_sector_size: Vector2i
@onready var sector_count: int = Globals.sector_number
@onready var grid_origin: Vector2 = Vector2(sector_count / 2.0, sector_count / 2.0)
@onready var rng = RandomNumberGenerator.new()
################################################################################


################################################################################
# Exported variables that can be changed from the Inspector in the editor
################################################################################
#@export var sector_size: = Vector2(2048,2048)
#@export var sector_number: int = 20
@export var grid_color: Color = "white"
@export var planets: int = 4   # Replace with desired max number (set in inspector)
@export var world_seed: int = 1
#@export var max_asteroids: int = 5  # Replace with desired max number (set in inspector)
################################################################################


################################################################################
# Arrays of objects that can get randomized when instanced
################################################################################
@onready var planet_array = [planet_arid, planet_frozen, planet_humid, planet_volcanic]
@onready var asteroid_array = [asteroid_small, asteroid_medium, asteroid_medium, asteroid_large, asteroid_large, asteroid_large]
################################################################################


################################################################################
# Called when the node enters the scene tree for the first time.
################################################################################
func _ready():
	noise_generator.settings.world_size = Vector2(Globals.sector_number, Globals.sector_number)
	tilemap.tile_set.tile_size = Globals.sector_size
	tilemap.visible = false
	$ColorRect.set_deferred("size", Globals.sector_size * Globals.sector_number)
	half_sector_size = Vector2i(Globals.sector_size / 2)  # Calculate half tile size
	
	await get_tree().create_timer(0.5).timeout
	
	tiles_black = tilemap.get_used_cells_by_id(0, 0, Vector2i(0, 0))  # Adjust layer_id and source_id if necessary
	tiles_yellow = tilemap.get_used_cells_by_id(0, 0, Vector2i(1, 0))  # Adjust layer_id and source_id if necessary
	tiles_green = tilemap.get_used_cells_by_id(0, 0, Vector2i(2, 0))  # Adjust layer_id and source_id if necessary
	
	planet_spawner()
	asteroid_light_spawner()
	asteroid_heavy_spawner()
################################################################################


################################################################################
# Instantiate labels for a cell position in the world space
################################################################################
func label_cell_position(world_position, cell):
# Add position label information in the middle of each cell
		var label_instance = label_scene.instantiate()
		label_instance.text = str(cell)
		label_instance.position = world_position + half_sector_size
		ObjectRegistry.register_label(label_instance) # Instantiate in the Autoload singleton
#		labels_registry.add_child(label_instance)
################################################################################


################################################################################
# Function to find cells surrounding the current cell
################################################################################
func get_neighboring_cells(cell):
	var neighbors = []
	var neighbor_offsets = [
		Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0),  # Up, down, left, right
		Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),   # Diagonals
		Vector2i(0, 2), Vector2i(0, -2), Vector2i(2, 0), Vector2i(-2, 0),
		Vector2i(1, 2), Vector2i(1, -2), Vector2i(2, 1), Vector2i(-2, 1),
		Vector2i(-1, 2), Vector2i(-1, -2), Vector2i(-2, -1), Vector2i(2, 1),
		Vector2i(-2, 2), Vector2i(-2, -2), Vector2i(2, -2), Vector2i(2, 2)
	]
	for offset in neighbor_offsets:
		var neighbor_cell = cell + offset
		# Check if within bounds (same as before)
		if 0 <= neighbor_cell.x and neighbor_cell.x < tilemap.tile_set.tile_size.x and 0 <= neighbor_cell.y and neighbor_cell.y < tilemap.tile_set.tile_size.y:
			# Check if not already included as a cardinal neighbor (avoid double counting)
			if not (offset.x == 0 or offset.y == 0) or !(neighbor_cell in neighbors):
				neighbors.append(neighbor_cell)
	return neighbors
################################################################################


################################################################################
# Spawn planets randomly  within the assigned tiles in the tile map
################################################################################
func planet_spawner():
# Setup:
#        tiles          = which colored tiles to spawn on

	var tiles = tiles_black
################################################################################
	tiles.shuffle()
	var planet = planets
	var planets_spawned = []  # Keep track of spawned planets
	
	for cell in tiles:
		var random_planet = planet_array[rng.randi() % planet_array.size()]
		var world_position = cell * tilemap.tile_set.tile_size
		var spawn_planet = planet != 0
		
		label_cell_position(world_position, cell) # Instatiate a cell position label in each tile
		
		if planet != 0:
			# Check for neighboring planets before spawning
			for neighbor in get_neighboring_cells(cell):
				if neighbor in planets_spawned:
					spawn_planet = false  # Don't spawn planet if neighbor has one
					print("Planet failed to spawn at cell ", cell, " because of neighboring planet")
					break  # Exit loop if neighboring planet found
					
			if spawn_planet:
				print("Planet spawned at cell ", cell)
				var planet_instance = random_planet.instantiate()
				planet_instance.position = world_position + half_sector_size
				planets_spawned.append(cell)  # Add spawned planet cell to list
				ObjectRegistry.register_planet(planet_instance) # Instantiate in the Autoload singleton
				var planet_size = rng.randf_range(1.0, 3.0) # Random planet size
				planet_instance.scale = Vector2(planet_size, planet_size)
				planet -= 1
################################################################################


################################################################################
# Spawn asteroids within a sub grid on every assigned tile in the tile map
################################################################################
func asteroid_light_spawner():
# Setup:
#        tiles          = which colored tiles to spawn on
#        sub_cell_count = The number of sub divisions for x and y
#        odds_to_spawn  = The chance to spawn in each cell 0-100 percent

	var tiles = tiles_yellow
	var sub_cell_count = 5 # The number of sub cells inside each cell	
	var odds_to_spawn = 25
################################################################################
	var sub_cell_size = Globals.sector_size/sub_cell_count # The size of each sub cell
	var grid_size = Vector2(sub_cell_count, sub_cell_count) # The size of the grid
	var grid = [] # Create a 2D array to hold the grid data
	var row = [] # Create a 2D array to hold the data for each row
	
# Loop through all available tiles and sub tiles
	for cell in tiles:
		var world_position = cell * tilemap.tile_set.tile_size # Position each cell in the world
		
		label_cell_position(world_position, cell) # Instatiate a cell position label in each tile
		
		for x in range(grid_size.x):
			for y in range(grid_size.y):
				var random_asteroid = asteroid_array[rng.randi() % asteroid_array.size()] # Choose an asteroid randomly from the array
				var sub_cell = Vector2(x, y) # Assign each sub cell its coordinates within the grid
				var asteroid_instance = random_asteroid.instantiate() # Create an instance of the proper asteroid scene
				var center_offset = (sub_cell_size/2) + Vector2(rng.randi_range(-sub_cell_size.x/3, sub_cell_size.x/3), rng.randi_range(-sub_cell_size.y/3, sub_cell_size.y/3)) # Create an offset within each sub cell
				asteroid_instance.position = world_position + Vector2i(sub_cell * sub_cell_size + center_offset) # Position each asteroid within the grid
				asteroid_instance.rotation = rng.randi() % 360
				if rng.randi() % 100 >= 100-odds_to_spawn: # Determine the odds of which to spawn an asteroid in each sub cell
					ObjectRegistry.register_asteroid(asteroid_instance) # Instantiate in the Autoload singleton
				row.append(asteroid_instance) # Add the instance to the row
			grid.append(row) # Move on to the next row
################################################################################


################################################################################
# Spawn asteroids within a sub grid on every assigned tile in the tile map
################################################################################
func asteroid_heavy_spawner():
# Setup:
#        tiles          = which colored tiles to spawn on
#        sub_cell_count = The number of sub divisions for x and y
#        odds_to_spawn  = The chance to spawn in each cell 0-100 percent

	var tiles = tiles_green
	var sub_cell_count = 5 # The number of sub cells inside each cell	
	var odds_to_spawn = 75
################################################################################
	var sub_cell_size = Globals.sector_size/sub_cell_count # The size of each sub cell
	var grid_size = Vector2(sub_cell_count, sub_cell_count) # The size of the grid
	var grid = [] # Create a 2D array to hold the grid data
	var row = [] # Create a 2D array to hold the data for each row
	
# Loop through all available tiles and sub tiles
	for cell in tiles:
		var world_position = cell * tilemap.tile_set.tile_size # Position each cell in the world
		
		label_cell_position(world_position, cell) # Instatiate a cell position label in each tile
		
		for x in range(grid_size.x):
			for y in range(grid_size.y):
				var random_asteroid = asteroid_array[rng.randi() % asteroid_array.size()] # Choose an asteroid randomly from the array
				var sub_cell = Vector2(x, y) # Assign each sub cell its coordinates within the grid
				var asteroid_instance = random_asteroid.instantiate() # Create an instance of the proper asteroid scene
				var center_offset = (sub_cell_size/2) + Vector2(rng.randi_range(-sub_cell_size.x/3, sub_cell_size.x/3), rng.randi_range(-sub_cell_size.y/3, sub_cell_size.y/3)) # Create an offset within each sub cell
				asteroid_instance.position = world_position + Vector2i(sub_cell * sub_cell_size + center_offset) # Position each asteroid within the grid
				asteroid_instance.rotation = rng.randi() % 360
				if rng.randi() % 100 >= 100-odds_to_spawn: # Determine the odds of which to spawn an asteroid in each sub cell
					ObjectRegistry.register_asteroid(asteroid_instance) # Instantiate in the Autoload singleton
				row.append(asteroid_instance) # Add the instance to the row
			grid.append(row) # Move on to the next row
################################################################################


################################################################################
# Draw grid
################################################################################
func _draw() -> void:
	if Globals.sector_size == Vector2(0, 0):
		return
	var position_origin := grid_origin * Globals.sector_size
	var half_sector_count := int(sector_count / 2.0)
	for x in range(-half_sector_count, half_sector_count):
		for y in range(-half_sector_count, half_sector_count):
			var sector_rect := Rect2(
				Vector2(
					position_origin.x + x * Globals.sector_size.x,
					position_origin.y + y * Globals.sector_size.y
				),
				Vector2(Globals.sector_size)
			)
			draw_rect(sector_rect, grid_color, false)
################################################################################
