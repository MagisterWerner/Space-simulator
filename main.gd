# main.gd
extends Node2D

@onready var grid = $Grid
@onready var seed_label = $CanvasLayer/SeedLabel
@onready var message_label = $CanvasLayer/MessageLabel
@onready var enemy_spawner = $EnemySpawner
@onready var planet_spawner = $PlanetSpawner
@onready var asteroid_spawner = $AsteroidSpawner

const MESSAGE_DURATION = 3.0
var message_timer = 0.0

var initial_planet_position = null
var initial_planet_cell_x = -1
var initial_planet_cell_y = -1
var player = null
var previous_key_states = {}

func _ready():
	scale = Vector2.ONE
	grid.scale = Vector2.ONE
	
	for i in range(10):
		previous_key_states[KEY_0 + i] = false
	
	update_seed_label()
	call_deferred("initialize_world")

func initialize_world():
	grid.regenerate()
	await get_tree().process_frame
	
	if planet_spawner and planet_spawner.has_method("generate_planets"):
		planet_spawner.generate_planets()
	await get_tree().process_frame
	
	if asteroid_spawner and asteroid_spawner.has_method("generate_asteroids"):
		asteroid_spawner.generate_asteroids()
	await get_tree().process_frame
	
	create_player()
	await get_tree().process_frame
	
	if enemy_spawner and enemy_spawner.has_method("spawn_enemies"):
		enemy_spawner.spawn_enemies()
	force_grid_update()

func _process(delta):
	scale = Vector2.ONE
	grid.scale = Vector2.ONE
	
	handle_seed_key_input()
	handle_random_seed_input()
	manage_message_timer(delta)
	queue_redraw()

func handle_seed_key_input():
	for i in range(10):
		var key_code = KEY_0 + i
		var key_pressed = Input.is_physical_key_pressed(key_code)
		
		if key_pressed and not previous_key_states[key_code]:
			grid.set_seed(i)
			update_seed_label()
			create_player()
			enemy_spawner.reset_enemies()
		
		previous_key_states[key_code] = key_pressed

func handle_random_seed_input():
	if Input.is_action_just_pressed("ui_accept"):
		var rng = RandomNumberGenerator.new()
		rng.randomize()
		var new_seed = rng.randi_range(1, 9999)
		
		grid.set_seed(new_seed)
		update_seed_label()
		create_player()
		if enemy_spawner and enemy_spawner.has_method("reset_enemies"):
			enemy_spawner.reset_enemies()
		
		show_message("Generated new random seed: %s" % new_seed)

func manage_message_timer(delta):
	if message_timer > 0:
		message_timer -= delta
		if message_timer <= 0:
			hide_message()

func update_seed_label():
	seed_label.text = "Current Seed: %s" % grid.seed_value

func show_message(text):
	message_label.text = text
	message_label.visible = true
	message_timer = MESSAGE_DURATION

func hide_message():
	message_label.visible = false

func respawn_player_at_initial_planet():
	if not player or not initial_planet_position:
		place_player_at_random_planet()
		return
	
	if player.has_method("set_immobilized"):
		player.set_immobilized(false)
		
	var movement = player.get_node_or_null("MovementComponent")
	if movement:
		if movement.has_method("set_speed"):
			movement.set_speed(300)
		else:
			movement.speed = 300
	
	player.global_position = initial_planet_position
	player.last_valid_position = initial_planet_position
	
	if player is RigidBody2D:
		player.linear_velocity = Vector2.ZERO
		player.angular_velocity = 0.0
		player.freeze = false
	
	if "is_immobilized" in player:
		player.is_immobilized = false
	if "respawn_timer" in player:
		player.respawn_timer = 0.0
	if "was_in_boundary_cell" in player:
		player.was_in_boundary_cell = false
	if "was_outside_grid" in player:
		player.was_outside_grid = false
	
	grid.current_player_cell_x = -999
	grid.current_player_cell_y = -999
	grid.update_loaded_chunks(initial_planet_cell_x, initial_planet_cell_y)
	grid.queue_redraw()
	
	grid.player_immobilized = false
	grid.was_outside_grid = false
	grid.was_in_boundary_cell = false
	grid.respawn_timer = 0.0
	
	if asteroid_spawner and asteroid_spawner.has_method("draw_asteroids"):
		asteroid_spawner.draw_asteroids(grid, grid.loaded_cells)
	
	if enemy_spawner and enemy_spawner.has_method("initialize_enemy_visibility"):
		enemy_spawner.initialize_enemy_visibility()
	
	var planet_name = get_planet_name(initial_planet_cell_x, initial_planet_cell_y)
	show_message("You have been rescued and returned to planet %s." % planet_name)
	
	call_deferred("force_grid_update")

