# scripts/managers/content_registry.gd
# Central cache for all generated content
extends Node
class_name ContentRegistry

signal content_loaded
signal content_cache_updated(content_type)
signal texture_cache_updated

# World data reference
var world_data: WorldData = null

# Texture caches
var texture_cache: Dictionary = {
	"planets": {
		"terran": {},
		"gaseous": {}
	},
	"moons": {
		"rocky": {},
		"icy": {},
		"volcanic": {}
	},
	"asteroids": {},
	"atmospheres": {}
}

# Fragment pattern cache
var fragment_patterns: Dictionary = {}

# Entity template cache for faster instantiation
var entity_templates: Dictionary = {}

# Generation status tracking
var _generation_status: Dictionary = {
	"initialized": false,
	"generating": false,
	"progress": 0.0
}

# Generator services - these produce only data, not entities
var _generators: Dictionary = {}

# Background worker for async generation
var _background_worker: BackgroundGenerationWorker = null

# Debug flag
var _debug_mode: bool = false

# Initialize the registry
func initialize(world_seed: int, debug: bool = false) -> void:
	_debug_mode = debug
	
	if _debug_mode:
		print("ContentRegistry: Initializing with seed ", world_seed)
	
	# Create world data if needed
	if not world_data:
		world_data = WorldData.new()
		world_data.seed_value = world_seed
		world_data.seed_hash = SeedManager.get_seed_hash()
		world_data.generation_timestamp = Time.get_unix_time_from_system()
	
	# Initialize generators
	_initialize_generators(world_seed)
	
	# Setup background worker
	_background_worker = BackgroundGenerationWorker.new()
	add_child(_background_worker)
	_background_worker.initialize(world_data, _generators)
	
	# Connect signals
	_background_worker.connect("cell_generated", _on_cell_generated)
	_background_worker.connect("generation_completed", _on_generation_completed)
	_background_worker.connect("generation_progress", _on_generation_progress)
	
	_generation_status.initialized = true
	content_loaded.emit()

# Initialize all generators
func _initialize_generators(seed_value: int) -> void:
	# Create generators for different content types
	if ResourceLoader.exists("res://scripts/generators/planet_data_generator.gd"):
		var PlanetGeneratorClass = load("res://scripts/generators/planet_data_generator.gd")
		_generators["planet"] = PlanetGeneratorClass.new(seed_value)
	
	if ResourceLoader.exists("res://scripts/generators/asteroid_data_generator.gd"):
		var AsteroidGeneratorClass = load("res://scripts/generators/asteroid_data_generator.gd")
		_generators["asteroid"] = AsteroidGeneratorClass.new(seed_value)
	
	if ResourceLoader.exists("res://scripts/generators/fragment_pattern_generator.gd"):
		var FragmentGeneratorClass = load("res://scripts/generators/fragment_pattern_generator.gd")
		_generators["fragment"] = FragmentGeneratorClass.new(seed_value)
		
		# Generate fragment patterns
		fragment_patterns = _generators["fragment"].generate_pattern_collection(seed_value)

# Start background generation for a set of cells
func start_background_generation(cells_to_generate: Array[Vector2i], priority_cells: Array[Vector2i] = []) -> void:
	if not _generation_status.initialized:
		push_error("ContentRegistry: Not initialized, cannot start generation")
		return
	
	if _generation_status.generating:
		if _debug_mode:
			print("ContentRegistry: Generation already in progress")
		return
	
	_generation_status.generating = true
	_generation_status.progress = 0.0
	
	# Start the background worker
	_background_worker.start_generation(cells_to_generate, priority_cells)

# Get content for a specific cell
func get_cell_content(cell: Vector2i) -> Array:
	if not world_data:
		return []
	
	# If cell not generated, trigger generation
	if not world_data.is_cell_generated(cell):
		# Add to queue but don't wait
		world_data.generation_queue.append(cell)
		return []
	
	return world_data.get_entities_in_cell(cell)

# Get a specific entity by ID
func get_entity(entity_id: int) -> EntityData:
	if not world_data:
		return null
	
	return world_data.get_entity_by_id(entity_id)

# Get planet texture - centralized to ensure caching
func get_planet_texture(planet_data: PlanetData) -> Texture2D:
	var category_name = "gaseous" if planet_data.is_gaseous else "terran"
	var cache_key = str(planet_data.seed_value) + "_" + str(planet_data.planet_theme)
	
	# Check cache first
	if texture_cache.planets[category_name].has(cache_key):
		return texture_cache.planets[category_name][cache_key]
	
	# Not in cache, generate it
	var texture: Texture2D = null
	
	if _generators.has("planet"):
		# Delegate to generator to create texture only
		texture = _generators["planet"].generate_planet_texture(planet_data)
		
		# Cache the result
		texture_cache.planets[category_name][cache_key] = texture
		texture_cache_updated.emit()
	
	return texture

# Get asteroid texture with caching
func get_asteroid_texture(asteroid_data: AsteroidData) -> Texture2D:
	var cache_key = str(asteroid_data.texture_seed) + "_" + str(asteroid_data.variant)
	
	# Check cache first
	if texture_cache.asteroids.has(cache_key):
		return texture_cache.asteroids[cache_key]
	
	# Not in cache, generate it
	var texture: Texture2D = null
	
	if _generators.has("asteroid"):
		# Delegate to generator to create texture only
		texture = _generators["asteroid"].generate_asteroid_texture(asteroid_data)
		
		# Cache the result
		texture_cache.asteroids[cache_key] = texture
		texture_cache_updated.emit()
	
	return texture

# Get fragment pattern for asteroid
func get_fragment_pattern(asteroid_data: AsteroidData) -> FragmentPatternData:
	# Skip if small (doesn't fragment)
	if asteroid_data.size_category == AsteroidData.SizeCategory.SMALL:
		return null
	
	# Convert size to string for lookup
	var size_string = "medium"
	if asteroid_data.size_category == AsteroidData.SizeCategory.LARGE:
		size_string = "large"
	
	# Find matching patterns
	var matching_patterns = []
	for pattern in fragment_patterns.values():
		if pattern.source_size == size_string:
			matching_patterns.append(pattern)
	
	# No patterns found
	if matching_patterns.is_empty():
		return null
	
	# Use variant to select pattern
	var index = asteroid_data.variant % matching_patterns.size()
	return matching_patterns[index]

# Event handlers
func _on_cell_generated(cell: Vector2i) -> void:
	if _debug_mode:
		print("ContentRegistry: Cell generated: ", cell)
	
	content_cache_updated.emit("cell")

func _on_generation_completed() -> void:
	_generation_status.generating = false
	_generation_status.progress = 1.0
	
	if _debug_mode:
		print("ContentRegistry: Background generation completed")

func _on_generation_progress(progress: float) -> void:
	_generation_status.progress = progress

# Get generation status
func get_generation_status() -> Dictionary:
	return _generation_status

# Clear all caches
func clear_caches() -> void:
	texture_cache.planets.terran.clear()
	texture_cache.planets.gaseous.clear()
	texture_cache.moons.rocky.clear()
	texture_cache.moons.icy.clear()
	texture_cache.moons.volcanic.clear()
	texture_cache.asteroids.clear()
	texture_cache.atmospheres.clear()
	texture_cache_updated.emit()
