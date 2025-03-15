# scripts/managers/effect_pool_manager.gd
extends Node
class_name EffectPoolManager

signal pools_initialized

# Pool configuration
@export_group("Pool Configuration")
@export var small_explosion_pool_size: int = 20
@export var medium_explosion_pool_size: int = 15
@export var large_explosion_pool_size: int = 10
@export var impact_effect_pool_size: int = 25
@export var shield_hit_pool_size: int = 15
@export var auto_expand_pools: bool = true

# Effect scene paths
const SMALL_EXPLOSION_PATH = "res://scenes/effects/small_explosion.tscn"
const MEDIUM_EXPLOSION_PATH = "res://scenes/effects/medium_explosion.tscn"
const LARGE_EXPLOSION_PATH = "res://scenes/effects/large_explosion.tscn"
const IMPACT_EFFECT_PATH = "res://scenes/effects/impact_effect.tscn"
const SHIELD_HIT_PATH = "res://scenes/effects/shield_hit.tscn"

# Effect pools - mapped by type
var _effect_pools = {}
var _active_effects = []

# Initialization tracking
var _initialized: bool = false
var _initializing: bool = false

# Cache for effect scenes
var _scene_cache = {}

# Debug mode
var _debug_mode: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_PAUSABLE
	
	# Find GameSettings
	var main_scene = get_tree().current_scene
	var game_settings = main_scene.get_node_or_null("GameSettings")
	if game_settings:
		_debug_mode = game_settings.debug_mode
	
	# Initialize after engine is ready
	call_deferred("initialize")

func initialize() -> void:
	if _initialized or _initializing:
		return
	
	_initializing = true
	
	if _debug_mode:
		print("EffectPoolManager: Initializing effect pools")
	
	# Load effect scenes
	_preload_effect_scenes()
	
	# Initialize pools
	_initialize_pools()
	
	_initialized = true
	_initializing = false
	
	if _debug_mode:
		_log_pool_stats()
	
	# Signal that all pools are initialized
	pools_initialized.emit()

# Preload effect scenes
func _preload_effect_scenes() -> void:
	_load_scene("small_explosion", SMALL_EXPLOSION_PATH)
	_load_scene("medium_explosion", MEDIUM_EXPLOSION_PATH)
	_load_scene("large_explosion", LARGE_EXPLOSION_PATH)
	_load_scene("impact_effect", IMPACT_EFFECT_PATH)
	_load_scene("shield_hit", SHIELD_HIT_PATH)

# Load a scene into the cache
func _load_scene(key: String, path: String) -> void:
	if ResourceLoader.exists(path):
		_scene_cache[key] = load(path)
	else:
		# Create fallback effect if scene doesn't exist
		if _debug_mode:
			print("EffectPoolManager: Scene not found: " + path + " - creating fallback")
		_scene_cache[key] = _create_fallback_effect(key)

# Create a fallback effect scene
func _create_fallback_effect(effect_name: String) -> PackedScene:
	var node = CPUParticles2D.new()
	node.name = effect_name + "_fallback"
	node.emitting = false
	node.one_shot = true
	node.explosiveness = 0.9
	
	# Configure based on effect type
	if "explosion" in effect_name:
		node.amount = 50
		node.lifetime = 0.5
		node.spread = 180
		node.initial_velocity_min = 30
		node.initial_velocity_max = 100
		node.scale_amount = 2.0 if "medium" in effect_name else (3.0 if "large" in effect_name else 1.0)
		node.color = Color(1.0, 0.5, 0.1)
	elif "impact" in effect_name:
		node.amount = 20
		node.lifetime = 0.3
		node.spread = 90
		node.initial_velocity_min = 20
		node.initial_velocity_max = 50
		node.color = Color(1.0, 0.9, 0.3)
	elif "shield" in effect_name:
		node.amount = 15
		node.lifetime = 0.2
		node.spread = 60
		node.initial_velocity_min = 10
		node.initial_velocity_max = 30
		node.color = Color(0.3, 0.8, 1.0)
	
	var packed_scene = PackedScene.new()
	packed_scene.pack(node)
	return packed_scene

# Initialize all effect pools
func _initialize_pools() -> void:
	_initialize_pool("small_explosion", small_explosion_pool_size)
	_initialize_pool("medium_explosion", medium_explosion_pool_size)
	_initialize_pool("large_explosion", large_explosion_pool_size)
	_initialize_pool("impact_effect", impact_effect_pool_size)
	_initialize_pool("shield_hit", shield_hit_pool_size)

# Initialize a specific effect pool
func _initialize_pool(pool_name: String, pool_size: int) -> void:
	if not _scene_cache.has(pool_name):
		push_error("EffectPoolManager: Cannot initialize pool - missing scene: " + pool_name)
		return
	
	var pool = []
	
	for i in range(pool_size):
		var effect = _create_effect(pool_name)
		if effect:
			pool.append(effect)
	
	_effect_pools[pool_name] = pool

