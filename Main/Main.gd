class_name BlueNoiseWorldGenerator
extends WorldGenerator

@onready var asteroid_sizes = [Globals.scene_asteroid_large, Globals.scene_asteroid_medium, Globals.scene_asteroid_small]
@export var asteroid_density := 3 # (int, 10)

@export var player1_spawn = Vector2(0, 0)
@export var capital_ship = Vector2(3, 1)
@export var planet_arid = Vector2(-1, -1)
@export var planet_frozen = Vector2(-1, 1)
@export var planet_humid = Vector2(1, -1)
@export var planet_volcanic = Vector2(1, 1)
@onready var object_positions = [player1_spawn, capital_ship, planet_arid, planet_frozen, planet_humid, planet_volcanic]

@export var debug_grid = false
@export var debug_color: Color

@export var sector_margin_proportion := 0.1
@export var subsector_margin_proportion := 0.1

@onready var _subsector_grid_width: int = ceil(sqrt(asteroid_density))
@onready var _subsector_count := _subsector_grid_width * _subsector_grid_width

@onready var _sector_margin := sector_size * sector_margin_proportion
@onready var _subsector_base_size := (sector_size - _sector_margin * 2) / _subsector_grid_width
@onready var _subsector_margin := _subsector_base_size * subsector_margin_proportion
@onready var _subsector_size := _subsector_base_size - _subsector_margin * 2

@onready var _grid_drawer := $GridDrawer

####################################################################################################

func _ready() -> void:
	if Globals.first_run == true:
		Globals.first_run = false
		generate()
		_grid_drawer.setup(sector_size, sector_axis_count)
		_grid_drawer.visible = debug_grid
		_grid_drawer.grid_color = debug_color


### This function generated all the sectors in the world.
func _generate_sector(x_id: int, y_id: int) -> void:
	_rng.seed = make_seed_for(x_id, y_id)
	seed(_rng.seed)

	var sector_top_left := Vector2(
		x_id * sector_size - _half_sector_size + _sector_margin,
		y_id * sector_size - _half_sector_size + _sector_margin
	)

	var sector_data := []
	var sector_indices = range(_subsector_count)
	sector_indices.shuffle()


### Add the correct number of asteroids to each sector but ignore sectors with planets and players.
	if not Vector2(x_id, y_id) in object_positions:
		for i in range(asteroid_density):
			var x := int(sector_indices[i] / _subsector_grid_width)
			var y: int = sector_indices[i] - x * _subsector_grid_width

			var spawn_asteroid = asteroid_sizes[_rng.randi() % asteroid_sizes.size()]
			var asteroid = spawn_asteroid.instantiate()
			ObjectRegistry._asteroids.add_child(asteroid)
			asteroid.position = _generate_random_position(Vector2(x, y), sector_top_left)
			asteroid.rotation = _rng.randf_range(-PI, PI)
			asteroid.scale *= _rng.randf_range(0.2, 1.0)
			sector_data.append(asteroid)

	elif Vector2(x_id, y_id) in object_positions:
### Add the homeplanets to the grid by instancing them within a given sector.
		if Vector2(x_id, y_id) == planet_arid:
			var _object = Globals.PlanetArid.instantiate()
			add_child(_object)
			_object.position = Vector2(x_id * sector_size, y_id * sector_size)
		elif Vector2(x_id, y_id) == planet_frozen:
			var _object = Globals.PlanetFrozen.instantiate()
			add_child(_object)
			_object.position = Vector2(x_id * sector_size, y_id * sector_size)
		elif Vector2(x_id, y_id) == planet_humid:
			var _object = Globals.PlanetHumid.instantiate()
			add_child(_object)
			_object.position = Vector2(x_id * sector_size, y_id * sector_size)
		elif Vector2(x_id, y_id) == planet_volcanic:
			var _object = Globals.PlanetVolcanic.instantiate()
			add_child(_object)
			_object.position = Vector2(x_id * sector_size, y_id * sector_size)
		elif Vector2(x_id, y_id) == capital_ship:
			var _object = Globals.CapitalShip.instantiate()
			add_child(_object)
			_object.position = Vector2(x_id * sector_size, y_id * sector_size)

	_sectors[Vector2(x_id, y_id)] = sector_data

### This function generates subsectors within each sector for proper asteroid placement
func _generate_random_position(subsector_coordinates: Vector2, sector_top_left: Vector2) -> Vector2:
	var subsector_top_left := (
		sector_top_left
		+ Vector2(_subsector_base_size, _subsector_base_size) * subsector_coordinates
		+ Vector2(_subsector_margin, _subsector_margin)
	)
	var subsector_bottom_right := subsector_top_left + Vector2(_subsector_size, _subsector_size)
	return Vector2(
		_rng.randf_range(subsector_top_left.x, subsector_bottom_right.x),
		_rng.randf_range(subsector_top_left.y, subsector_bottom_right.y)
	)
