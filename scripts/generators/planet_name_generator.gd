extends RefCounted
class_name PlanetNameGenerator

# Constants for planet name generation
const PLANET_PREFIXES = [
	"Aet", "Aeg", "Aqu", "Ast", "Ath", "Bor", "Cal", "Chro", "Cir", "Cor", 
	"Dem", "Dio", "Ech", "Ely", "Eos", "Epi", "Eri", "Eur", "Gal", "Hel", 
	"Hyp", "Ion", "Kal", "Kro", "Lun", "Lyt", "Mnem", "Nym", "Ody", "Oly", 
	"Orp", "Pan", "Per", "Pho", "Pos", "Rhe", "Sel", "Tha", "Tit", "Ura", 
	"Xen", "Zer"
]

const PLANET_SUFFIXES = [
	"on", "us", "um", "ux", "ax", "ix", "os", "is", "ia", "ium", "aria", 
	"aris", "oris", "ies", "eon", "era", "ura", "oni", "esi", "iri", 
	"oria", "aria", "alia", "opia", "ium"
]

const TERRAN_DESCRIPTORS = {
	# Themed descriptors - mapped by theme index
	0: ["Arid", "Dusty", "Sandy", "Barren", "Dry"], # Arid
	1: ["Frozen", "Icy", "Glacial", "Frigid", "Arctic"], # Ice
	2: ["Molten", "Volcanic", "Burning", "Infernal", "Scorched"], # Lava
	3: ["Verdant", "Lush", "Fertile", "Vibrant", "Flourishing"], # Lush
	4: ["Desert", "Dune", "Parched", "Desolate", "Sunbaked"], # Desert
	5: ["Alpine", "Mountainous", "Craggy", "Rugged", "Peaked"], # Alpine
	6: ["Oceanic", "Aquatic", "Abyssal", "Maritime", "Tidal"], # Ocean
	-1: ["Mysterious", "Enigmatic", "Unknown", "Distant", "Strange"] # Generic
}

const GAS_DESCRIPTORS = {
	# Gas giant types (Jupiter, Saturn, Uranus, Neptune)
	0: ["Colossal", "Mammoth", "Banded", "Massive", "Tempestuous"], # Jupiter-like
	1: ["Ringed", "Crowned", "Encircled", "Belted", "Adorned"], # Saturn-like
	2: ["Cyan", "Tilted", "Sideways", "Azure", "Pale"], # Uranus-like
	3: ["Stormy", "Deep", "Cobalt", "Sapphire", "Dark"], # Neptune-like
	-1: ["Gaseous", "Nebulous", "Swirling", "Cloudy", "Vast"] # Generic
}

# Constants for moon name generation
const MOON_PREFIXES = [
	"Lun", "Phob", "Deim", "Eur", "Gan", "Call", "Teth", "Rhe", "Tita", 
	"Nim", "Ner", "Tri", "Lar", "Mir", "Enc"
]

const MOON_SUFFIXES = [
	"a", "os", "is", "us", "o", "ia", "ius", "on", "ar", "ax", "ex", 
	"ix", "an", "iel"
]

const MOON_TYPE_DESCRIPTORS = {
	0: ["Rocky", "Cratered", "Barren", "Rugged", "Gray"], # Rocky
	1: ["Icy", "Frozen", "Crystalline", "Glacial", "Pale"], # Icy
	2: ["Volcanic", "Molten", "Fiery", "Sulfuric", "Burning"] # Volcanic
}

const LETTERS = "abcdefghijklmnopqrstuvwxyz"
const NUMBERS = "0123456789"

# Mythological names for important moons
const MYTHOLOGICAL_MOON_NAMES = [
	"Charon", "Europa", "Ganymede", "Callisto", "Io", "Titan", "Rhea", "Tethys",
	"Dione", "Enceladus", "Mimas", "Phoebe", "Iapetus", "Hyperion", "Miranda",
	"Ariel", "Umbriel", "Titania", "Oberon", "Nereid", "Proteus", "Triton"
]

# Static cache to ensure names are consistent across instances
static var _name_cache = {}

