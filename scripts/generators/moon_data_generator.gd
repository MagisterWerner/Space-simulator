extends RefCounted
class_name MoonDataGenerator

# Moon type enum
enum MoonType {
	ROCKY,
	ICY,
	VOLCANIC
}

# Moon size constants
const MOON_SIZES = {
	MoonType.ROCKY: [32, 40, 48],
	MoonType.ICY: [36, 44, 52],
	MoonType.VOLCANIC: [28, 36, 44]
}

# Name prefixes based on moon type
const NAME_PREFIXES = {
	MoonType.ROCKY: ["Rocky", "Stone", "Barren", "Dust", "Crater", "Desolate"],
	MoonType.ICY: ["Frozen", "Icy", "Frost", "Glacial", "Crystal", "Rime"],
	MoonType.VOLCANIC: ["Molten", "Magma", "Cinder", "Ash", "Volcanic", "Ember"]
}

# Internal state
var _seed_value: int = 0
var _rng: RandomNumberGenerator

# Initialize with seed
func _init(seed_value: int = 0):
	_seed_value = seed_value
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value

# Generate a moon with the given parameters
func generate_moon(entity_id: int, position: Vector2, seed_value: int, moon_type: int = MoonType.ROCKY) -> MoonData:
	# Set seed for deterministic generation
	_rng.seed = seed_value
	
	# Create moon data
	var moon_data = MoonData.new(
		entity_id,
		position,
		seed_value,
		moon_type
	)
	
	# Generate moon size
	moon_data.pixel_size = _generate_moon_size(moon_type)
	
	# Generate moon name
	moon_data.moon_name = _generate_moon_name(moon_type, seed_value)
	
	# Determine if gaseous (rare for certain moons)
	moon_data.is_gaseous = _determine_if_gaseous(moon_type)
	
	# Configure visual properties
	_configure_visual_properties(moon_data)
	
	return moon_data

# Generate a size for the moon
func _generate_moon_size(moon_type: int) -> int:
	var size_array = MOON_SIZES.get(moon_type, MOON_SIZES[MoonType.ROCKY])
	var index = _rng.randi() % size_array.size()
	return size_array[index]

# Generate a name for the moon
func _generate_moon_name(moon_type: int, seed_value: int) -> String:
	_rng.seed = seed_value + 3456
	
	# Get type prefix list
	var prefixes = NAME_PREFIXES.get(moon_type, NAME_PREFIXES[MoonType.ROCKY])
	
	# Generate name
	var prefix = prefixes[_rng.randi() % prefixes.size()]
	var designation = str(_rng.randi_range(1, 999))
	
	return prefix + " Moon-" + designation

# Determine if a moon is gaseous (rare)
func _determine_if_gaseous(moon_type: int) -> bool:
	# Volcanic and icy moons can occasionally have atmospheres
	match moon_type:
		MoonType.VOLCANIC:
			return _rng.randf() < 0.15  # 15% chance
		MoonType.ICY:
			return _rng.randf() < 0.1   # 10% chance
		_:
			return _rng.randf() < 0.05  # 5% chance for rocky
	
	return false

# Configure visual properties for the moon
func _configure_visual_properties(moon_data: MoonData) -> void:
	# Set orbit colors based on type
	match moon_data.moon_type:
		MoonType.ROCKY:
			moon_data.orbit_color = Color(0.7, 0.7, 0.7, 0.5)
			moon_data.indicator_color = Color(0.8, 0.8, 0.8, 0.8)
		MoonType.ICY:
			moon_data.orbit_color = Color(0.5, 0.8, 1.0, 0.5)
			moon_data.indicator_color = Color(0.6, 0.9, 1.0, 0.8)
		MoonType.VOLCANIC:
			moon_data.orbit_color = Color(1.0, 0.3, 0.0, 0.5)
			moon_data.indicator_color = Color(1.0, 0.3, 0.0, 0.8)
	
	# Add some color variation
	var color_variation = 0.1
	moon_data.orbit_color.r = clamp(moon_data.orbit_color.r + (_rng.randf() - 0.5) * color_variation, 0, 1)
	moon_data.orbit_color.g = clamp(moon_data.orbit_color.g + (_rng.randf() - 0.5) * color_variation, 0, 1)
	moon_data.orbit_color.b = clamp(moon_data.orbit_color.b + (_rng.randf() - 0.5) * color_variation, 0, 1)
	
	# Set orbit indicator size based on moon size
	moon_data.orbit_indicator_size = max(3.0, moon_data.pixel_size / 12.0)
