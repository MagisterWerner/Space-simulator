# planet_spawner.gd
extends Node

@export var planet_percentage: int = 10
@export var minimum_planets: int = 5
@export var cell_margin: float = 0.2
@export var moon_chance: int = 40
@export var max_moons: int = 2
@export var min_moon_distance_factor: float = 1.8
@export var max_moon_distance_factor: float = 2.5
@export var max_orbit_deviation: float = 0.15
@export var moon_orbit_factor: float = 0.05

var grid = null
var planet_scene = null
var spawned_planets = []
var planet_positions = []
var planet_data = []

func _ready():
	grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		push_error("ERROR: Grid not found for planet spawning!")
		return
	
	if not ResourceLoader.exists("res://scenes/planet.tscn"):
		push_error("ERROR: Planet scene not found at res://scenes/planet.tscn")
		return
	else:
		planet_scene = load("res://scenes/planet.tscn")
	
	if grid.has_signal("_seed_changed"):
		grid.connect("_seed_changed", _on_grid_seed_changed)
	
	if grid.has_signal("_cell_loaded"):
		grid.connect("_cell_loaded", _on_cell_loaded)
	if grid.has_signal("_cell_unloaded"):
		grid.connect("_cell_unloaded", _on_cell_unloaded)

func generate_planets():
	clear_planets()
	planet_positions.clear()
	planet_data.clear()
	
	if not planet_scene:
		if ResourceLoader.exists("res://scenes/planet.tscn"):
			planet_scene = load("res://scenes/planet.tscn")
		else:
			push_error("ERROR: Planet scene not found for generation")
			return
			
	if not grid or grid.cell_contents.size() == 0:
		return
	
	var available_cells = []
	for y in range(1, int(grid.grid_size.y) - 1):
		for x in range(1, int(grid.grid_size.x) - 1):
			if grid.is_boundary_cell(x, y):
				continue
			
			available_cells.append(Vector2i(x, y))
	
	var reserved_cells = {}
	
	var non_boundary_count = available_cells.size()
	var planet_count = max(minimum_planets, int(non_boundary_count * planet_percentage / 100.0))
	planet_count = min(planet_count, non_boundary_count)
	
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value
	
	var actual_planet_count = 0
	
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
		
		grid.cell_contents[y][x] = grid.CellContent.PLANET
		actual_planet_count += 1
		
		var planet_seed = grid.seed_value + x * 10000 + y * 1000
		
		var world_pos = Vector2(
			x * grid.cell_size.x + grid.cell_size.x / 2,
			y * grid.cell_size.y + grid.cell_size.y / 2
		)
		
		planet_positions.append({
			"position": world_pos,
			"grid_x": x,
			"grid_y": y,
			"seed": planet_seed
		})
		
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var nx = x + dx
				var ny = y + dy
				
				if grid.is_valid_position(nx, ny):
					reserved_cells[Vector2i(nx, ny)] = true
		
		if actual_planet_count >= planet_count:
			break
	
	if grid.loaded_cells:
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
	if not planet_scene:
		if ResourceLoader.exists("res://scenes/planet.tscn"):
			planet_scene = load("res://scenes/planet.tscn")
		else:
			push_error("ERROR: Planet scene not found for spawn")
			return null
			
	var planet_instance = planet_scene.instantiate()
	if not planet_instance:
		push_error("ERROR: Failed to instantiate planet")
		return null
		
	var params = {
		"seed_value": seed_value,
		"grid_x": grid_x,
		"grid_y": grid_y,
		"max_moons": max_moons,
		"moon_chance": moon_chance,
		"min_moon_distance_factor": min_moon_distance_factor,
		"max_moon_distance_factor": max_moon_distance_factor,
		"max_orbit_deviation": max_orbit_deviation,
		"moon_orbit_factor": moon_orbit_factor
	}
	
	planet_instance.initialize(params)
	planet_instance.global_position = position
	get_parent().add_child(planet_instance)
	spawned_planets.append(planet_instance)
	
	var planet_name = ""
	if "planet_name" in planet_instance:
		planet_name = planet_instance.planet_name
	
	var pixel_size = 256
	if "pixel_size" in planet_instance:
		pixel_size = planet_instance.pixel_size
	
	var theme_id = 0
	if "theme_id" in planet_instance:
		theme_id = planet_instance.theme_id
	
	var atmosphere_data = {}
	if "atmosphere_data" in planet_instance:
		atmosphere_data = planet_instance.atmosphere_data
	
	var moons = []
	if "moons" in planet_instance:
		moons = planet_instance.moons
		
	var planet_data_entry = {
		"seed": seed_value,
		"scale": 1.0,
		"pixel_size": pixel_size,
		"moons": moons,
		"name": planet_name,
		"theme": theme_id,
		"atmosphere": atmosphere_data,
		"grid_x": grid_x,
		"grid_y": grid_y
	}
	
	planet_data.append(planet_data_entry)
	
	return planet_instance

func _on_cell_loaded(cell_x, cell_y):
	if not grid:
		return
		
	if cell_x < 0 or cell_y < 0 or cell_y >= grid.cell_contents.size() or cell_x >= grid.cell_contents[cell_y].size():
		return
	
	if grid.cell_contents[cell_y][cell_x] == grid.CellContent.PLANET:
		for planet_pos in planet_positions:
			if planet_pos.grid_x == cell_x and planet_pos.grid_y == cell_y:
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
	
	for data in planet_data:
		if data.grid_x == x and data.grid_y == y and "name" in data:
			return data.name
	
	var name_component = NameComponent.new()
	var seed_value = grid.seed_value + x * 10000 + y * 1000
	name_component.initialize(seed_value, x, y)
	var planet_name = name_component.get_entity_name()
	name_component.queue_free()
	return planet_name

func reset_planets():
	call_deferred("generate_planets")

func _on_grid_seed_changed(_new_seed = null):
	call_deferred("reset_planets")

func draw_planets(_canvas: CanvasItem, _loaded_cells: Dictionary):
	pass