# Generate a planet name based on seed and planet type
static func generate_planet_name(seed_value: int, is_gaseous: bool = false, theme_id: int = -1) -> String:
	# Check cache for previously generated names
	var cache_key = "planet_%d_%s_%d" % [seed_value, str(is_gaseous), theme_id]
	if _name_cache.has(cache_key):
		return _name_cache[cache_key]
	
	# Generate name using SeedManager
	var style = _get_random_int(seed_value, 0, 3)
	var name = ""
	
	match style:
		0: name = _generate_compound_name(seed_value, is_gaseous)
		1: name = _generate_designation_name(seed_value, is_gaseous)
		2: name = _generate_descriptive_name(seed_value, is_gaseous, theme_id)
		_: name = _generate_compound_name(seed_value, is_gaseous)
	
	# Store in cache
	_name_cache[cache_key] = name
	return name

# Generate a moon name based on seed and moon type
static func generate_moon_name(seed_value: int, parent_name: String, moon_type: int, moon_index: int = 0) -> String:
	# Check cache
	var cache_key = "moon_%d_%s_%d_%d" % [seed_value, parent_name, moon_type, moon_index]
	if _name_cache.has(cache_key):
		return _name_cache[cache_key]
	
	# Bias for important moons (first moons more likely to get mythological names)
	var important_moon_bias = 0.6 - (moon_index * 0.2)
	important_moon_bias = clamp(important_moon_bias, 0.1, 0.6)
	
	var name = ""
	if _get_random_value(seed_value, 0, 1) < important_moon_bias:
		name = _generate_mythological_moon_name(seed_value, moon_index)
	else:
		var style = _get_random_int(seed_value, 0, 2)
		match style:
			0: name = _generate_moon_compound_name(seed_value, moon_type)
			1: name = _generate_moon_designation(seed_value, parent_name, moon_index)
			_: name = _generate_moon_descriptive_name(seed_value, moon_type)
	
	# Store in cache
	_name_cache[cache_key] = name
	return name

# Generate a mythological name for significant moons
static func _generate_mythological_moon_name(seed_value: int, moon_index: int) -> String:
	var name_index = _get_random_int(seed_value + moon_index, 0, MYTHOLOGICAL_MOON_NAMES.size() - 1)
	return MYTHOLOGICAL_MOON_NAMES[name_index]

# Generate a compound name (prefix + suffix)
static func _generate_compound_name(seed_value: int, is_gaseous: bool) -> String:
	var prefix_index = _get_random_int(seed_value, 0, PLANET_PREFIXES.size() - 1)
	var suffix_index = _get_random_int(seed_value + 1, 0, PLANET_SUFFIXES.size() - 1)
	
	var name = PLANET_PREFIXES[prefix_index] + PLANET_SUFFIXES[suffix_index]
	
	# Add number for extra uniqueness
	if _get_random_value(seed_value + 2, 0, 1) < 0.3:
		var number = _get_random_int(seed_value + 3, 1, 9)
		name += " " + str(number)
		
	return name

# Generate a designation style name (e.g., HD-24601)
static func _generate_designation_name(seed_value: int, is_gaseous: bool) -> String:
	var prefix_length = _get_random_int(seed_value, 1, 3)
	var number_length = _get_random_int(seed_value + 1, 3, 5)
	
	var prefix = ""
	for i in range(prefix_length):
		var letter_idx = _get_random_int(seed_value + 10 + i, 0, LETTERS.length() - 1)
		prefix += LETTERS[letter_idx].to_upper()
	
	var number = ""
	for i in range(number_length):
		var digit_idx = _get_random_int(seed_value + 20 + i, 0, NUMBERS.length() - 1)
		number += NUMBERS[digit_idx]
	
	return prefix + "-" + number

# Generate a descriptive name based on planet type
static func _generate_descriptive_name(seed_value: int, is_gaseous: bool, theme_id: int) -> String:
	var descriptor_array = GAS_DESCRIPTORS.get(-1, []) if is_gaseous else TERRAN_DESCRIPTORS.get(-1, [])
	
	# Use themed descriptors if available
	if theme_id >= 0:
		if is_gaseous and GAS_DESCRIPTORS.has(theme_id - 8): # Adjust for gas giant theme IDs
			descriptor_array = GAS_DESCRIPTORS[theme_id - 8]
		elif not is_gaseous and TERRAN_DESCRIPTORS.has(theme_id):
			descriptor_array = TERRAN_DESCRIPTORS[theme_id]
	
	var descriptor_idx = _get_random_int(seed_value, 0, descriptor_array.size() - 1)
	var descriptor = descriptor_array[descriptor_idx]
	
	return descriptor + " " + _generate_compound_name(seed_value + 100, is_gaseous)

