# grid.gd
class_name Grid
extends Node2D

# Grid properties
@export var cell_size: Vector2 = Vector2(512, 512)
@export var grid_size: Vector2 = Vector2(10, 10)
@export var grid_color: Color = Color(0.2, 0.2, 0.2, 0.5)
@export var boundary_color: Color = Color(1.0, 0.0, 0.0, 0.8)
@export var font_size: int = 14
@export var seed_value: int = 0
@export var chunk_load_radius: int = 1

signal _seed_changed(new_seed)
signal _cell_loaded(cell_x, cell_y)
signal _cell_unloaded(cell_x, cell_y)
signal _player_entered_boundary(cell_x, cell_y)
signal _player_left_boundary

enum CellContent { EMPTY, PLANET, ASTEROID }

var cell_contents = []
var current_player_cell_x = -1
var current_player_cell_y = -1
var loaded_cells = {}
var was_in_boundary_cell = false
var was_outside_grid = false
var player_immobilized = false
var respawn_timer = 0.0
var last_valid_position = Vector2.ZERO
var boundary_warning_active = false

var resource_manager: ResourceManager
var planet_spawner = null
var asteroid_spawner = null

func _ready():
	scale = Vector2.ONE
	
	resource_manager = get_node_or_null("/root/Main/ResourceManager")
	if not resource_manager:
		resource_manager = get_node_or_null("/root/Main/Node")
	
	planet_spawner = get_node_or_null("/root/Main/PlanetSpawner")
	asteroid_spawner = get_node_or_null("/root/Main/AsteroidSpawner")
	
	generate_cell_contents()

func _process(delta):
	scale = Vector2.ONE
	
	var player = get_node_or_null("/root/Main/Player")
	if not player:
		return
		
	check_player_position(player, delta)
	queue_redraw()
	update_enemy_visibility()

func check_player_position(player, delta):
	var player_pos = player.global_position
	var cell_x = int(floor(player_pos.x / cell_size.x))
	var cell_y = int(floor(player_pos.y / cell_size.y))
	
	var grid_x = int(grid_size.x)
	var grid_y = int(grid_size.y)
	
	var outside_grid = cell_x < 0 or cell_x >= grid_x or cell_y < 0 or cell_y >= grid_y
	
	if not outside_grid and not player_immobilized:
		last_valid_position = player.global_position
	
	if outside_grid:
		handle_player_outside_grid(player)
	
	if player_immobilized:
		handle_player_immobilized(player, delta)
		return
	
	was_outside_grid = outside_grid
	if outside_grid:
		return
	
	var is_in_boundary = is_boundary_cell(cell_x, cell_y)
	handle_boundary_warnings(is_in_boundary)
	was_in_boundary_cell = is_in_boundary
	
	# Update loaded chunks if player moved to a new cell
	if cell_x != current_player_cell_x or cell_y != current_player_cell_y:
		update_loaded_chunks(cell_x, cell_y)

func handle_player_outside_grid(player):
	player.global_position = last_valid_position
	
	if not was_outside_grid:
		var main = get_tree().current_scene
		if main.has_method("show_message"):
			main.show_message("You abandoned all logic and were lost in space!")
		
		player_immobilized = true
		respawn_timer = 5.0
		
		if player.has_method("set_immobilized"):
			player.set_immobilized(true)

func handle_player_immobilized(player, delta):
	player.global_position = last_valid_position
	respawn_timer -= delta
	
	if respawn_timer <= 0:
		player_immobilized = false
		respawn_timer = 0.0
		
		if player.has_method("set_immobilized"):
			player.set_immobilized(false)
		
		var main = get_tree().current_scene
		if main.has_method("respawn_player_at_initial_planet"):
			main.respawn_player_at_initial_planet()
		
		was_outside_grid = false
		was_in_boundary_cell = false

func handle_boundary_warnings(is_in_boundary):
	if is_in_boundary and not was_in_boundary_cell and not boundary_warning_active:
		var main = get_tree().current_scene
		if main.has_method("show_message"):
			main.show_message("WARNING: You are leaving known space!")
			boundary_warning_active = true
		
		emit_signal("_player_entered_boundary", current_player_cell_x, current_player_cell_y)
	
	if not is_in_boundary and was_in_boundary_cell:
		var main = get_tree().current_scene
		if main.has_method("hide_message"):
			main.hide_message()
			boundary_warning_active = false
		
		emit_signal("_player_left_boundary")

func update_loaded_chunks(center_x, center_y):
	current_player_cell_x = center_x
	current_player_cell_y = center_y
	
	var previously_loaded = loaded_cells.duplicate()
	loaded_cells.clear()
	
	for y in range(center_y - chunk_load_radius, center_y + chunk_load_radius + 1):
		for x in range(center_x - chunk_load_radius, center_x + chunk_load_radius + 1):
			if is_valid_position(x, y):
				var cell_pos = Vector2i(x, y)
				loaded_cells[cell_pos] = true
				
				if not previously_loaded.has(cell_pos):
					emit_signal("_cell_loaded", x, y)
	
	for cell_pos in previously_loaded:
		if not loaded_cells.has(cell_pos):
			emit_signal("_cell_unloaded", cell_pos.x, cell_pos.y)

