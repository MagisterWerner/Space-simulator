# planet_spawner.gd
extends Node

@export var planet_percentage: int = 10
@export var minimum_planets: int = 5
@export var cell_margin: float = 0.2

var grid = null
var planet_scene = preload("res://planet.tscn")
var spawned_planets = []
var planet_positions = []
var planet_data = []

func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for planet spawning!")
		return
	
	if grid.has_signal("_seed_changed"):
		grid.connect("_seed_changed", _on_grid_seed_changed)
	
	if grid.has_signal("_cell_loaded"):
		grid.connect("_cell_loaded", _on_cell_loaded)
	if grid.has_signal("_cell_unloaded"):
		grid.connect("_cell_unloaded", _on_cell_unloaded)

func generate_planets():
	# Clear existing data
	clear_planets()
	planet_positions.clear()
	planet_data.clear()
	
	if grid.cell_contents.size() == 0:
		return
	
	# Get available cells
	var available_cells = []
	for y in range(1, int(grid.grid_size.y) - 1):
		for x in range(1, int(grid.grid_size.x) - 1):
			if grid.is_boundary_cell(x, y):
				continue
			
			available_cells.append(Vector2i(x, y))
	
	# Track reserved cells
	var reserved_cells = {}
	
	# Calculate planet count
	var non_boundary_count = available_cells.size()
	var planet_count = max(minimum_planets, int(non_boundary_count * planet_percentage / 100.0))
	planet_count = min(planet_count, non_boundary_count)
	
	# Set up RNG
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value
	
	var actual_planet_count = 0
	
	# Generate planets
	for i in range(planet_count * 3):
		var avail_indices = []
		for j in range(available_cells.size()):
			var pos = available_cells[j]
			if not reserved_cells.has(pos):
				avail_indices.append(j)
		
		if avail_indices.size() == 0:
			break
		
		var idx = avail_indices[rng.randi() % avail_indices.size()]
		var planet_pos = available_cells[idx]
		var x = planet_pos.x
		var y = planet_pos.y
		
		# Mark as planet
		grid.cell_contents[y][x] = grid.CellContent.PLANET
		actual_planet_count += 1
		
		# Generate planet seed
		var planet_seed = grid.seed_value + x * 10000 + y * 1000
		
		# Calculate world position
		var world_pos = Vector2(
			x * grid.cell_size.x + grid.cell_size.x / 2,
			y * grid.cell_size.y + grid.cell_size.y / 2
		)
		
		# Store planet position
		planet_positions.append({
			"position": world_pos,
			"grid_x": x,
			"grid_y": y,
			"seed": planet_seed
		})
		
		# Reserve cells
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx = x + dx
				var ny = y + dy
				
				if grid.is_valid_position(nx, ny):
					reserved_cells[Vector2i(nx, ny)] = true
		
		if actual_planet_count >= planet_count:
			break
	
	# Create planets for cells that are already loaded
	for cell_pos in grid.loaded_cells.keys():
		var x = int(cell_pos.x)
		var y = int(cell_pos.y)
		
		if y >= grid.cell_contents.size() or x >= grid.cell_contents[y].size():
			continue
			
		if grid.cell_contents[y][x] == grid.CellContent.PLANET:
			for planet_pos in planet_positions:
				if planet_pos.grid_x == x and planet_pos.grid_y == y:
					spawn_planet(
						planet_pos.position,
						planet_pos.grid_x,
						planet_pos.grid_y, 
						planet_pos.seed
					)
					break
	
	grid.queue_redraw()

func clear_planets():
	for planet in spawned_planets:
		if is_instance_valid(planet):
			planet.queue_free()
	
	spawned_planets.clear()

func spawn_planet(position, grid_x, grid_y, seed_value):
	var planet_instance = planet_scene.instantiate()
	
	planet_instance.initialize({
		"seed_value": seed_value,
		"grid_x": grid_x,
		"grid_y": grid_y
	})
	
	planet_instance.global_position = position
	get_parent().add_child(planet_instance)
	spawned_planets.append(planet_instance)
	
	# Update planet_data for compatibility with old code
	var planet_data_entry = {
		"seed": seed_value,
		"scale": 1.0,
		"pixel_size": planet_instance.pixel_size,
		"moons": planet_instance.moons,
		"name": planet_instance.planet_name,
		"theme": planet_instance.theme_id,
		"atmosphere": planet_instance.atmosphere_data
	}
	
	planet_data.append(planet_data_entry)
	
	return planet_instance

func _on_cell_loaded(cell_x, cell_y):
	if cell_x < 0 or cell_y < 0 or cell_y >= grid.cell_contents.size() or cell_x >= grid.cell_contents[cell_y].size():
		return
	
	if grid.cell_contents[cell_y][cell_x] == grid.CellContent.PLANET:
		for planet_pos in planet_positions:
			if planet_pos.grid_x == cell_x and planet_pos.grid_y == cell_y:
				# Check if planet already exists
				var planet_exists = false
				for planet in spawned_planets:
					if is_instance_valid(planet) and planet.grid_x == cell_x and planet.grid_y == cell_y:
						planet_exists = true
						break
				
				if not planet_exists:
					spawn_planet(
						planet_pos.position,
						planet_pos.grid_x,
						planet_pos.grid_y, 
						planet_pos.seed
					)
				break

func _on_cell_unloaded(cell_x, cell_y):
	for i in range(spawned_planets.size() - 1, -1, -1):
		var planet = spawned_planets[i]
		if is_instance_valid(planet) and planet.grid_x == cell_x and planet.grid_y == cell_y:
			planet.queue_free()
			spawned_planets.remove_at(i)

func get_all_planet_positions():
	return planet_positions

func get_planet_name(x, y):
	for planet in spawned_planets:
		if is_instance_valid(planet) and planet.grid_x == x and planet.grid_y == y:
			return planet.planet_name
	
	# Fallback to generating a name
	var name_component = NameComponent.new()
	var seed_value = grid.seed_value + x * 10000 + y * 1000
	name_component.initialize(seed_value, x, y)
	return name_component.get_name()

func reset_planets():
	call_deferred("generate_planets")

func _on_grid_seed_changed(_new_seed = null):
	call_deferred("reset_planets")

# For compatibility with old code
func draw_planets(_canvas: CanvasItem, _loaded_cells: Dictionary):
	# This function is intentionally empty for backwards compatibility
	pass
