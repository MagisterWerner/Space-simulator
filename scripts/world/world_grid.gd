extends Node2D

# Grid settings
var game_settings: GameSettings = null
var grid_total_size: Vector2 = Vector2.ZERO

# Camera tracking
var _camera: Camera2D = null
var _viewport_size: Vector2 = Vector2.ZERO
var _last_camera_pos: Vector2 = Vector2.ZERO
var _last_camera_zoom: Vector2 = Vector2.ONE

# Cached grid properties for performance
var _cell_size: int = 1024
var _grid_size: int = 10
var _line_color: Color = Color.CYAN
var _line_width: float = 2.0
var _opacity: float = 0.5
var _draw_debug: bool = false

# Grid cell cache for performance
var _visible_cells := {}
var _cell_world_positions := {}
var _cell_centers := {}

# Draw optimization
var _redraw_needed: bool = false
const REDRAW_THRESHOLD: float = 50.0
const REDRAW_ZOOM_THRESHOLD: float = 0.05

func _ready() -> void:
	add_to_group("world_grid")
	_initialize_settings()
	_precalculate_grid_positions()
	_find_camera()
	_update_viewport_size()
	
	# Start with initial draw
	_redraw_needed = true

func _initialize_settings() -> void:
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		# Cache grid settings
		_cell_size = game_settings.grid_cell_size
		_grid_size = game_settings.grid_size
		_line_color = game_settings.grid_color
		_line_width = game_settings.grid_line_width
		_opacity = game_settings.grid_opacity
		_draw_debug = game_settings.draw_debug_grid
		
		# Calculate total grid size
		grid_total_size = Vector2(_cell_size, _cell_size) * _grid_size
		
		# Position grid centered at origin
		position = -grid_total_size / 2.0
		
		# Connect to settings changes if available
		if game_settings.has_signal("settings_changed") and not game_settings.is_connected("settings_changed", _on_settings_changed):
			game_settings.connect("settings_changed", _on_settings_changed)
	else:
		# Default settings
		_cell_size = 1024
		_grid_size = 10
		grid_total_size = Vector2(_cell_size, _cell_size) * _grid_size
		position = -grid_total_size / 2.0

func _on_settings_changed() -> void:
	if game_settings:
		# Update cached settings
		_cell_size = game_settings.grid_cell_size
		_grid_size = game_settings.grid_size
		_line_color = game_settings.grid_color
		_line_width = game_settings.grid_line_width
		_opacity = game_settings.grid_opacity
		_draw_debug = game_settings.draw_debug_grid
		
		# Update grid size
		grid_total_size = Vector2(_cell_size, _cell_size) * _grid_size
		position = -grid_total_size / 2.0
		
		# Recalculate grid positions
		_precalculate_grid_positions()
		
		_redraw_needed = true

func _precalculate_grid_positions() -> void:
	_cell_world_positions.clear()
	_cell_centers.clear()
	
	for x in range(_grid_size):
		for y in range(_grid_size):
			var cell = Vector2i(x, y)
			var cell_pos = Vector2(x * _cell_size, y * _cell_size)
			var cell_center = cell_pos + Vector2(_cell_size / 2.0, _cell_size / 2.0)
			
			_cell_world_positions[cell] = cell_pos
			_cell_centers[cell] = cell_center

func _find_camera() -> void:
	_camera = get_viewport().get_camera_2d()
	
	if not _camera:
		# Try player's camera
		var player_ships = get_tree().get_nodes_in_group("player")
		if not player_ships.is_empty():
			var player = player_ships[0]
			_camera = player.get_viewport().get_camera_2d()
	
	if not _camera:
		# Try main scene camera
		var main = get_node_or_null("/root/Main")
		if main:
			_camera = main.get_node_or_null("Camera2D")
	
	if _camera:
		_last_camera_pos = _camera.get_screen_center_position()
		_last_camera_zoom = _camera.zoom

func _update_viewport_size() -> void:
	_viewport_size = get_viewport_rect().size

func _process(_delta: float) -> void:
	# Check for changes that would require redrawing
	if _should_redraw():
		queue_redraw()
		_redraw_needed = false

func _should_redraw() -> bool:
	# Explicit redraw request
	if _redraw_needed:
		return true
		
	# Check viewport size changes
	var current_size = get_viewport_rect().size
	if current_size != _viewport_size:
		_viewport_size = current_size
		return true
	
	# Skip if no camera
	if not _camera or not is_instance_valid(_camera):
		_find_camera()
		return _camera != null
	
	# Check for significant camera movement
	var current_pos = _camera.get_screen_center_position()
	var movement_distance = current_pos.distance_to(_last_camera_pos)
	
	if movement_distance > REDRAW_THRESHOLD:
		_last_camera_pos = current_pos
		return true
	
	# Check for zoom changes
	var current_zoom = _camera.zoom
	if abs(current_zoom.x - _last_camera_zoom.x) > REDRAW_ZOOM_THRESHOLD:
		_last_camera_zoom = current_zoom
		return true
	
	return false

func _draw() -> void:
	if not _camera or not is_instance_valid(_camera):
		_find_camera()
		if not _camera:
			return
	
	# Update camera state
	_last_camera_pos = _camera.get_screen_center_position()
	_last_camera_zoom = _camera.zoom
	
	# Calculate visible area
	var visible_bounds = _calculate_visible_grid_bounds()
	if visible_bounds.is_empty():
		return
	
	# Draw grid lines
	_draw_grid_lines(visible_bounds)
	
	# Draw debug info if needed
	if _draw_debug:
		_draw_debug_info(visible_bounds)

