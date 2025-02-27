extends Node2D

@export var movement_speed = 300
@export var max_health = 100
@export var fire_cooldown = 0.5  # Seconds between shots

# Track previous position for cell change detection
var previous_cell_x = -1
var previous_cell_y = -1

# Planet detection variables
var current_planet_id = -1  # Track which planet we're currently on, if any
var planet_entered = false  # Flag to track when we've entered a planet

# Boundary detection variables
var is_immobilized = false
var respawn_timer = 0.0
var was_in_boundary_cell = false
var was_outside_grid = false
var last_valid_position = Vector2.ZERO

# Combat variables
var current_health = max_health
var current_cooldown = 0.0
var laser_scene = preload("res://laser.tscn")
var is_invulnerable = false  # Used for temporary invulnerability after taking damage
var invulnerability_timer = 0.0  # Timer for invulnerability duration

func _ready():
	# Set a high z-index to ensure the player is drawn on top of all other objects
	z_index = 10
	
	# Add a camera if one doesn't exist
	if not has_node("Camera2D"):
		var camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.current = true
		add_child(camera)
		print("Player ready at position: ", global_position)
	
	# Set up the sprite if it doesn't exist
	if not has_node("Sprite2D"):
		var sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		sprite.texture = load("res://sprites/ships_player/player_ship_1.png")
		add_child(sprite)
		print("Added player sprite")
	
	# Initialize health
	current_health = max_health
	
	# Initialize previous cell position
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		previous_cell_x = int(floor(global_position.x / grid.cell_size.x))
		previous_cell_y = int(floor(global_position.y / grid.cell_size.y))
		
		# Initialize last valid position
		last_valid_position = global_position
		
		print("Player initialized at cell: (", previous_cell_x, ", ", previous_cell_y, ")")

func _process(delta):
	# Handle player movement
	handle_movement(delta)
	
	# Check for grid cell changes
	check_grid_position()
	
	# Check for planet collision
	check_planet_collision()
	
	# Update shooting cooldown
	if current_cooldown > 0:
		current_cooldown -= delta
	
	# Handle shooting input
	if Input.is_action_pressed("ui_accept") and current_cooldown <= 0 and not is_immobilized:
		shoot()
	
	# Update invulnerability timer
	if is_invulnerable:
		invulnerability_timer -= delta
		if invulnerability_timer <= 0:
			is_invulnerable = false
	
	# Visual feedback for invulnerability
	if has_node("Sprite2D"):
		var sprite = get_node("Sprite2D")
		sprite.modulate.a = 0.5 if is_invulnerable else 1.0

func handle_movement(delta):
	# Prevent movement if immobilized
	if is_immobilized:
		respawn_timer -= delta
		if respawn_timer <= 0:
			var main = get_node_or_null("/root/Main")
			if main and main.has_method("respawn_player_at_initial_planet"):
				is_immobilized = false
				movement_speed = 300
				main.respawn_player_at_initial_planet()
		return
	
	# Immediate direction calculation
	var direction = Vector2(
		Input.get_axis("ui_left", "ui_right"),
		Input.get_axis("ui_up", "ui_down")
	)
	
	# Normalize and move in a single frame
	if direction.length() > 0:
		direction = direction.normalized()
		var movement = direction * movement_speed * delta
		
		# Store current position before moving
		var old_position = global_position
		
		# Immediate position update
		global_position += movement
		
		# Strict boundary check after movement
		if not check_boundaries():
			# Revert to previous position if outside grid
			global_position = old_position
		
		# Update sprite rotation to face movement direction
		if has_node("Sprite2D") and direction.length() > 0:
			# Calculate the angle in radians, adjust for Godot's coordinate system
			var angle = direction.angle()
			get_node("Sprite2D").rotation = angle

func check_grid_position():
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		var current_cell_x = int(floor(global_position.x / grid.cell_size.x))
		var current_cell_y = int(floor(global_position.y / grid.cell_size.y))
		
		# Check if player moved to a new cell
		if current_cell_x != previous_cell_x or current_cell_y != previous_cell_y:
			print("Player moved to new cell: (", current_cell_x, ",", current_cell_y, ")")
			grid.update_loaded_chunks(current_cell_x, current_cell_y)
			
			# Update previous cell position
			previous_cell_x = current_cell_x
			previous_cell_y = current_cell_y