func update_enemy_visibility():
	var enemy_spawner = get_node_or_null("/root/Main/EnemySpawner")
	if not enemy_spawner:
		return
		
	for enemy in enemy_spawner.spawned_enemies:
		if is_instance_valid(enemy):
			var enemy_cell_x = int(floor(enemy.global_position.x / cell_size.x))
			var enemy_cell_y = int(floor(enemy.global_position.y / cell_size.y))
			
			var is_cell_loaded = loaded_cells.has(Vector2i(enemy_cell_x, enemy_cell_y))
			enemy.update_active_state(is_cell_loaded)

func _draw():
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	
	for cell_pos in loaded_cells.keys():
		var x = int(cell_pos.x)
		var y = int(cell_pos.y)
		
		var rect_pos = Vector2(x * cell_size.x, y * cell_size.y)
		
		var line_color = grid_color
		var line_width = 1.0
		
		if is_boundary_cell(x, y):
			line_color = boundary_color
			line_width = 2.0
		
		# Draw all 4 sides of the cell
		draw_line(rect_pos, rect_pos + Vector2(cell_size.x, 0), line_color, line_width)
		draw_line(rect_pos + Vector2(0, cell_size.y), rect_pos + cell_size, line_color, line_width)
		draw_line(rect_pos, rect_pos + Vector2(0, cell_size.y), line_color, line_width)
		draw_line(rect_pos + Vector2(cell_size.x, 0), rect_pos + cell_size, line_color, line_width)
		
		draw_cell_coordinates(x, y)
	
	if asteroid_spawner:
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
		asteroid_spawner.draw_asteroids(self, loaded_cells)

func draw_cell_coordinates(x, y):
	var cell_center = Vector2(
		x * cell_size.x + cell_size.x / 2.0,
		y * cell_size.y + cell_size.y / 2.0
	)
	
	var coord_text = "(%d,%d)" % [x, y]
	var text_size = ThemeDB.fallback_font.get_string_size(coord_text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	var coord_pos = cell_center - Vector2(text_size.x / 2.0, font_size / 2.0 - 5)
	
	var outline_color = Color.BLACK
	var outline_width = 1
	
	for dx in range(-outline_width, outline_width + 1):
		for dy in range(-outline_width, outline_width + 1):
			if dx != 0 or dy != 0:
				draw_string(
					ThemeDB.fallback_font,
					coord_pos + Vector2(dx, dy),
					coord_text,
					HORIZONTAL_ALIGNMENT_LEFT,
					-1,
					font_size,
					outline_color
				)
	
	draw_string(
		ThemeDB.fallback_font,
		coord_pos,
		coord_text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color.WHITE
	)

func regenerate():
	generate_cell_contents()

func set_seed(new_seed):
	if seed_value == new_seed:
		return
		
	seed_value = new_seed
	regenerate()
	emit_signal("_seed_changed", new_seed)

func generate_cell_contents():
	cell_contents = []
	
	for y in range(int(grid_size.y)):
		cell_contents.append([])
		for x in range(int(grid_size.x)):
			cell_contents[y].append(CellContent.EMPTY)
	
	loaded_cells = {}
	queue_redraw()

func is_valid_position(x, y):
	return x >= 0 and x < int(grid_size.x) and y >= 0 and y < int(grid_size.y)

func is_boundary_cell(x, y):
	var grid_x = int(grid_size.x)
	var grid_y = int(grid_size.y)
	return (x == 0 or x == grid_x - 1 or y == 0 or y == grid_y - 1) and is_valid_position(x, y)

func get_cell_content(x, y):
	if is_valid_position(x, y) and y < cell_contents.size() and x < cell_contents[y].size():
		return cell_contents[y][x]
	return CellContent.EMPTY

func set_cell_content(x, y, content):
	if is_valid_position(x, y) and y < cell_contents.size() and x < cell_contents[y].size():
		cell_contents[y][x] = content
		return true
	return false

func get_cell_at_position(world_pos):
	var cell_x = int(floor(world_pos.x / cell_size.x))
	var cell_y = int(floor(world_pos.y / cell_size.y))
	return Vector2i(cell_x, cell_y)

func get_cell_center(cell_x, cell_y):
	return Vector2(
		cell_x * cell_size.x + cell_size.x / 2.0,
		cell_y * cell_size.y + cell_size.y / 2.0
	)

func get_empty_cells():
	var empty_cells = []
	for y in range(int(grid_size.y)):
		for x in range(int(grid_size.x)):
			if not is_boundary_cell(x, y) and cell_contents[y][x] == CellContent.EMPTY:
				empty_cells.append(Vector2i(x, y))
	return empty_cells