func _calculate_visible_grid_bounds() -> Dictionary:
	var camera_pos = _camera.get_screen_center_position()
	var zoom = _camera.zoom
	
	# Calculate visible area with padding
	var visible_rect_size = _viewport_size / zoom
	var visible_rect = Rect2(
		camera_pos - visible_rect_size / 2, 
		visible_rect_size
	).grow(_cell_size)
	
	# Convert to local grid coordinates
	var local_top_left = visible_rect.position - position
	var local_bottom_right = local_top_left + visible_rect.size
	
	# Calculate grid cell bounds
	var start_x = int(max(0, floor(local_top_left.x / _cell_size)))
	var start_y = int(max(0, floor(local_top_left.y / _cell_size)))
	var end_x = int(min(_grid_size, ceil(local_bottom_right.x / _cell_size)))
	var end_y = int(min(_grid_size, ceil(local_bottom_right.y / _cell_size)))
	
	# Early return if nothing to draw
	if start_x >= end_x or start_y >= end_y:
		return {}
	
	return {
		"start_x": start_x,
		"start_y": start_y,
		"end_x": end_x,
		"end_y": end_y,
		"pixel_start_x": start_x * _cell_size,
		"pixel_start_y": start_y * _cell_size,
		"pixel_end_x": end_x * _cell_size,
		"pixel_end_y": end_y * _cell_size
	}

func _draw_grid_lines(bounds: Dictionary) -> void:
	var line_color = _line_color * Color(1, 1, 1, _opacity)
	
	# Pre-calculate line coordinates
	var lines = []
	
	# Vertical lines
	for x in range(bounds.start_x, bounds.end_x + 1):
		var line_x = x * _cell_size
		lines.append({
			"start": Vector2(line_x, bounds.pixel_start_y),
			"end": Vector2(line_x, bounds.pixel_end_y)
		})
	
	# Horizontal lines
	for y in range(bounds.start_y, bounds.end_y + 1):
		var line_y = y * _cell_size
		lines.append({
			"start": Vector2(bounds.pixel_start_x, line_y),
			"end": Vector2(bounds.pixel_end_x, line_y)
		})
	
	# Batch draw all lines
	for line in lines:
		draw_line(line.start, line.end, line_color, _line_width)

func _draw_debug_info(bounds: Dictionary) -> void:
	# Draw grid outline
	draw_rect(Rect2(Vector2.ZERO, grid_total_size), Color.RED, false, 3.0)
	
	# Calculate font size based on zoom
	var font_size = 16.0 / _camera.zoom.x
	
	# Draw cell coordinates in visible cells
	for x in range(bounds.start_x, bounds.end_x):
		for y in range(bounds.start_y, bounds.end_y):
			var cell_center = Vector2(
				x * _cell_size + _cell_size / 2,
				y * _cell_size + _cell_size / 2
			)
			
			var cell_text = "(%d,%d)" % [x, y]
			draw_string(
				ThemeDB.fallback_font,
				cell_center - Vector2(font_size * 1.5, 0),
				cell_text,
				HORIZONTAL_ALIGNMENT_CENTER,
				-1,
				font_size,
				Color.WHITE
			)

# Public API methods

func center_grid_on_player() -> void:
	var player_ships = get_tree().get_nodes_in_group("player")
	if player_ships.is_empty():
		return
	
	var player = player_ships[0]
	if not is_instance_valid(player):
		return
	
	var grid_center = grid_total_size / 2.0
	position = player.global_position - grid_center
	_redraw_needed = true

func reset_grid() -> void:
	position = -grid_total_size / 2.0
	_redraw_needed = true

func get_cell_coords(world_position: Vector2) -> Vector2i:
	# Use GameSettings implementation if available
	if game_settings and game_settings.has_method("get_cell_coords"):
		return game_settings.get_cell_coords(world_position)
	
	# Calculate local position
	var local_pos = world_position - position
	
	# Calculate grid coordinates 
	return Vector2i(
		int(floor(local_pos.x / _cell_size)),
		int(floor(local_pos.y / _cell_size))
	)

func get_cell_position(cell_coords: Vector2i) -> Vector2:
	# Use cached positions for performance
	if _cell_world_positions.has(cell_coords):
		return position + _cell_world_positions[cell_coords]
	
	# Fallback calculation
	return position + Vector2(cell_coords.x * _cell_size, cell_coords.y * _cell_size)

func get_cell_center(cell_coords: Vector2i) -> Vector2:
	# Use cached center positions for performance
	if _cell_centers.has(cell_coords):
		return position + _cell_centers[cell_coords]
	
	# Fallback calculation
	return position + Vector2(
		cell_coords.x * _cell_size + _cell_size / 2.0,
		cell_coords.y * _cell_size + _cell_size / 2.0
	)

func is_cell_valid(cell_coords: Vector2i) -> bool:
	return (
		cell_coords.x >= 0 and 
		cell_coords.x < _grid_size and
		cell_coords.y >= 0 and
		cell_coords.y < _grid_size
	)

func set_debug_mode(enable: bool) -> void:
	if _draw_debug != enable:
		_draw_debug = enable
		_redraw_needed = true

func set_line_opacity(opacity: float) -> void:
	_opacity = clamp(opacity, 0.0, 1.0)
	_redraw_needed = true

func set_line_width(width: float) -> void:
	_line_width = max(1.0, width)
	_redraw_needed = true

func set_line_color(color: Color) -> void:
	_line_color = color
	_redraw_needed = true

func get_grid_info() -> Dictionary:
	return {
		"cell_size": _cell_size,
		"grid_size": _grid_size,
		"total_size": grid_total_size,
		"position": position
	}