# Check collision with planets
func check_planet_collision():
	var planet_spawner = get_node_or_null("/root/Main/PlanetSpawner")
	var main = get_node_or_null("/root/Main")
	
	if not planet_spawner or not main:
		return
	
	var planet_positions = planet_spawner.planet_positions
	var planet_data = planet_spawner.planet_data
	var sprites = planet_spawner.planet_sprites
	
	var player_radius = 16  # Approximate player radius
	var on_any_planet = false
	var new_planet_id = -1
	
	# Check collision with each planet
	for i in range(planet_positions.size()):
		var planet_pos = planet_positions[i].position
		var planet = planet_data[i]
		
		# Skip if planet sprite index is invalid
		if planet.sprite_idx >= sprites.size():
			continue
			
		# Get the sprite for this planet
		var sprite = sprites[planet.sprite_idx]
		if not sprite:
			continue
			
		# Get the radius of the planet (half the width or height, scaled)
		var sprite_size = sprite.get_size()
		var planet_radius = max(sprite_size.x, sprite_size.y) * planet.scale / 2
		
		# Calculate distance between player and planet centers
		var distance = global_position.distance_to(planet_pos)
		
		# Check if player is within the planet's radius
		if distance < planet_radius + player_radius * 0.5:
			on_any_planet = true
			new_planet_id = i
			break
	
	# Handle entering a new planet
	if new_planet_id != -1 and new_planet_id != current_planet_id:
		current_planet_id = new_planet_id
		# Get the planet name and show welcome message
		var planet_name = planet_data[current_planet_id].name
		if main.has_method("show_message"):
			main.show_message("Welcome to planet " + planet_name + "!")
	
	# Handle leaving a planet
	if not on_any_planet and current_planet_id != -1:
		current_planet_id = -1

# Returns true if the player is in a valid position, false otherwise
func check_boundaries():
	var grid = get_node_or_null("/root/Main/Grid")
	if not grid:
		return true
	
	# Prevent multiple immobilization attempts
	if is_immobilized:
		return false
	
	# Precise cell coordinate calculation
	var cell_x = int(floor(global_position.x / grid.cell_size.x))
	var cell_y = int(floor(global_position.y / grid.cell_size.y))
	
	# Precise grid size as integers
	var grid_width = int(grid.grid_size.x)
	var grid_height = int(grid.grid_size.y)
	
	# Detailed boundary checks
	var is_left_exit = cell_x < 0
	var is_right_exit = cell_x >= grid_width
	var is_top_exit = cell_y < 0
	var is_bottom_exit = cell_y >= grid_height
	
	# Combine all exit conditions
	var is_outside_grid = is_left_exit or is_right_exit or is_top_exit or is_bottom_exit
	
	# If outside grid, always immobilize
	if is_outside_grid:
		# Detailed exit direction logging
		var exit_direction = ""
		if is_left_exit:
			exit_direction = "LEFT"
		elif is_right_exit:
			exit_direction = "RIGHT"
		elif is_top_exit:
			exit_direction = "TOP"
		elif is_bottom_exit:
			exit_direction = "BOTTOM"
		
		print("CRITICAL: Player Attempting Grid Exit")
		print("  Exit Direction: ", exit_direction)
		print("  Current Position: ", global_position)
		print("  Cell Coordinates: (", cell_x, ", ", cell_y, ")")
		
		# Show immobilization message
		var main = get_tree().current_scene
		if main and main.has_method("show_message"):
			main.show_message("You abandoned all logic and were lost in space!")
		
		# Ensure immobilization works for ALL exits
		set_immobilized(true)
		respawn_timer = 5.0  # Full 5-second wait
		
		# Always revert to last valid position
		global_position = last_valid_position
		
		return false
	
	# Position tracking only when not immobilized
	last_valid_position = global_position
	
	return true