func place_player_at_random_planet():
	if not player:
		return
	
	grid.queue_redraw()
	var planet_positions = get_planet_positions()
	
	if planet_positions.size() > 0:
		var rng = RandomNumberGenerator.new()
		rng.seed = grid.seed_value
		var chosen_planet = planet_positions[rng.randi() % planet_positions.size()]
		
		player.global_position = chosen_planet.position
		
		if player is RigidBody2D:
			player.linear_velocity = Vector2.ZERO
			player.angular_velocity = 0.0
		
		initial_planet_position = chosen_planet.position
		initial_planet_cell_x = chosen_planet.grid_x
		initial_planet_cell_y = chosen_planet.grid_y
		
		var cell_x = int(floor(player.global_position.x / grid.cell_size.x))
		var cell_y = int(floor(player.global_position.y / grid.cell_size.y))
		
		grid.current_player_cell_x = -1
		grid.current_player_cell_y = -1
		grid.update_loaded_chunks(cell_x, cell_y)
		
		var planet_name = get_planet_name(chosen_planet.grid_x, chosen_planet.grid_y)
		show_message("Welcome to planet %s!" % planet_name)
		
		await get_tree().create_timer(0.1).timeout
		force_grid_update()
	else:
		var center = Vector2(
			grid.grid_size.x * grid.cell_size.x / 2,
			grid.grid_size.y * grid.cell_size.y / 2
		)
		player.global_position = center
		
		if player is RigidBody2D:
			player.linear_velocity = Vector2.ZERO
			player.angular_velocity = 0.0
		
		initial_planet_position = center
		initial_planet_cell_x = int(floor(center.x / grid.cell_size.x))
		initial_planet_cell_y = int(floor(center.y / grid.cell_size.y))
		
		var cell_x = int(floor(center.x / grid.cell_size.x))
		var cell_y = int(floor(center.y / grid.cell_size.y))
		
		grid.current_player_cell_x = -1
		grid.current_player_cell_y = -1
		grid.update_loaded_chunks(cell_x, cell_y)
		
		await get_tree().create_timer(0.1).timeout
		force_grid_update()

func create_player():
	if has_node("Player"):
		player = get_node("Player")
		call_deferred("place_player_at_random_planet")
		return
	
	call_deferred("_deferred_create_player")

func _deferred_create_player():
	if not ResourceLoader.exists("res://player.tscn") and not ResourceLoader.exists("res://scenes/player.tscn"):
		push_error("ERROR: Player scene not found")
		return
		
	var player_scene_path = "res://player.tscn"
	if not ResourceLoader.exists(player_scene_path):
		player_scene_path = "res://scenes/player.tscn"
		
	var player_scene = load(player_scene_path)
	player = player_scene.instantiate()
	
	if not player.get_script():
		if ResourceLoader.exists("res://player.gd"):
			var player_script = load("res://player.gd")
			player.set_script(player_script)
		elif ResourceLoader.exists("res://scripts/entities/player.gd"):
			var player_script = load("res://scripts/entities/player.gd")
			player.set_script(player_script)
	
	player.scale = Vector2.ONE
	
	if player.has_node("Camera2D"):
		player.get_node("Camera2D").zoom = Vector2.ONE
	
	if player is RigidBody2D:
		player.gravity_scale = 0.0
		player.linear_damp = 0.1
		player.angular_damp = 1.0
		player.can_sleep = false
	
	add_child(player)
	player.global_position = Vector2(100, 100)
	player.name = "Player"
	
	call_deferred("place_player_at_random_planet")

func get_planet_positions():
	if planet_spawner:
		if planet_spawner.has_method("get_all_planet_positions"):
			return planet_spawner.get_all_planet_positions()
		elif "planet_positions" in planet_spawner:
			return planet_spawner.planet_positions
	return []

func get_planet_name(x, y):
	if planet_spawner and planet_spawner.has_method("get_planet_name"):
		return planet_spawner.get_planet_name(x, y)
	
	var consonants = ["b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "r", "s", "t", "v", "z"]
	var vowels = ["a", "e", "i", "o", "u"]
	
	var rng = RandomNumberGenerator.new()
	rng.seed = grid.seed_value + (x * 100) + y
	
	var name = ""
	name += consonants[rng.randi() % consonants.size()].to_upper()
	name += vowels[rng.randi() % vowels.size()]
	name += consonants[rng.randi() % consonants.size()]
	name += vowels[rng.randi() % vowels.size()]

	if rng.randi() % 2 == 0:
		name += "-"
		name += consonants[rng.randi() % consonants.size()].to_upper()
		name += vowels[rng.randi() % vowels.size()]
	else:
		name += " " + str((x + y) % 9 + 1)

	return name
	
func force_grid_update():
	if not player or not grid:
		return
		
	var cell_x = int(floor(player.global_position.x / grid.cell_size.x))
	var cell_y = int(floor(player.global_position.y / grid.cell_size.y))
 
	grid.current_player_cell_x = -1
	grid.current_player_cell_y = -1
	grid.update_loaded_chunks(cell_x, cell_y)
	grid.queue_redraw()
