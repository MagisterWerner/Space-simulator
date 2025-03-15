extends Node
class_name WorldCoordinator

signal world_ready
signal player_ready
signal cell_ready(cell_coords)

# Key managers
var world_simulation: WorldSimulation = null
var world_generator: WorldGenerator = null
var game_manager = null
var entity_manager = null
var resource_manager = null
var seed_manager = null
var grid_manager = null

# Initialization state
var _ready_for_game: bool = false
var _managers_initialized: bool = false
var _debug_mode: bool = false

# Current world data
var world_data: WorldData = null

func _ready() -> void:
	# Add to coordinator group
	add_to_group("world_coordinator")
	
	# Check game settings for debug mode
	var main_scene = get_tree().current_scene
	var game_settings = main_scene.get_node_or_null("GameSettings")
	if game_settings:
		_debug_mode = game_settings.debug_mode
	
	# Defer initialization to ensure all autoloads are ready
	call_deferred("_initialize_managers")

func _initialize_managers() -> void:
	# Find all required managers
	game_manager = get_node_or_null("/root/GameManager")
	entity_manager = get_node_or_null("/root/EntityManager")
	resource_manager = get_node_or_null("/root/ResourceManager")
	grid_manager = get_node_or_null("/root/GridManager")
	seed_manager = get_node_or_null("/root/SeedManager")
	
	# Find or create world simulation
	world_simulation = get_node_or_null("/root/WorldSimulation")
	if not world_simulation:
		var world_sims = get_tree().get_nodes_in_group("world_simulation")
		if not world_sims.is_empty():
			world_simulation = world_sims[0]
		else:
			# Create a new world simulation
			world_simulation = WorldSimulation.new()
			world_simulation.name = "WorldSimulation"
			add_child(world_simulation)
	
	# Find or create world generator
	world_generator = get_node_or_null("/root/WorldGenerator")
	if not world_generator:
		var generators = get_tree().get_nodes_in_group("world_generator")
		if not generators.is_empty():
			world_generator = generators[0]
		else:
			# Create a new world generator
			world_generator = WorldGenerator.new()
			world_generator.name = "WorldGenerator"
			add_child(world_generator)
	
	# Connect to signals
	_connect_signals()
	
	_managers_initialized = true
	
	if _debug_mode:
		print("WorldCoordinator: Managers initialized")

func _connect_signals() -> void:
	# World simulation signals
	if world_simulation:
		if not world_simulation.is_connected("world_loaded", _on_world_loaded):
			world_simulation.connect("world_loaded", _on_world_loaded)
		
		if not world_simulation.is_connected("entity_spawned", _on_entity_spawned):
			world_simulation.connect("entity_spawned", _on_entity_spawned)
		
		if not world_simulation.is_connected("entity_despawned", _on_entity_despawned):
			world_simulation.connect("entity_despawned", _on_entity_despawned)
		
		if not world_simulation.is_connected("cell_loaded", _on_cell_loaded):
			world_simulation.connect("cell_loaded", _on_cell_loaded)
	
	# World generator signals
	if world_generator and world_generator.has_signal("world_generation_completed"):
		if not world_generator.is_connected("world_generation_completed", _on_world_generation_completed):
			world_generator.connect("world_generation_completed", _on_world_generation_completed)
	
	# Entity manager signals
	if entity_manager:
		if not entity_manager.is_connected("player_spawned", _on_player_spawned):
			entity_manager.connect("player_spawned", _on_player_spawned)
	
	# Grid manager signals
	if grid_manager and grid_manager.has_signal("player_cell_changed"):
		if not grid_manager.is_connected("player_cell_changed", _on_player_cell_changed):
			grid_manager.connect("player_cell_changed", _on_player_cell_changed)

func _on_world_loaded() -> void:
	if _debug_mode:
		print("WorldCoordinator: World loaded")
	
	_ready_for_game = true
	world_ready.emit()

func _on_world_generation_completed() -> void:
	if _debug_mode:
		print("WorldCoordinator: World generation completed")

func _on_entity_spawned(entity, entity_data) -> void:
	# Make sure entity is registered with entity manager
	if entity_manager:
		# Use entity data to register if available
		if entity_data:
			entity_manager.register_entity_with_data(entity, entity_data)
		else:
			# Determine entity type
			var entity_type = "generic"
			if entity.has_meta("entity_type"):
				entity_type = entity.get_meta("entity_type")
			
			entity_manager.register_entity(entity, entity_type)

