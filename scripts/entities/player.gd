extends Node2D
class_name Player

# Component references
var health_component
var combat_component
var movement_component
var resource_component
var state_machine
var camera_2d

# Player-specific properties
var is_immobilized: bool = false
var respawn_timer: float = 0.0
var current_planet_id: int = -1
var last_valid_position: Vector2
var grid = null
var main = null
var current_charge: float = 0.0

# Weapon handling properties
var is_charging_weapon: bool = false
var weapon_swap_index: int = 0  # For cycling through weapons

# Sound system reference
var sound_system = null
var thruster_active = false

func _ready():
	# Set basic properties
	z_index = 10
	add_to_group("player")
	
	# Get component references 
	health_component = $HealthComponent
	combat_component = $CombatComponent
	movement_component = $MovementComponent
	resource_component = $ResourceComponent
	state_machine = $StateMachine
	camera_2d = $Camera2D
	
	# Get sound system reference
	sound_system = get_node_or_null("/root/SoundSystem")
	
	# IMPORTANT: Ensure the camera has zoom exactly 1.0 to avoid scaling
	if camera_2d:
		camera_2d.zoom = Vector2.ONE
		# Disable smoothing to avoid interpolation issues
		camera_2d.position_smoothing_enabled = false
	
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
	
	if combat_component:
		combat_component.connect("weapon_changed", _on_weapon_changed)
		combat_component.connect("weapon_fired", _on_weapon_fired)
	
	# Initialize resource component if available
	if resource_component:
		# Add energy resource
		resource_component.add_resource("energy", 100.0, 10.0)  # 100 max, 10 regen per second
	
	# Initialize weapons
	initialize_weapons()
	
	# Initialize state machine
	if state_machine:
		if is_immobilized:
			state_machine.change_state("Immobilized")
		else:
			state_machine.change_state("Normal")

func _process(delta):
	# Ensure camera zoom is always set to 1.0
	if camera_2d and camera_2d.zoom != Vector2.ONE:
		camera_2d.zoom = Vector2.ONE
	
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
	
	# Handle weapon charging if button is held
	if is_charging_weapon and combat_component:
		current_charge = combat_component.update_charge(delta)
		
	# Update thruster sound based on movement
	update_thruster_sound()

func _unhandled_input(event):
	# Skip if immobilized
	if is_immobilized:
		return
	
	# Weapon firing controls
	if event is InputEvent:
		# Fire weapon on primary fire button pressed
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("primary_fire"):
			if combat_component:
				# Start charging if this is a chargeable weapon
				var current_weapon = combat_component.get_current_weapon_name()
				if current_weapon == "ChargeBeam":
					is_charging_weapon = combat_component.start_charging()
				else:
					shoot()
		
		# Release charged weapon when button released
		elif event.is_action_released("ui_accept") or event.is_action_released("primary_fire"):
			if is_charging_weapon and combat_component:
				combat_component.release_charge()
				is_charging_weapon = false
				current_charge = 0.0
		
		# Cycle through weapons with Z and X keys
		elif event.is_action_pressed("weapon_next"):
			cycle_weapon(1)
		elif event.is_action_pressed("weapon_prev"):
			cycle_weapon(-1)
		
		# Direct weapon selection with number keys
		for i in range(1, 10):
			if event.is_action_pressed("weapon_" + str(i)):
				select_weapon_by_index(i - 1)

func initialize_weapons():
	if combat_component:
		# Add all available weapon types
		combat_component.add_weapon("StandardLaser", StandardLaser.new())
		combat_component.add_weapon("SpreadShot", SpreadShot.new())
		combat_component.add_weapon("MissileLauncher", MissileLauncher.new())
		
		# Set initial weapon
		combat_component.set_weapon("StandardLaser")

func shoot():
	if combat_component and not is_immobilized:
		# Get the facing direction either from movement component or sprite
		var direction = Vector2.RIGHT
		if movement_component:
			direction = movement_component.facing_direction
		else:
			# If no movement component, use sprite rotation
			var sprite = get_node_or_null("Sprite2D")
			if sprite:
				direction = Vector2.RIGHT.rotated(sprite.rotation)
		
		combat_component.fire(direction)

func cycle_weapon(direction: int):
	if combat_component:
		var weapons = combat_component.get_available_weapons()
		if weapons.size() <= 1:
			return
			
		weapon_swap_index = (weapon_swap_index + direction) % weapons.size()
		if weapon_swap_index < 0:
			weapon_swap_index = weapons.size() - 1
			
		combat_component.set_weapon(weapons[weapon_swap_index])

func select_weapon_by_index(index: int):
	if combat_component:
		var weapons = combat_component.get_available_weapons()
		if index >= 0 and index < weapons.size():
			weapon_swap_index = index
			combat_component.set_weapon(weapons[index])

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
		
		# Stop thruster sound if active
		stop_thruster_sound()
		
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
	
	var player_radius = 16
	var on_any_planet = false
	var new_planet_id = -1
	
	# Check collision with each planet
	for i in range(planet_positions.size()):
		var planet_pos = planet_positions[i].position
		var planet = planet_data[i]
		
		# Calculate distance between player and planet centers
		var distance = global_position.distance_to(planet_pos)
	
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

# Sound-related methods
func update_thruster_sound():
	if not sound_system or is_immobilized:
		return
		
	# Check if player is moving
	var is_moving = false
	if movement_component:
		is_moving = movement_component.velocity.length() > 0
	
	# Start or stop thruster sound based on movement
	if is_moving and not thruster_active:
		start_thruster_sound()
	elif not is_moving and thruster_active:
		stop_thruster_sound()

func start_thruster_sound():
	if sound_system:
		sound_system.start_thruster(get_instance_id())
		thruster_active = true

func stop_thruster_sound():
	if sound_system:
		sound_system.stop_thruster(get_instance_id())
		thruster_active = false

# Signal handlers
func _on_died():
	# Stop thruster sound
	stop_thruster_sound()
	
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
	# Cell change logic is handled by the grid
	pass

func _on_weapon_changed(new_weapon):
	# Stop charging if weapon changed
	is_charging_weapon = false
	current_charge = 0.0
	
	# Update weapon swap index to match new weapon
	if combat_component:
		var weapons = combat_component.get_available_weapons()
		var index = weapons.find(new_weapon.weapon_name)
		if index >= 0:
			weapon_swap_index = index
	
	# Show message about new weapon
	if main and main.has_method("show_message"):
		main.show_message("Weapon switched to: " + new_weapon.weapon_name)

func _on_weapon_fired(position, direction):
	# Play laser sound when weapon is fired
	if sound_system:
		sound_system.play_laser(position)
