extends Node2D
class_name Player

# Component references
var health_component
var combat_component
var movement_component
var state_machine

# Player-specific properties
var is_immobilized: bool = false
var respawn_timer: float = 0.0
var current_planet_id: int = -1
var last_valid_position: Vector2
var grid = null
var main = null

func _ready():
	# Set basic properties
	z_index = 10
	add_to_group("player")
	
	# Get component references 
	health_component = $HealthComponent
	combat_component = $CombatComponent
	movement_component = $MovementComponent
	state_machine = $StateMachine
	
	# Store initial position
	last_valid_position = global_position
	
	# Get references to commonly used nodes
	grid = get_node_or_null("/root/Main/Grid")
	main = get_node_or_null("/root/Main")
	
	# Connect signals
	if health_component:
		health_component.connect("died", _on_died)
		
	if movement_component:
		movement_component.connect("position_changed", _on_position_changed)
		movement_component.connect("cell_changed", _on_cell_changed)
	
	# Initialize state machine
	if state_machine:
		if is_immobilized:
			state_machine.change_state("Immobilized")
		else:
			state_machine.change_state("Normal")

func _process(delta):
	# Update respawn timer if immobilized
	if is_immobilized:
		respawn_timer -= delta
		if respawn_timer <= 0:
			set_immobilized(false)
			
			# Respawn at initial planet
			if main and main.has_method("respawn_player_at_initial_planet"):
				main.respawn_player_at_initial_planet()
	
	# Only check for planet collision if not immobilized
	if not is_immobilized:
		check_planet_collision()

func shoot():
	if combat_component and not is_immobilized:
		# Get the facing direction either from movement component or sprite
		var direction = Vector2.RIGHT
		if movement_component:
			direction = movement_component.facing_direction
		
		combat_component.fire(direction)

func take_damage(amount: float) -> bool:
	if health_component:
		return health_component.take_damage(amount)
	return false

func set_immobilized(value: bool):
	if value == is_immobilized:
		return
		
	is_immobilized = value
	
	if value:
		# Immobilize
		respawn_timer = 5.0
		
		# Change state to immobilized
		if state_machine and state_machine.has_state("Immobilized"):
			state_machine.change_state("Immobilized")
	else:
		# Restore movement
		respawn_timer = 0.0
		
		# Change state to normal
		if state_machine and state_machine.has_state("Normal"):
			state_machine.change_state("Normal")

func check_boundaries() -> bool:
	if not grid or is_immobilized:
		return false
	
	if movement_component:
		var cell = movement_component.get_current_cell()
		
		# Check if outside grid
		var is_outside_grid = (
			cell.x < 0 or 
			cell.x >= int(grid.grid_size.x) or 
			cell.y < 0 or 
			cell.y >= int(grid.grid_size.y)
		)
		
		if is_outside_grid:
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

func check_laser_hit(laser) -> bool:
	if combat_component:
		return combat_component.check_collision(laser)
	return false

func get_collision_rect() -> Rect2:
	var sprite = $Sprite2D
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		# Make the collision rect a bit smaller than the sprite
		var scaled_size = texture_size * 0.7
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	else:
		# Fallback collision rect
		return Rect2(-16, -16, 32, 32)

func check_planet_collision():
	var planet_spawner = get_node_or_null("/root/Main/PlanetSpawner")
	
	if not planet_spawner or not main:
		return
	
	var planet_positions = planet_spawner.planet_positions
	var planet_data = planet_spawner.planet_data
	var sprites = planet_spawner.planet_sprites
	
	var player_radius = 16
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

func get_current_cell() -> Vector2i:
	if movement_component:
		return Vector2i(movement_component.cell_x, movement_component.cell_y)
	return Vector2i(-1, -1)

# Signal handlers
func _on_died():
	# Reset health
	if health_component:
		health_component.current_health = health_component.max_health
		health_component.set_invulnerable(3.0)
	
	# Immobilize the player
	set_immobilized(true)
	
	# Show message about death
	if main and main.has_method("show_message"):
		main.show_message("You were destroyed! Respawning...")

func _on_position_changed(_old_position, _new_position):
	# Check boundaries after position change
	check_boundaries()

func _on_cell_changed(_cell_x, _cell_y):
	# Additional logic when player changes cells
	pass
