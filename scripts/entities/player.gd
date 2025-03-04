# player.gd
extends RigidBody2D
class_name Player

var health_component
var combat_component
var movement_component
var resource_component
var state_machine
var camera_2d

var is_immobilized: bool = false
var respawn_timer: float = 0.0
var current_planet_id: int = -1
var last_valid_position: Vector2
var grid = null
var main = null
var current_charge: float = 0.0

var is_charging_weapon: bool = false
var weapon_swap_index: int = 0
var sound_system = null
var thruster_active = false

func _ready():
	z_index = 10
	add_to_group("player")
	
	health_component = $HealthComponent
	combat_component = $CombatComponent
	movement_component = $MovementComponent
	state_machine = $StateMachine
	camera_2d = $Camera2D
	sound_system = get_node_or_null("/root/SoundSystem")
	
	if camera_2d:
		camera_2d.zoom = Vector2.ONE
		camera_2d.position_smoothing_enabled = false
	
	last_valid_position = global_position
	grid = get_node_or_null("/root/Main/Grid")
	main = get_node_or_null("/root/Main")
	
	if health_component:
		health_component.connect("died", _on_died)
		
	if movement_component:
		movement_component.connect("position_changed", _on_position_changed)
		movement_component.connect("cell_changed", _on_cell_changed)
	
	if combat_component:
		combat_component.connect("weapon_changed", _on_weapon_changed)
		combat_component.connect("weapon_fired", _on_weapon_fired)
	
	if resource_component:
		resource_component.add_resource("energy", 100.0, 10.0)
	
	initialize_weapons()
	
	if state_machine:
		state_machine.change_state("Immobilized" if is_immobilized else "Normal")

func _process(delta):
	if camera_2d and camera_2d.zoom != Vector2.ONE:
		camera_2d.zoom = Vector2.ONE
	
	if is_immobilized:
		respawn_timer -= delta
		if respawn_timer <= 0:
			set_immobilized(false)
			
			if main and main.has_method("respawn_player_at_initial_planet"):
				main.respawn_player_at_initial_planet()
	else:
		check_planet_collision()
	
	if is_charging_weapon and combat_component:
		current_charge = combat_component.update_charge(delta)
		
	update_thruster_sound()

func _unhandled_input(event):
	if is_immobilized:
		return
	
	if event is InputEvent:
		if event.is_action_pressed("ui_accept") or event.is_action_pressed("primary_fire"):
			if combat_component:
				if combat_component.get_current_weapon_name() == "ChargeBeam":
					is_charging_weapon = combat_component.start_charging()
				else:
					shoot()
		
		elif event.is_action_released("ui_accept") or event.is_action_released("primary_fire"):
			if is_charging_weapon and combat_component:
				combat_component.release_charge()
				is_charging_weapon = false
				current_charge = 0.0
		
		elif event.is_action_pressed("weapon_next"):
			cycle_weapon(1)
		elif event.is_action_pressed("weapon_prev"):
			cycle_weapon(-1)
		
		for i in range(1, 10):
			if event.is_action_pressed("weapon_" + str(i)):
				select_weapon_by_index(i - 1)

func initialize_weapons():
	if combat_component:
		combat_component.add_weapon("StandardLaser", StandardLaser.new())
		combat_component.add_weapon("SpreadShot", SpreadShot.new())
		combat_component.add_weapon("MissileLauncher", MissileLauncher.new())
		combat_component.set_weapon("StandardLaser")

func shoot():
	if combat_component and not is_immobilized:
		var direction = Vector2.RIGHT
		if movement_component:
			direction = movement_component.facing_direction
		else:
			direction = Vector2.RIGHT.rotated(rotation)
		
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
	return health_component.take_damage(amount) if health_component else false

