# scripts/generators/generator_service.gd
# Abstract base class for all generators
class_name GeneratorService
extends RefCounted

var _seed_value: int = 0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func _init(seed_value: int = 0) -> void:
	_seed_value = seed_value
	_rng.seed = seed_value

# Get a deterministic random value
func get_random_value(object_id: int, min_val: float, max_val: float, sub_id: int = 0) -> float:
	if Engine.has_singleton("SeedManager"):
		return SeedManager.get_random_value(object_id, min_val, max_val, sub_id)
	else:
		# Fallback if SeedManager not available
		_rng.seed = _seed_value + object_id + (sub_id * 1000)
		return min_val + _rng.randf() * (max_val - min_val)

# Get a deterministic random integer
func get_random_int(object_id: int, min_val: int, max_val: int, sub_id: int = 0) -> int:
	if Engine.has_singleton("SeedManager"):
		return SeedManager.get_random_int(object_id, min_val, max_val, sub_id)
	else:
		# Fallback if SeedManager not available
		_rng.seed = _seed_value + object_id + (sub_id * 1000)
		return _rng.randi_range(min_val, max_val)

# Generate method to be overridden by subclasses
func generate() -> Resource:
	push_error("GeneratorService: generate() method must be overridden")
	return null


# scripts/generators/background_generation_worker.gd
# Handles background generation of world content
class_name BackgroundGenerationWorker
extends Node

signal cell_generated(cell: Vector2i)
signal generation_completed
signal generation_progress(progress: float)

# References
var _world_data: WorldData = null
var _generators: Dictionary = {}
var _generation_thread: Thread = null
var _generation_mutex: Mutex = Mutex.new()
var _quit_thread: bool = false

# Generation queue and state
var _cells_to_generate: Array[Vector2i] = []
var _cells_completed: int = 0
var _total_cells: int = 0
var _prioritized_cells: Dictionary = {}

# Initialize with world data and generators
func initialize(world_data: WorldData, generators: Dictionary) -> void:
	_world_data = world_data
	_generators = generators

# Start background generation
func start_generation(cells: Array[Vector2i], priority_cells: Array[Vector2i] = []) -> void:
	if _generation_thread and _generation_thread.is_started():
		push_error("BackgroundGenerationWorker: Thread already running")
		return
	
	# Reset state
	_cells_to_generate = cells.duplicate()
	_cells_completed = 0
	_total_cells = cells.size()
	_quit_thread = false
	
	# Setup priority cells
	_prioritized_cells.clear()
	var priority = 10
	for cell in priority_cells:
		_prioritized_cells[cell] = priority
		priority -= 1
		if priority < 1:
			priority = 1
	
	# Sort cells by priority (high to low)
	_sort_cells_by_priority()
	
	# Start the thread
	_generation_thread = Thread.new()
	_generation_thread.start(_generation_thread_function)

# Sort cells by priority
func _sort_cells_by_priority() -> void:
	_cells_to_generate.sort_custom(func(a, b):
		var priority_a = _prioritized_cells.get(a, 0)
		var priority_b = _prioritized_cells.get(b, 0)
		return priority_a > priority_b
	)

# Main thread function
func _generation_thread_function() -> void:
	while not _quit_thread:
		var cell = _get_next_cell_to_generate()
		if cell == null:
			break
		
		# Generate the cell
		_generate_cell(cell)
		
		# Update progress
		_cells_completed += 1
		call_deferred("_emit_progress")
	
	# Signal completion
	call_deferred("_emit_completion")

# Emit progress update
func _emit_progress() -> void:
	var progress = float(_cells_completed) / _total_cells if _total_cells > 0 else 1.0
	generation_progress.emit(progress)

# Emit completion signal
func _emit_completion() -> void:
	generation_completed.emit()

# Get next cell to generate with thread safety
func _get_next_cell_to_generate() -> Vector2i:
	_generation_mutex.lock()
	var cell = null
	if not _cells_to_generate.is_empty():
		cell = _cells_to_generate.pop_front()
	_generation_mutex.unlock()
	return cell

# Generate content for a cell
func _generate_cell(cell: Vector2i) -> void:
	# Skip if already generated
	if _world_data.is_cell_generated(cell):
		return
	
	# Generate planets
	if _generators.has("planet"):
		var planet_generator = _generators["planet"]
		var planets_per_cell = 1  # Adjust as needed
		
		for i in range(planets_per_cell):
			# Use cell and index to create deterministic entity ID
			var entity_id = (cell.x * 1000 + cell.y) * 100 + i
			
			# Generate planet only if seeded RNG determines we should
			if SeedManager.get_random_bool(entity_id, 0.3):  # 30% chance
				var planet_data = planet_generator.generate_planet_at_cell(cell, entity_id)
				
				# Add to world data with thread safety
				_generation_mutex.lock()
				_world_data.add_entity(planet_data)
				_generation_mutex.unlock()
	
	# Generate asteroid fields
	if _generators.has("asteroid"):
		var asteroid_generator = _generators["asteroid"]
		var fields_per_cell = 1  # Adjust as needed
		
		for i in range(fields_per_cell):
			# Use cell and index to create deterministic entity ID
			var entity_id = (cell.x * 1000 + cell.y) * 100 + 50 + i
			
			# Generate field only if seeded RNG determines we should
			if SeedManager.get_random_bool(entity_id, 0.2):  # 20% chance
				var field_data = asteroid_generator.generate_field_at_cell(cell, entity_id)
				
				# Add to world data with thread safety
				_generation_mutex.lock()
				_world_data.add_entity(field_data)
				_generation_mutex.unlock()
	
	# Mark cell as generated
	_generation_mutex.lock()
	_world_data.mark_cell_generated(cell)
	_generation_mutex.unlock()
	
	# Signal completion for this cell
	call_deferred("_emit_cell_generated", cell)

# Emit cell generation completion
func _emit_cell_generated(cell: Vector2i) -> void:
	cell_generated.emit(cell)

# Stop thread gracefully
func stop() -> void:
	if _generation_thread and _generation_thread.is_started():
		_quit_thread = true
		_generation_thread.wait_to_finish()

# Clean up
func _exit_tree() -> void:
	stop()