# Create a single effect
func _create_effect(effect_type: String) -> Node:
	if not _scene_cache.has(effect_type):
		return null
	
	var effect = _scene_cache[effect_type].instantiate()
	add_child(effect)
	
	# Set initial state to inactive
	if effect is CPUParticles2D or effect is GPUParticles2D:
		effect.emitting = false
	effect.visible = false
	
	# Add to group for easier management
	if not effect.is_in_group("effects"):
		effect.add_to_group("effects")
	
	return effect

# Get an effect from a pool and play it at the specified position
func play_effect(effect_type: String, position: Vector2, rotation: float = 0.0, scale: float = 1.0) -> Node:
	if not _initialized:
		# Wait for initialization to complete
		if not _initializing:
			initialize()
		await pools_initialized
	
	# Make sure pool exists
	if not _effect_pools.has(effect_type):
		if _debug_mode:
			push_error("EffectPoolManager: Unknown effect type: " + effect_type)
		return null
	
	# Get effect from pool
	var effect = _get_from_pool(effect_type)
	if not effect:
		return null
	
	# Configure and play effect
	_configure_and_play_effect(effect, position, rotation, scale)
	
	# Track active effect
	_active_effects.append(effect)
	
	return effect

# Get an inactive effect from the pool
func _get_from_pool(pool_name: String) -> Node:
	var pool = _effect_pools.get(pool_name, [])
	
	# Try to find an inactive effect
	for effect in pool:
		if is_instance_valid(effect) and not effect.visible:
			var is_active = false
			
			# Different checks for particle effects vs. animated effects
			if effect is CPUParticles2D or effect is GPUParticles2D:
				is_active = effect.emitting
			elif effect.has_method("is_playing"):
				is_active = effect.is_playing()
			
			if not is_active:
				effect.visible = true
				return effect
	
	# If no effects available, create a new one if auto-expand is enabled
	if auto_expand_pools and _scene_cache.has(pool_name):
		if _debug_mode:
			print("EffectPoolManager: Expanding " + pool_name + " pool")
			
		var new_effect = _create_effect(pool_name)
		if new_effect:
			pool.append(new_effect)
			_effect_pools[pool_name] = pool
			new_effect.visible = true
			return new_effect
	
	# If no effects available and auto-expand is disabled, return null
	if _debug_mode:
		print("EffectPoolManager: No " + pool_name + " effects available!")
		
	return null

# Configure and play an effect
func _configure_and_play_effect(effect: Node, position: Vector2, rotation: float, scale_factor: float) -> void:
	# Set position
	effect.global_position = position
	
	# Set rotation if applicable
	if "rotation" in effect:
		effect.rotation = rotation
	
	# Set scale if applicable
	if "scale" in effect:
		var base_scale = Vector2(1, 1)
		if effect.scale != Vector2.ZERO:
			base_scale = effect.scale.normalized()
		effect.scale = base_scale * scale_factor
	
	# Play the effect
	if effect is CPUParticles2D or effect is GPUParticles2D:
		effect.restart()
		effect.emitting = true
		
		# Auto-return particle effects after lifetime
		var max_lifetime = effect.lifetime
		if effect is CPUParticles2D and effect.lifetime_randomness > 0:
			max_lifetime *= (1.0 + effect.lifetime_randomness)
		
		get_tree().create_timer(max_lifetime).timeout.connect(
			func(): return_effect(effect)
		)
	elif effect.has_method("play"):
		effect.play()
		
		# Connect to finished signal if it exists
		if effect.has_signal("animation_finished") and not effect.is_connected("animation_finished", Callable(self, "return_effect").bind(effect)):
			effect.animation_finished.connect(
				func(): return_effect(effect)
			)

# Return an effect to the pool
func return_effect(effect: Node) -> void:
	if not is_instance_valid(effect):
		return
	
	# Reset state
	effect.visible = false
	
	if effect is CPUParticles2D or effect is GPUParticles2D:
		effect.emitting = false
	
	# Remove from active effects list
	var index = _active_effects.find(effect)
	if index >= 0:
		_active_effects.remove_at(index)

# Clear all active effects
func clear_active_effects() -> void:
	var active_copy = _active_effects.duplicate()
	for effect in active_copy:
		if is_instance_valid(effect):
			return_effect(effect)

# Convenience methods for common effects
func explosion(position: Vector2, size: String = "medium", rotation: float = 0.0, scale: float = 1.0) -> Node:
	var effect_type = size + "_explosion"
	return await play_effect(effect_type, position, rotation, scale)

func impact(position: Vector2, rotation: float = 0.0, scale: float = 1.0) -> Node:
	return await play_effect("impact_effect", position, rotation, scale)

func shield_hit(position: Vector2, rotation: float = 0.0, scale: float = 1.0) -> Node:
	return await play_effect("shield_hit", position, rotation, scale)

# Debug logging
func _log_pool_stats() -> void:
	if not _debug_mode:
		return
		
	print("EffectPoolManager: Effect pool statistics:")
	for pool_name in _effect_pools:
		var pool_size = _effect_pools[pool_name].size()
		print("- " + pool_name + " effects: " + str(pool_size))
