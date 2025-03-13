extends RefCounted
class_name PlanetNameGenerator

# Constants for name generation
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

# Using SeedManager for deterministic generation
var _seed_manager = null
var _rng = RandomNumberGenerator.new()

func _init() -> void:
	# Try to get SeedManager
	if Engine.has_singleton("SeedManager"):
		_seed_manager = Engine.get_singleton("SeedManager")

# Generate a planet name based on seed and planet type
func generate_planet_name(seed_value: int, is_gaseous: bool = false, theme_id: int = -1) -> String:
	# Choose name generation style based on random value
	var style = _get_random_int(seed_value, 0, 3)
	
	match style:
		0: return _generate_compound_name(seed_value, is_gaseous)
		1: return _generate_designation_name(seed_value, is_gaseous)
		2: return _generate_descriptive_name(seed_value, is_gaseous, theme_id)
		_: return _generate_compound_name(seed_value, is_gaseous)

# Generate moon name based on seed and moon type
func generate_moon_name(seed_value: int, parent_name: String, moon_type: int, moon_index: int = 0) -> String:
	var style = _get_random_int(seed_value, 0, 2)
	
	match style:
		0: return _generate_moon_compound_name(seed_value, moon_type)
		1: return _generate_moon_designation(seed_value, parent_name, moon_index)
		_: return _generate_moon_descriptive_name(seed_value, moon_type)

# Generate a compound name (prefix + suffix)
func _generate_compound_name(seed_value: int, is_gaseous: bool) -> String:
	var prefix_index = _get_random_int(seed_value, 0, PLANET_PREFIXES.size() - 1)
	var suffix_index = _get_random_int(seed_value + 1, 0, PLANET_SUFFIXES.size() - 1)
	
	var name = PLANET_PREFIXES[prefix_index] + PLANET_SUFFIXES[suffix_index]
	
	# Add number for extra uniqueness
	if _get_random_value(seed_value + 2, 0, 1) < 0.3:
		var number = _get_random_int(seed_value + 3, 1, 9)
		name += " " + str(number)
	
	return name

# Generate a designation style name (e.g., HD-24601)
func _generate_designation_name(seed_value: int, is_gaseous: bool) -> String:
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
func _generate_descriptive_name(seed_value: int, is_gaseous: bool, theme_id: int) -> String:
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
func _generate_moon_compound_name(seed_value: int, moon_type: int) -> String:
	var prefix_index = _get_random_int(seed_value, 0, MOON_PREFIXES.size() - 1)
	var suffix_index = _get_random_int(seed_value + 1, 0, MOON_SUFFIXES.size() - 1)
	
	return MOON_PREFIXES[prefix_index] + MOON_SUFFIXES[suffix_index]

# Generate moon designation
func _generate_moon_designation(seed_value: int, parent_name: String, moon_index: int) -> String:
	# Extract first letters from parent name
	var parent_initial = ""
	var parts = parent_name.split(" ")
	var base_name = parts[0]
	
	if base_name.length() >= 2:
		parent_initial = base_name.substr(0, 2).to_upper()
	else:
		parent_initial = base_name.to_upper()
	
	return parent_initial + "-" + ('I'.repeat(moon_index + 1))

# Generate descriptive moon name
func _generate_moon_descriptive_name(seed_value: int, moon_type: int) -> String:
	var descriptor_array = MOON_TYPE_DESCRIPTORS.get(moon_type, MOON_TYPE_DESCRIPTORS[0])
	var descriptor_idx = _get_random_int(seed_value, 0, descriptor_array.size() - 1)
	
	return descriptor_array[descriptor_idx] + " " + _generate_moon_compound_name(seed_value + 50, moon_type)

# Helper functions for deterministic random values
func _get_random_value(object_id: int, min_val: float, max_val: float) -> float:
	if _seed_manager and _seed_manager.has_method("get_random_value"):
		return _seed_manager.get_random_value(object_id, min_val, max_val)
	else:
		_rng.seed = object_id
		return min_val + _rng.randf() * (max_val - min_val)

func _get_random_int(object_id: int, min_val: int, max_val: int) -> int:
	if _seed_manager and _seed_manager.has_method("get_random_int"):
		return _seed_manager.get_random_int(object_id, min_val, max_val)
	else:
		_rng.seed = object_id
		return _rng.randi_range(min_val, max_val)