# Method to completely immobilize the player
func set_immobilized(value):
	# Ensure atomic state change
	if value and not is_immobilized:
		is_immobilized = true
		movement_speed = 0
		respawn_timer = 5.0
		print("Player immobilized with full 5-second timer")
	elif not value:
		is_immobilized = false
		movement_speed = 300
		respawn_timer = 0.0
		print("Player movement restored")

# Shooting function
func shoot():
	# Create the laser instance
	var laser = laser_scene.instantiate()
	
	# Set position slightly in front of the player's facing direction
	var spawn_offset = Vector2.RIGHT.rotated(get_node("Sprite2D").rotation) * 30
	laser.global_position = global_position + spawn_offset
	
	# Set direction based on player's rotation
	laser.direction = Vector2.RIGHT.rotated(get_node("Sprite2D").rotation)
	laser.rotation = get_node("Sprite2D").rotation
	
	# Configure the laser
	laser.is_player_laser = true
	laser.damage = 25
	
	# Change laser color for player
	var sprite = laser.get_node("Sprite2D")
	if sprite:
		sprite.texture = load("res://sprites/weapons/laser_blue.png")
	
	# Add laser to scene
	get_tree().current_scene.add_child(laser)
	
	# Reset cooldown
	current_cooldown = fire_cooldown
	
	print("Player fired laser")

# Take damage from enemy or other source
func take_damage(amount):
	# No damage if invulnerable
	if is_invulnerable:
		return
	
	# Apply damage
	current_health -= amount
	print("Player took", amount, "damage. Health:", current_health)
	
	# Check for death
	if current_health <= 0:
		die()
	else:
		# Set temporary invulnerability
		is_invulnerable = true
		invulnerability_timer = 1.0  # 1 second of invulnerability
		
		# Visual feedback
		if has_node("Sprite2D"):
			var sprite = get_node("Sprite2D")
			var tween = create_tween()
			tween.tween_property(sprite, "modulate", Color.RED, 0.1)
			tween.tween_property(sprite, "modulate", Color.WHITE, 0.1)

# Death function
func die():
	print("Player died")
	
	# Reset health
	current_health = max_health
	
	# Set temporary invulnerability
	is_invulnerable = true
	invulnerability_timer = 3.0  # 3 seconds of invulnerability after respawn
	
	# Immobilize the player
	set_immobilized(true)
	
	# Show message about death
	var main = get_tree().current_scene
	if main and main.has_method("show_message"):
		main.show_message("You were destroyed! Respawning...")
	
	# Respawn will be handled by the normal respawn timer

# Method to update cell position (called from main.gd)
func update_cell_position(cell_x, cell_y):
	previous_cell_x = cell_x
	previous_cell_y = cell_y
	print("Player cell position initialized to: (", cell_x, ",", cell_y, ")")
	
	# Force grid update when cell position is set
	var grid = get_node_or_null("/root/Main/Grid")
	if grid:
		grid.update_loaded_chunks(cell_x, cell_y)

# Check if a laser has hit this player
func check_laser_hit(laser):
	# Skip if player is invulnerable
	if is_invulnerable:
		return false
	
	# Only enemy lasers can hit the player
	if laser.is_player_laser:
		return false
	
	# Get collision shapes
	var player_rect = get_collision_rect()
	var laser_rect = laser.get_collision_rect()
	
	# Offset to global coordinates
	player_rect.position += global_position
	laser_rect.position += laser.global_position
	
	# Check for intersection
	return player_rect.intersects(laser_rect)

# Get player collision rectangle for hit detection
func get_collision_rect():
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		# Make the collision rect a bit smaller than the sprite for better gameplay
		var scaled_size = texture_size * 0.7
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	else:
		# Fallback collision rect if no sprite
		return Rect2(-16, -16, 32, 32)

func _draw():
	# Only draw if the sprite is missing
	if not has_node("Sprite2D"):
		# Draw the player as an orange square (fallback)
		var rect = Rect2(-16, -16, 32, 32)
		draw_rect(rect, Color(1.0, 0.5, 0.0, 1.0))
		
		# Add a white border
		draw_rect(rect, Color.WHITE, false, 2.0)
