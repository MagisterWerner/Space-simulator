# scripts/entities/planet_spawner.gd
extends Node2D
class_name PlanetSpawner

@export var use_specific_seed: bool = false
@export var planet_seed: int = 0
@export var register_with_entity_manager: bool = true
@export var spawn_on_ready: bool = true
@export var moon_chance: int = 40
@export var max_moons: int = 2
@export var force_spawn: bool = false  # Spawn even if there are adjacent planets

var _planet_instance = null
var _planet_generation_manager = null

func _ready():
	# Wait a frame to ensure all systems are ready
	await get_tree().process_frame
	
	_planet_generation_manager = get_node_or_null("/root/PlanetGenerationManager")
	
	if spawn_on_ready:
		spawn_planet()

func spawn_planet() -> Node2D:
	# Return if planet already spawned
	if _planet_instance:
		return _planet_instance
	
	# Make sure PlanetGenerationManager exists
	if not _planet_generation_manager:
		_planet_generation_manager = get_node_or_null("/root/PlanetGenerationManager")
		if not _planet_generation_manager:
			push_error("PlanetSpawner: PlanetGenerationManager not found")
			return null
	
	# Wait for PlanetGenerationManager to be initialized
	if not _planet_generation_manager.initialized:
		await _planet_generation_manager.planet_textures_pregenerated
	
	# Get grid cell for this position
	var _grid_manager = get_node_or_null("/root/GridManager")
	if not _grid_manager:
		push_error("PlanetSpawner: GridManager not found")
		return null
	
	var cell_coords = _grid_manager.world_to_cell(global_position)
	
	# Check for adjacent planets if not forcing spawn
	if not force_spawn and not _planet_generation_manager.can_place_planet_at(cell_coords):
		push_warning("PlanetSpawner: Cannot spawn planet at %s - adjacent cells already occupied" % str(cell_coords))
		return null
	
	# Get a planet scene
	var planet_scene = load("res://scenes/world/planet.tscn")
	if not planet_scene:
		push_error("PlanetSpawner: Failed to load planet scene")
		return null
	
	# Create the planet
	_planet_instance = planet_scene.instantiate()
	
	# Get seed for this planet
	var seed_to_use = planet_seed if use_specific_seed else _get_seed_for_position()
	var planet_texture = null
	var atmosphere_texture = null
	var theme_id = 0
	var atmosphere_data = null
	
	# Try to find matching textures in the pregenerated pools
	for data in _planet_generation_manager.planet_texture_pool:
		if data.seed == seed_to_use:
			planet_texture = data.texture
			theme_id = data.theme
			break
	
	for data in _planet_generation_manager.atmosphere_texture_pool:
		if data.seed == seed_to_use:
			atmosphere_texture = data.texture
			atmosphere_data = data.data
			break
	
	# Add to scene and register with EntityManager if needed
	var _entity_manager = get_node_or_null("/root/EntityManager")
	if register_with_entity_manager and _entity_manager:
		_entity_manager.add_child(_planet_instance)
		if _entity_manager.has_method("register_entity"):
			_entity_manager.register_entity(_planet_instance, "planet")
	else:
		add_child(_planet_instance)
	
	# Position the planet
	_planet_instance.global_position = global_position
	
	# Set required properties
	_planet_instance.seed_value = seed_to_use
	_planet_instance.grid_x = cell_coords.x
	_planet_instance.grid_y = cell_coords.y
	_planet_instance.max_moons = max_moons
	_planet_instance.moon_chance = moon_chance
	
	if planet_texture:
		_planet_instance.planet_texture = planet_texture
	if atmosphere_texture:
		_planet_instance.atmosphere_texture = atmosphere_texture
	if theme_id:
		_planet_instance.theme_id = theme_id
	if atmosphere_data:
		_planet_instance.atmosphere_data = atmosphere_data
	
	# Register with PlanetGenerationManager
	_planet_generation_manager.placed_planets[cell_coords] = _planet_instance
	if not _planet_generation_manager.occupied_cells.has(cell_coords):
		_planet_generation_manager.occupied_cells.append(cell_coords)
	
	# Emit signal through PlanetGenerationManager
	_planet_generation_manager.planet_spawned.emit(_planet_instance, cell_coords)
	
	return _planet_instance

func _get_seed_for_position() -> int:
	# Generate a deterministic seed based on grid position
	var _grid_manager = get_node_or_null("/root/GridManager")
	if not _grid_manager:
		return randi()
		
	var cell_coords = _grid_manager.world_to_cell(global_position)
	
	var _seed_manager = get_node_or_null("/root/SeedManager")
	if _seed_manager and _seed_manager.has_method("get_random_int"):
		return _seed_manager.get_random_int(cell_coords.x * 1000 + cell_coords.y, 1, 1000000)
	else:
		return hash("planet" + str(cell_coords.x) + "_" + str(cell_coords.y)) % 1000000

func get_planet() -> Node2D:
	return _planet_instance

func despawn_planet() -> void:
	if _planet_instance:
		# Unregister from PlanetGenerationManager
		if _planet_generation_manager:
			var _grid_manager = get_node_or_null("/root/GridManager")
			if _grid_manager:
				var cell_coords = _grid_manager.world_to_cell(_planet_instance.global_position)
				_planet_generation_manager.placed_planets.erase(cell_coords)
				
				var index = _planet_generation_manager.occupied_cells.find(cell_coords)
				if index >= 0:
					_planet_generation_manager.occupied_cells.remove_at(index)
		
		# Remove the planet
		_planet_instance.queue_free()
		_planet_instance = null