func _on_entity_despawned(entity, entity_data) -> void:
	# Make sure entity is deregistered from entity manager
	if entity_manager and is_instance_valid(entity):
		entity_manager.deregister_entity(entity)

func _on_player_spawned(player) -> void:
	if _debug_mode:
		print("WorldCoordinator: Player spawned")
	
	player_ready.emit()

func _on_cell_loaded(cell_coords) -> void:
	cell_ready.emit(cell_coords)

func _on_player_cell_changed(old_cell, new_cell) -> void:
	# This is handled by world simulation directly
	pass

# PUBLIC API

# Generate a new world
func generate_world(seed_value: int = 0) -> WorldData:
	if not _managers_initialized:
		await get_tree().process_frame
		_initialize_managers()
	
	if _debug_mode:
		print("WorldCoordinator: Generating new world with seed " + str(seed_value))
	
	# Update seed manager if available
	if seed_manager:
		seed_manager.set_seed(seed_value)
	
	# Generate world data
	world_data = world_generator.generate_world_data(seed_value)
	
	return world_data

# Load a world
func load_world(data: WorldData = null) -> bool:
	if not _managers_initialized:
		await get_tree().process_frame
		_initialize_managers()
	
	if not data and not world_data:
		push_error("WorldCoordinator: No world data available")
		return false
	
	if not data:
		data = world_data
	else:
		world_data = data
	
	if _debug_mode:
		print("WorldCoordinator: Loading world into simulation")
	
	# Load world data into simulation
	if world_simulation:
		return world_simulation.load_world(data)
	
	return false

# Create and load a world with a specific seed
func create_and_load_world(seed_value: int = 0) -> bool:
	if not _managers_initialized:
		await get_tree().process_frame
		_initialize_managers()
	
	# Generate the world
	var data = await generate_world(seed_value)
	
	# Load the generated world
	return load_world(data)

# Save current world state
func save_world_state(filepath: String = "user://world.save") -> Error:
	if not world_simulation or not world_data:
		push_error("WorldCoordinator: Cannot save - no active world")
		return ERR_UNCONFIGURED
	
	if _debug_mode:
		print("WorldCoordinator: Saving world state to " + filepath)
	
	# Update world data from simulation
	if world_simulation.has_method("_update_world_data_from_entities"):
		world_simulation._update_world_data_from_entities()
	
	# Save to file
	return world_data.save_to_file(filepath)

# Load world state from file
func load_world_state(filepath: String = "user://world.save") -> Error:
	if not world_simulation:
		push_error("WorldCoordinator: Cannot load - no world simulation")
		return ERR_UNCONFIGURED
	
	if _debug_mode:
		print("WorldCoordinator: Loading world state from " + filepath)
	
	# Load from file
	var data = WorldData.load_from_file(filepath)
	if not data:
		push_error("WorldCoordinator: Failed to load world data from file")
		return ERR_FILE_CANT_READ
	
	# Store the data
	world_data = data
	
	# Update seed
	if seed_manager:
		seed_manager.set_seed(data.seed_value)
	
	# Load into simulation
	if not world_simulation.load_world(data):
		push_error("WorldCoordinator: Failed to load world into simulation")
		return ERR_CANT_CREATE
	
	return OK

# Get world data
func get_world_data() -> WorldData:
	return world_data

# Update world data with current state
func update_world_data() -> void:
	if world_simulation and world_data:
		if world_simulation.has_method("_update_world_data_from_entities"):
			world_simulation._update_world_data_from_entities()

# Reset world state
func reset_world() -> void:
	if not world_simulation:
		return
	
	# Clear all cells
	var loaded_cells = world_simulation.loaded_cells.keys()
	for cell in loaded_cells:
		world_simulation.unload_cell(cell)
	
	# Reset world data
	world_data = null
	
	_ready_for_game = false

# Get entities in a specific cell
func get_entities_in_cell(cell_coords: Vector2i) -> Array:
	if world_simulation:
		return world_simulation.get_entities_in_cell(cell_coords)
	return []

# Force load a specific cell
func load_cell(cell_coords: Vector2i) -> void:
	if world_simulation:
		world_simulation.load_cell(cell_coords)

# Check if a cell is loaded
func is_cell_loaded(cell_coords: Vector2i) -> bool:
	if world_simulation:
		return world_simulation.is_cell_loaded(cell_coords)
	return false

# Is world ready for game to start?
func is_world_ready() -> bool:
	return _ready_for_game
