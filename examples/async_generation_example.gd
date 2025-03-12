extends Node2D
# Example of using the asynchronous generation system

# UI elements
@onready var status_label = $CanvasLayer/StatusLabel
@onready var debug_button = $CanvasLayer/DebugButton
@onready var queue_ui = $CanvasLayer/GenerationQueueUI

# Generator node - can be used for custom generation
@onready var generator_component = $AsyncGeneratorComponent
@onready var planet_field = $PlanetFieldGenerator

# Configuration
@export var test_planets_count: int = 10
@export var test_asteroids_count: int = 20

# State tracking
var generation_count = 0
var completed_count = 0
var failed_count = 0
var generation_active = false

func _ready():
	# Connect to generator signals
	generator_component.generation_completed.connect(_on_generation_completed)
	generator_component.generation_failed.connect(_on_generation_failed)
	
	# Connect to planet field signals
	planet_field.generation_started.connect(_on_field_generation_started)
	planet_field.planet_generated.connect(_on_field_planet_generated)
	planet_field.generation_completed.connect(_on_field_generation_completed)
	planet_field.sector_updated.connect(_on_sector_updated)
	
	# Connect to UI signals
	debug_button.pressed.connect(_on_debug_button_pressed)
	
	# Initial UI update
	_update_status_label()

# Update status display
func _update_status_label():
	var status_text = "Async Generation: "
	if generation_active:
		status_text += "Active\n"
	else:
		status_text += "Idle\n"
	
	status_text += "Generated: " + str(completed_count) + "/" + str(generation_count) + "\n"
	status_text += "Failed: " + str(failed_count) + "\n"
	
	if planet_field:
		var current_sector = planet_field.get_current_sector()
		status_text += "Current Sector: " + str(current_sector) + "\n"
		status_text += "Loaded Sectors: " + str(planet_field.get_loaded_sectors().size()) + "\n"
		status_text += "Pending Sectors: " + str(planet_field.get_pending_sectors().size())
	
	status_label.text = status_text

# Generate a test batch
func _generate_test_batch():
	# Reset counters
	generation_count = test_planets_count + test_asteroids_count
	completed_count = 0
	failed_count = 0
	generation_active = true
	
	# Request planets with different priorities
	for i in range(test_planets_count):
		var seed_value = randi()
		var is_gaseous = (i % 3 == 0)  # Every third planet is gaseous
		var priority = GenerationManager.Priority.NORMAL
		
		# First planets get higher priority
		if i < 3:
			priority = GenerationManager.Priority.HIGH
		elif i > test_planets_count - 3:
			priority = GenerationManager.Priority.LOW
		
		if GenerationManager:
			GenerationManager.request_planet(seed_value, is_gaseous, -1, priority)
	
	# Request asteroids
	for i in range(test_asteroids_count):
		var seed_value = randi()
		var size = AsteroidGenerator.ASTEROID_SIZE_MEDIUM
		
		# Variety of sizes
		if i % 3 == 0:
			size = AsteroidGenerator.ASTEROID_SIZE_SMALL
		elif i % 3 == 2:
			size = AsteroidGenerator.ASTEROID_SIZE_LARGE
			
		if GenerationManager:
			GenerationManager.request_asteroid(seed_value, size, GenerationManager.Priority.NORMAL)
	
	# Update status
	_update_status_label()

# Test spawning planets and asteroids with the component
func _spawn_test_objects():
	# Create planet spawner
	var planet_spawner = AsyncPlanetSpawner.new()
	planet_spawner.position = Vector2(400, 300)
	add_child(planet_spawner)
	
	# Create asteroid spawner
	var asteroid_spawner = AsyncAsteroidSpawner.new()
	asteroid_spawner.position = Vector2(600, 300)
	add_child(asteroid_spawner)
	
	# Start generation
	planet_spawner.generate_planet(randi())
	asteroid_spawner.generate_asteroid(randi())

# Signal handlers

func _on_generation_completed(result):
	completed_count += 1
	_update_status_label()
	
	if completed_count >= generation_count:
		generation_active = false

func _on_generation_failed(error):
	failed_count += 1
	print("Generation failed: ", error)
	_update_status_label()

func _on_field_generation_started(total_planets):
	generation_count = total_planets
	completed_count = 0
	failed_count = 0
	generation_active = true
	_update_status_label()

func _on_field_planet_generated(index, total):
	completed_count += 1
	_update_status_label()

func _on_field_generation_completed():
	generation_active = false
	_update_status_label()

func _on_sector_updated(sector_coords):
	_update_status_label()

func _on_debug_button_pressed():
	# Toggle between different test modes
	var debug_mode = debug_button.text
	
	if debug_mode == "Generate Batch":
		_generate_test_batch()
		debug_button.text = "Spawn Objects"
	
	elif debug_mode == "Spawn Objects":
		_spawn_test_objects()
		debug_button.text = "Clear Cache"
	
	elif debug_mode == "Clear Cache":
		if GenerationManager:
			GenerationManager.clear_cache()
		queue_ui.reset_counters()
		debug_button.text = "Generate Batch"
