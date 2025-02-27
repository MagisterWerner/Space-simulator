# scripts/entities/player.gd
extends Node2D

# Components will be accessed via onready variables
@onready var entity_component = $EntityComponent
@onready var state_machine = $StateMachine

# Player-specific properties
var is_immobilized: bool = false
var respawn_timer: float = 0.0
var current_planet_id: int = -1
var cell_x: int = -1
var cell_y: int = -1
var last_valid_position: Vector2 = Vector2.ZERO

# --- Cached nodes ---
var grid: Node2D
var main: Node2D

# Signals
signal cell_changed(new_x, new_y)
signal health_changed(current, maximum)

func _ready():
	# Set player-specific properties
	z_index = 10  # Ensure player is drawn on top
	add_to_group("player")
	
	# Get references to commonly used nodes
	grid = get_node_or_null("/root/Main/Grid")
	main = get_node_or_null("/root/Main")
	
	# Store initial position as the last valid position
	last_valid_position = global_position
	
	# Ensure camera exists
	if not has_node("Camera2D"):
		var camera = Camera2D.new()
		camera.name = "Camera2D"
		camera.current = true
		add_child(camera)
	
	# Ensure sprite exists
	if not has_node("Sprite2D"):
		var sprite = Sprite2D.new()
		sprite.name = "Sprite2D"
		sprite.texture = load("res://sprites/ships_player/player_ship_1.png")
		add_child(sprite)
	
	# Calculate initial cell position
	update_cell_position()
	
	# Initialize state machine
	if state_machine:
		# Start in normal state unless immobilized
		if is_immobilized:
			state_machine.change_state("Immobilized")
		else:
			state_machine.change_state("Normal")
	
	print("Player initialized at position: ", global_position)

func _process(delta):
	# Process player-specific logic (state machine handles movement)
	
	# Update visual feedback for invulnerability
	if has_node("Sprite2D") and entity_component:
		var sprite = get_node("Sprite2D")
		sprite.modulate.a = 0.5 if entity_component.is_invulnerable else 1.0
	
	# Update health bar
	update_health_bar()
	
	# Only check for planet collision if not immobilized
	if not is_immobilized:
		check_planet_collision()
	
	# Update respawn timer if immobilized
	if is_immobilized:
		respawn_timer -= delta
		if respawn_timer <= 0:
			set_immobilized(false)
			# Respawn at initial planet
			if main and main.has_method("respawn_player_at_initial_planet"):
				main.respawn_player_at_initial_planet()

# Public method to take damage (delegates to component)
func take_damage(amount):
	if entity_component:
		entity_component.take_damage(amount)
		emit_signal("health_changed", entity_component.current_health, entity_component.max_health)

# Callback when entity component dies
func on_death():
	print("Player died")
	
	# Reset health
	if entity_component:
		entity_component.current_health = entity_component.max_health
		emit_signal("health_changed", entity_component.current_health, entity_component.max_health)
	
	# Set temporary invulnerability
	if entity_component:
		entity_component.is_invulnerable = true
		entity_component.invulnerability_timer = 3.0  # 3 seconds of invulnerability after respawn
	
	# Immobilize the player
	set_immobilized(true)
	
	# Show message about death
	if main and main.has_method("show_message"):
		main.show_message("You were destroyed! Respawning...")

# Player-specific shooting method 
func shoot():
	if entity_component and entity_component.current_cooldown <= 0 and not is_immobilized:
		# Get the current facing direction
		var facing_direction = Vector2.RIGHT
		if has_node("Sprite2D"):
			facing_direction = Vector2.RIGHT.rotated(get_node("Sprite2D").rotation)
		
		# Use the component to shoot
		entity_component.shoot(global_position, facing_direction, true, 25.0)

# Method to completely immobilize the player
func set_immobilized(value):
	# Only change state if it's actually changing
	if value != is_immobilized:
		is_immobilized = value
		
		if value:
			# Immobilize
			respawn_timer = 5.0
			print("Player immobilized with 5-second timer")
			
			# Change state to immobilized if state machine exists
			if state_machine and state_machine.has_state("Immobilized"):
				state_machine.change_state("Immobilized")
		else:
			# Restore movement
			respawn_timer = 0.0
			print("Player movement restored")
			
			# Change state to normal if state machine exists
			if state_machine and state_machine.has_state("Normal"):
				state_machine.change_state("Normal")

# Update the player's cell position and emit signal if changed
func update_cell_position():
	if grid:
		var new_cell_x = int(floor(global_position.x / grid.cell_size.x))
		var new_cell_y = int(floor(global_position.y / grid.cell_size.y))
		
		if new_cell_x != cell_x or new_cell_y != cell_y:
			cell_x = new_cell_x
			cell_y = new_cell_y
			
			# Emit signal about cell change
			emit_signal("cell_changed", cell_x, cell_y)
			print("Player moved to new cell: (", cell_x, ",", cell_y, ")")
			
			# Update loaded chunks in the grid
			if grid:
				grid.update_loaded_chunks(cell_x, cell_y)
			
			return true
	
	return false

# Check if a laser has hit this player (delegates to component)
func check_laser_hit(laser):
	if entity_component:
		return entity_component.check_laser_hit(laser, get_collision_rect(), true)
	return false

# Get collision rectangle for hit detection
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

# Check if the player is in a valid position, returns true if valid
func check_boundaries():
	if not grid:
		return true
	
	# Skip if already immobilized
	if is_immobilized:
		return false
	
	# Convert grid size to integers
	var grid_width = int(grid.grid_size.x)
	var grid_height = int(grid.grid_size.y)
	
	# Check if outside grid
	var is_outside_grid = cell_x < 0 or cell_x >= grid_width or cell_y < 0 or cell_y >= grid_height
	
	# Handle being outside grid
	if is_outside_grid:
		print("CRITICAL: Player attempted to leave grid at: ", global_position)
		
		# Show message
		if main and main.has_method("show_message"):
			main.show_message("You abandoned all logic and were lost in space!")
		
		# Immobilize the player
		set_immobilized(true)
		
		# Revert to last valid position
		global_position = last_valid_position
		
		return false
	
	# We're in a valid position
	last_valid_position = global_position
	return true

# Check collision with planets
func check_planet_collision():
	var planet_spawner = get_node_or_null("/root/Main/PlanetSpawner")
	
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
			
		# Get the radius of the planet
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
		if main and main.has_method("show_message"):
			main.show_message("Welcome to planet " + planet_name + "!")
	
	# Handle leaving a planet
	if not on_any_planet and current_planet_id != -1:
		current_planet_id = -1

# Update the health bar position and size based on current health
func update_health_bar():
	var health_bar = get_node_or_null("HealthBar")
	if health_bar and entity_component:
		# Update width based on current health percentage
		var health_percent = float(entity_component.current_health) / entity_component.max_health
		health_bar.size.x = 40 * health_percent
		
		# Center the health bar
		health_bar.position.x = -20
