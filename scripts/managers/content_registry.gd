# scripts/managers/content_registry.gd
extends Node
class_name ContentRegistry

signal content_loaded
signal content_updated(content_type)

# Registry for different content types
var _world_content = {}  # Grid cell -> cell content
var _asteroid_patterns = []
var _planet_textures = {}
var _moon_textures = {}
var _upgrade_strategies = {}
var _stations = {}
var _cached_assets = {}

# Loading state
var _loaded = false
var _debug_mode = false
var _game_settings = null
var _seed_value = 0

# Pattern and texture generators
var _pattern_generator = null
var _texture_generator = null

func _ready() -> void:
	# Find game settings
	var main_scene = get_tree().current_scene
	_game_settings = main_scene.get_node_or_null("GameSettings")
	if _game_settings:
		_debug_mode = _game_settings.debug_mode
		_seed_value = _game_settings.get_seed()
		
		# Connect to seed changes
		if _game_settings.has_signal("seed_changed") and not _game_settings.is_connected("seed_changed", _on_seed_changed):
			_game_settings.connect("seed_changed", _on_seed_changed)
	
	# Connect to SeedManager
	if has_node("/root/SeedManager"):
		if SeedManager.has_signal("seed_changed") and not SeedManager.is_connected("seed_changed", _on_seed_changed):
			SeedManager.connect("seed_changed", _on_seed_changed)
		_seed_value = SeedManager.get_seed()
	
	# Initialize generators - don't add as child since they extend RefCounted
	_pattern_generator = FragmentPatternGenerator.new(_seed_value)
	
	call_deferred("_initialize_registry")

func _initialize_registry() -> void:
	if _loaded:
		return
		
	if _debug_mode:
		print("ContentRegistry: Initializing content registry")
	
	# Generate asteroid fragment patterns
	_generate_asteroid_patterns()
	
	# Pre-generate textures
	_pre_generate_textures()
	
	# Prepare upgrade strategies
	_initialize_upgrade_strategies()
	
	_loaded = true
	content_loaded.emit()

func _on_seed_changed(new_seed: int) -> void:
	_seed_value = new_seed
	
	# Regenerate all procedural content
	_pattern_generator = FragmentPatternGenerator.new(new_seed)
	
	# Clear and rebuild registries
	_asteroid_patterns.clear()
	_planet_textures.clear()
	_moon_textures.clear()
	
	# Regenerate content
	_generate_asteroid_patterns()
	_pre_generate_textures()
	
	# Signal update
	content_updated.emit("all")

# Generate asteroid fragment patterns
func _generate_asteroid_patterns() -> void:
	_asteroid_patterns = _pattern_generator.generate_pattern_collection(_seed_value)
	
	if _debug_mode:
		print("ContentRegistry: Generated " + str(_asteroid_patterns.size()) + " asteroid patterns")
	
	content_updated.emit("asteroid_patterns")

# Pre-generate textures
func _pre_generate_textures() -> void:
	# Note: In a full implementation, we'd generate and cache actual textures here
	# For now, we'll just set up the structure for later integration
	
	_planet_textures = {
		"terran": {},
		"gaseous": {}
	}
	
	_moon_textures = {
		"rocky": {},
		"icy": {},
		"volcanic": {}
	}
	
	if _debug_mode:
		print("ContentRegistry: Prepared texture registry")
	
	content_updated.emit("textures")

# Initialize upgrade strategies
func _initialize_upgrade_strategies() -> void:
	# Load strategy scripts
	var weapon_strategies_script = load("res://scripts/strategies/weapon_strategies.gd")
	var shield_strategies_script = load("res://scripts/strategies/shield_strategies.gd")
	var movement_strategies_script = load("res://scripts/strategies/movement_strategies.gd")
	
	_upgrade_strategies = {
		"weapon": [],
		"shield": [],
		"movement": []
	}
	
	# Create instances of weapon strategies
	if weapon_strategies_script:
		_upgrade_strategies.weapon.append_array([
			weapon_strategies_script.DoubleDamageStrategy.new(),
			weapon_strategies_script.RapidFireStrategy.new(),
			weapon_strategies_script.PiercingShotStrategy.new(),
			weapon_strategies_script.SpreadShotStrategy.new()
		])
	
	# Create instances of shield strategies
	if shield_strategies_script:
		_upgrade_strategies.shield.append_array([
			shield_strategies_script.ReinforcedShieldStrategy.new(),
			shield_strategies_script.FastRechargeStrategy.new(),
			shield_strategies_script.ReflectiveShieldStrategy.new(),
			shield_strategies_script.AbsorbentShieldStrategy.new()
		])
	
	# Create instances of movement strategies
	if movement_strategies_script:
		_upgrade_strategies.movement.append_array([
			movement_strategies_script.EnhancedThrustersStrategy.new(),
			movement_strategies_script.ManeuverabilityStrategy.new(),
			movement_strategies_script.AfterburnerStrategy.new(),
			movement_strategies_script.InertialDampenersStrategy.new()
		])
	
	content_updated.emit("upgrade_strategies")

# Register world cell content (planets, asteroid fields, stations)
func register_world_cell_content(cell: Vector2i, content_data: Dictionary) -> void:
	_world_content[cell] = content_data
	content_updated.emit("world_content")

# Cache an asset in memory
func cache_asset(asset_type: String, asset_id: String, asset) -> void:
	if not _cached_assets.has(asset_type):
		_cached_assets[asset_type] = {}
	
	_cached_assets[asset_type][asset_id] = asset

# Get cached asset
func get_cached_asset(asset_type: String, asset_id: String):
	if not _cached_assets.has(asset_type):
		return null
	
	return _cached_assets[asset_type].get(asset_id)

# Clear asset cache for a specific type
func clear_asset_cache(asset_type: String) -> void:
	if _cached_assets.has(asset_type):
		_cached_assets[asset_type].clear()

# Get asteroid fragment pattern for an asteroid type and variant
func get_asteroid_pattern(size_category: String, variant_id: int) -> FragmentPatternData:
	# Filter patterns for this size
	var matching_patterns = []
	for pattern in _asteroid_patterns:
		if pattern.source_size == size_category:
			matching_patterns.append(pattern)
	
	# If no matching patterns, return null
	if matching_patterns.is_empty():
		return null
	
	# Select pattern based on variant
	var index = variant_id % matching_patterns.size()
	return matching_patterns[index]

# Get upgrade strategies for a component type
func get_upgrade_strategies(component_type: String) -> Array:
	return _upgrade_strategies.get(component_type, [])

# Get content for a world cell
func get_world_cell_content(cell: Vector2i) -> Dictionary:
	return _world_content.get(cell, {})

# Get all asteroid patterns
func get_all_asteroid_patterns() -> Array:
	return _asteroid_patterns

# Apply global content setting
func apply_content_settings(settings: Dictionary) -> void:
	# Update content based on settings
	if settings.has("asteroid_patterns_per_size"):
		var patterns_per_size = settings.asteroid_patterns_per_size
		_asteroid_patterns = _pattern_generator.generate_pattern_collection(_seed_value, patterns_per_size)
		content_updated.emit("asteroid_patterns")
	
	# Add other settings as needed
