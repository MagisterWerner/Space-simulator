# autoload/seed_manager.gd
#
# SeedManager Singleton
# ====================
# Purpose:
#   Manages the procedural generation seed used throughout the game.
#   Ensures consistent and reproducible random generation for all game elements.
#
# Interface:
#   - Seed Management: set_seed(), set_random_seed(), get_seed()
#   - Random Generation: get_random_value(), get_random_int(), get_random_point_in_circle()
#   - Array Operations: get_random_element(), get_shuffled_array()
#   - Signals: seed_changed
#
# Usage:
#   Access via the SeedManager autoload:
#   ```
#   # Set a specific seed
#   SeedManager.set_seed(12345)
#
#   # Get a random value that will always be the same for a given object ID and seed
#   var random_value = SeedManager.get_random_value(asteroid_id, 0.0, 100.0)
#
#   # Get a random point in a circle for spawning
#   var spawn_position = SeedManager.get_random_point_in_circle(entity_id, 500.0)
#   ```
#
extends Node
class_name SeedManagerSingleton

signal seed_changed(new_seed)

# Seed properties
var current_seed: int = 0
var rng: RandomNumberGenerator = RandomNumberGenerator.new()
var seed_hash: String = ""

# Generation history for debugging
var generation_history: Array = []
var max_history_size: int = 100
var debug_mode: bool = false

func _ready() -> void:
	# Initialize with a random seed if none is set
	if current_seed == 0:
		set_random_seed()
	
	# Connect to game start signal
	Events.game_started.connect(_on_game_started)

func _on_game_started() -> void:
	# Optional: Generate a new seed when starting a new game
	# Uncomment if you want a new seed for each game session
	# set_random_seed()
	pass

func set_seed(new_seed: int) -> void:
	# Store the old seed for history
	if current_seed != 0 and current_seed != new_seed:
		_add_to_history("Changed seed", current_seed, new_seed)
	
	current_seed = new_seed
	rng.seed = current_seed
	
	# Create a seed hash for saving/loading
	seed_hash = _generate_seed_hash(current_seed)
	
	# Notify all systems that depend on the seed
	seed_changed.emit(current_seed)
	print("Seed set to: %s (hash: %s)" % [current_seed, seed_hash])

func set_random_seed() -> void:
	# Generate a new random seed
	randomize()
	var new_seed = randi()
	set_seed(new_seed)

func get_seed() -> int:
	return current_seed

func get_seed_hash() -> String:
	return seed_hash

# Get a consistent random value between min and max for a given object ID
func get_random_value(object_id: int, min_val: float, max_val: float) -> float:
	# Create a deterministic random value based on the seed and object ID
	var hash_seed = _hash_combine(current_seed, object_id)
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	var result = min_val + temp_rng.randf() * (max_val - min_val)
	
	if debug_mode:
		_add_to_history("Random value", {
			"object_id": object_id,
			"min": min_val,
			"max": max_val,
			"result": result
		})
	
	return result

# Get a random integer in a given range for an object
func get_random_int(object_id: int, min_val: int, max_val: int) -> int:
	var hash_seed = _hash_combine(current_seed, object_id)
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	return temp_rng.randi_range(min_val, max_val)

# Get a random point in a circle with given radius
func get_random_point_in_circle(object_id: int, radius: float) -> Vector2:
	var hash_seed = _hash_combine(current_seed, object_id)
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	var angle = temp_rng.randf() * TAU  # Random angle in radians (0 to 2π)
	var distance = sqrt(temp_rng.randf()) * radius  # Square root for uniform distribution
	
	return Vector2(cos(angle) * distance, sin(angle) * distance)

# Get a random element from an array
func get_random_element(object_id: int, array: Array):
	if array.is_empty():
		return null
	
	var index = get_random_int(object_id, 0, array.size() - 1)
	return array[index]

# Shuffle an array deterministically based on an object ID
func get_shuffled_array(object_id: int, original_array: Array) -> Array:
	# Create a copy to avoid modifying the original
	var array = original_array.duplicate()
	
	var hash_seed = _hash_combine(current_seed, object_id)
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = hash_seed
	
	# Fisher-Yates shuffle
	for i in range(array.size() - 1, 0, -1):
		var j = temp_rng.randi_range(0, i)
		var temp = array[i]
		array[i] = array[j]
		array[j] = temp
	
	return array

# Generate a noise value at a position (for terrain generation, etc.)
func get_noise_value(object_id: int, position: Vector2) -> float:
	# This is a simple hash-based noise function
	var x_hash = _hash_combine(current_seed, int(position.x * 1000) + object_id)
	var y_hash = _hash_combine(current_seed, int(position.y * 1000) + object_id)
	
	var temp_rng = RandomNumberGenerator.new()
	temp_rng.seed = x_hash ^ y_hash
	
	return temp_rng.randf()

# Generate a random spawn position within a rectangular area
func get_random_position_in_rect(object_id: int, rect: Rect2) -> Vector2:
	var x = get_random_value(object_id * 2, rect.position.x, rect.position.x + rect.size.x)
	var y = get_random_value(object_id * 2 + 1, rect.position.y, rect.position.y + rect.size.y)
	return Vector2(x, y)

# Generate a consistent asteroid field based on seed
func generate_asteroid_field(center: Vector2, radius: float, count: int, center_clearance: float = 100.0) -> Array:
	var positions = []
	
	for i in range(count):
		var object_id = _hash_combine(current_seed, i)
		var pos = get_random_point_in_circle(object_id, radius)
		pos += center
		
		# Ensure asteroids aren't too close to the center
		var distance_to_center = pos.distance_to(center)
		if distance_to_center < center_clearance:
			# Move the asteroid outward
			var direction = (pos - center).normalized()
			pos = center + direction * center_clearance
		
		positions.append(pos)
	
	return positions

# Helper function to combine seed and object ID into a new hash
func _hash_combine(seed_value: int, object_id: int) -> int:
	return ((seed_value << 5) + seed_value) ^ object_id

# Generate a readable hash string from the seed
func _generate_seed_hash(seed_value: int) -> String:
	# Convert to a 6-character alphanumeric hash
	var characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # Omitting similar characters
	var hash_string = ""
	var temp_seed = seed_value
	
	for i in range(6):
		var index = temp_seed % characters.length()
		hash_string += characters[index]
		# Fix for integer division warning - explicitly convert to float for division
		temp_seed = int(temp_seed / float(characters.length()))
	
	return hash_string

# Add an entry to the generation history for debugging
func _add_to_history(action: String, data_old, data_new = null) -> void:
	if not debug_mode:
		return
	
	generation_history.append({
		"time": Time.get_ticks_msec(),
		"action": action,
		"old_data": data_old,
		"new_data": data_new
	})
	
	# Limit history size
	if generation_history.size() > max_history_size:
		generation_history.pop_front()

# Enable or disable debug mode
func set_debug_mode(enabled: bool) -> void:
	debug_mode = enabled
	if enabled:
		print("SeedManager debug mode enabled")
	else:
		generation_history.clear()

# Clear the generation history
func clear_history() -> void:
	generation_history.clear()