# Generate moon compound name
static func _generate_moon_compound_name(seed_value: int, moon_type: int) -> String:
	var prefix_index = _get_random_int(seed_value, 0, MOON_PREFIXES.size() - 1)
	var suffix_index = _get_random_int(seed_value + 1, 0, MOON_SUFFIXES.size() - 1)
	
	return MOON_PREFIXES[prefix_index] + MOON_SUFFIXES[suffix_index]

# Generate moon designation
static func _generate_moon_designation(seed_value: int, parent_name: String, moon_index: int) -> String:
	# Extract first letters from parent name
	var parent_initial = ""
	var parts = parent_name.split(" ")
	var base_name = parts[0]
	
	if base_name.length() >= 2:
		parent_initial = base_name.substr(0, 2).to_upper()
	else:
		parent_initial = base_name.to_upper()
	
	# Different designation styles
	var style = _get_random_int(seed_value + 5, 0, 2)
	match style:
		0: # Roman numerals
			return parent_initial + "-" + ('I'.repeat(moon_index + 1))
		1: # Numeric
			return parent_initial + "-" + str(moon_index + 1)
		2: # Alphabetic
			var letter = LETTERS[min(moon_index, LETTERS.length() - 1)].to_upper()
			return parent_initial + "-" + letter

# Generate descriptive moon name
static func _generate_moon_descriptive_name(seed_value: int, moon_type: int) -> String:
	var descriptor_array = MOON_TYPE_DESCRIPTORS.get(moon_type, MOON_TYPE_DESCRIPTORS[0])
	var descriptor_idx = _get_random_int(seed_value, 0, descriptor_array.size() - 1)
	
	return descriptor_array[descriptor_idx] + " " + _generate_moon_compound_name(seed_value + 50, moon_type)

# Helper functions for deterministic random values
static func _get_random_value(object_id: int, min_val: float, max_val: float) -> float:
	if Engine.has_singleton("SeedManager") and SeedManager.has_method("get_random_value"):
		return SeedManager.get_random_value(object_id, min_val, max_val)
	else:
		var rng = RandomNumberGenerator.new()
		rng.seed = object_id
		return min_val + rng.randf() * (max_val - min_val)

static func _get_random_int(object_id: int, min_val: int, max_val: int) -> int:
	if Engine.has_singleton("SeedManager") and SeedManager.has_method("get_random_int"):
		return SeedManager.get_random_int(object_id, min_val, max_val)
	else:
		var rng = RandomNumberGenerator.new()
		rng.seed = object_id
		return rng.randi_range(min_val, max_val)

# Get a color associated with a planet theme
static func get_planet_color(theme_id: int, is_gaseous: bool) -> Color:
	if is_gaseous:
		match theme_id - 8: # Adjust for gas giant themes
			0: return Color(0.8, 0.7, 0.5, 1.0) # Jupiter
			1: return Color(0.9, 0.8, 0.6, 1.0) # Saturn
			2: return Color(0.6, 0.9, 0.9, 1.0) # Uranus
			3: return Color(0.4, 0.5, 0.9, 1.0) # Neptune
			_: return Color(0.7, 0.7, 0.5, 1.0) # Default
	else:
		match theme_id:
			0: return Color(0.9, 0.7, 0.5, 1.0) # Arid
			1: return Color(0.8, 0.9, 1.0, 1.0) # Ice
			2: return Color(0.9, 0.4, 0.2, 1.0) # Lava
			3: return Color(0.5, 0.9, 0.5, 1.0) # Lush
			4: return Color(0.9, 0.8, 0.5, 1.0) # Desert
			5: return Color(0.7, 0.7, 0.7, 1.0) # Alpine
			6: return Color(0.4, 0.6, 0.9, 1.0) # Ocean
			_: return Color(0.7, 0.7, 0.7, 1.0) # Default

# Get a color for a moon type
static func get_moon_color(moon_type: int) -> Color:
	match moon_type:
		0: return Color(0.8, 0.8, 0.8, 1.0) # Rocky
		1: return Color(0.7, 0.9, 1.0, 1.0) # Icy
		2: return Color(1.0, 0.6, 0.4, 1.0) # Volcanic
		_: return Color(0.8, 0.8, 0.8, 1.0) # Default

# Clear the name cache (rarely needed)
static func clear_cache() -> void:
	_name_cache.clear()