func set_immobilized(value: bool):
	if value == is_immobilized:
		return
		
	is_immobilized = value
	
	if value:
		respawn_timer = 5.0
		stop_thruster_sound()
		
		if state_machine and state_machine.has_state("Immobilized"):
			state_machine.change_state("Immobilized")
	else:
		respawn_timer = 0.0
		
		if state_machine and state_machine.has_state("Normal"):
			state_machine.change_state("Normal")

func check_boundaries() -> bool:
	if not grid or is_immobilized:
		return false
	
	if movement_component:
		var cell = movement_component.get_current_cell()
		
		var is_outside_grid = (
			cell.x < 0 or 
			cell.x >= int(grid.grid_size.x) or 
			cell.y < 0 or 
			cell.y >= int(grid.grid_size.y)
		)
		
		if is_outside_grid:
			if main and main.has_method("show_message"):
				main.show_message("You abandoned all logic and were lost in space!")
			
			set_immobilized(true)
			global_position = last_valid_position
			linear_velocity = Vector2.ZERO
			angular_velocity = 0.0
			
			return false
	
	last_valid_position = global_position
	return true

func check_laser_hit(laser) -> bool:
	return combat_component.check_collision(laser) if combat_component else false

func get_collision_rect() -> Rect2:
	var shape = get_node_or_null("CollisionShape2D")
	if shape and shape.shape:
		var shape_extents
		
		if shape.shape is CircleShape2D:
			shape_extents = Vector2(shape.shape.radius, shape.shape.radius)
			return Rect2(-shape_extents, shape_extents * 2)
		elif shape.shape is RectangleShape2D:
			shape_extents = shape.shape.extents
			return Rect2(-shape_extents, shape_extents * 2)
	
	var sprite = $Sprite2D
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		var scaled_size = texture_size * 0.7
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	
	return Rect2(-16, -16, 32, 32)

func check_planet_collision():
	var planet_spawner = get_node_or_null("/root/Main/PlanetSpawner")
	
	if not planet_spawner or not main:
		return
	
	var planet_positions = planet_spawner.planet_positions
	var planet_data = planet_spawner.planet_data
	
	var on_any_planet = false
	var new_planet_id = -1
	
	# Handle entering a new planet
	if new_planet_id != -1 and new_planet_id != current_planet_id:
		current_planet_id = new_planet_id
		var planet_name = planet_data[current_planet_id].name
		if main and main.has_method("show_message"):
			main.show_message("Welcome to planet " + planet_name + "!")
	
	# Handle leaving a planet
	if not on_any_planet and current_planet_id != -1:
		current_planet_id = -1

func get_current_cell() -> Vector2i:
	return Vector2i(movement_component.cell_x, movement_component.cell_y) if movement_component else Vector2i(-1, -1)

func update_thruster_sound():
	if not sound_system or is_immobilized:
		return
		
	var is_moving = movement_component and movement_component.velocity.length() > 30
	
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

func _on_died():
	var explode_component = $ExplodeFireComponent if has_node("ExplodeFireComponent") else null
	
	if explode_component and explode_component.has_method("explode"):
		explode_component.explode()
	
	stop_thruster_sound()
	
	if health_component:
		health_component.current_health = health_component.max_health
		health_component.set_invulnerable(3.0)
	
	set_immobilized(true)
	
	if main and main.has_method("show_message"):
		main.show_message("You were destroyed! Respawning...")

func _on_position_changed(_old_position, _new_position):
	check_boundaries()

func _on_cell_changed(_cell_x, _cell_y):
	pass

func _on_weapon_changed(new_weapon):
	is_charging_weapon = false
	current_charge = 0.0
	
	if combat_component:
		var weapons = combat_component.get_available_weapons()
		var index = weapons.find(new_weapon.weapon_name)
		if index >= 0:
			weapon_swap_index = index
	
	if main and main.has_method("show_message"):
		main.show_message("Weapon switched to: " + new_weapon.weapon_name)

func _on_weapon_fired(position, _direction):
	if sound_system:
		sound_system.play_laser(position)
