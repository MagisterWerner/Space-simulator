# scripts/components/movement_component.gd
# Optimized movement component with improved thruster and audio management
extends Component
class_name MovementComponent

signal thrusting_changed(is_thrusting)
signal boost_activated
signal boost_depleted
signal boost_recharged

@export_category("Movement Properties")
@export var thrust_force: float = 200.0
@export var reverse_force: float = 100.0
@export var rotation_force: float = 300.0
@export var max_speed: float = 700.0
@export var dampening_factor: float = 0.98

@export_category("Boost")
@export var boost_enabled: bool = true
@export var boost_settings: Vector3 = Vector3(2.0, 3.0, 4.0)  # multiplier, duration, cooldown
@export var boost_fuel: float = 100.0
@export var boost_fuel_rates: Vector2 = Vector2(30.0, 20.0)  # consumption, regen

@export_category("Audio")
@export var enable_audio: bool = true
@export var audio_settings: Dictionary = {
	"main": {"name": "thruster", "volume": 0.0, "pitch": 1.0},
	"rotation": {"name": "thruster", "volume": -6.0, "pitch": 1.1},
	"backward": {"name": "thruster", "volume": -3.0, "pitch": 0.9},
	"boost": {"name": "boost", "volume": 0.0, "pitch": 0.9}
}

# Movement state
var _movement_state: Dictionary = {
	"forward": false,
	"backward": false,
	"rotation": 0.0,
	"boosting": false,
	"fuel": 100.0,
	"cooldown": 0.0
}

# References and cached values
var _rigid_body: RigidBody2D
var _audio_manager = null
var _sound_players: Dictionary = {}
var _thruster_nodes: Dictionary = {}
var _active_thrusters: Array = []

func setup() -> void:
	if owner_entity is RigidBody2D:
		_rigid_body = owner_entity
	else:
		push_error("MovementComponent: Owner is not a RigidBody2D")
		disable()
		return
	
	_movement_state.fuel = boost_fuel
	
	# Find thruster nodes efficiently
	_find_thruster_nodes()
	
	# Get AudioManager reference
	_audio_manager = _get_audio_manager()
	
	# Initialize audio
	call_deferred("_initialize_audio")

# Find all thruster nodes in owner - more efficient approach
func _find_thruster_nodes() -> void:
	# Standard names to search for
	var node_names = {
		"main": ["MainThruster"],
		"left_rear": ["ThrusterPositions/Left/RearThruster", "Left/RearThruster", "LeftRear"],
		"right_rear": ["ThrusterPositions/Right/RearThruster", "Right/RearThruster", "RightRear"],
		"left_front": ["ThrusterPositions/Left/FrontThruster", "Left/FrontThruster", "LeftFront"],
		"right_front": ["ThrusterPositions/Right/FrontThruster", "Right/FrontThruster", "RightFront"]
	}
	
	# Find a node by trying multiple paths
	for key in node_names:
		for path in node_names[key]:
			var node = owner_entity.get_node_or_null(path)
			if node:
				_thruster_nodes[key] = node
				break
				
		# If not found by path, try searching children
		if not _thruster_nodes.has(key):
			_thruster_nodes[key] = _find_node_recursive(owner_entity, node_names[key][0].split("/")[-1])

# Recursively find a node by name
func _find_node_recursive(parent: Node, name: String) -> Node:
	for child in parent.get_children():
		if child.name == name:
			return child
		
		var found = _find_node_recursive(child, name)
		if found:
			return found
	
	return null

# Get AudioManager with fallbacks
func _get_audio_manager():
	# Try root node first
	if Engine.get_main_loop() and Engine.get_main_loop().root.has_node("AudioManager"):
		return Engine.get_main_loop().root.get_node("AudioManager")
	
	# Try direct path
	var audio_mgr = get_node_or_null("/root/AudioManager")
	if audio_mgr:
		return audio_mgr
	
	return null

# Initialize audio with preloading
func _initialize_audio() -> void:
	if not enable_audio or not _audio_manager:
		return
	
	var sound_files = {
		"thruster": "res://assets/audio/thruster.wav",
		"boost": "res://assets/audio/boost.wav"
	}
	
	# Preload sounds if they're not already loaded
	if _audio_manager.has_method("is_sfx_loaded"):
		for sound_name in sound_files:
			if not _audio_manager.is_sfx_loaded(sound_name):
				var path = sound_files[sound_name]
				if ResourceLoader.exists(path):
					_audio_manager.preload_sfx(sound_name, path, 2)

func _on_enable() -> void:
	# Restart active sounds if any
	if _movement_state.forward:
		_update_thruster_audio("main", true)
	if _movement_state.rotation != 0:
		_update_thruster_audio("rotation", true)
	if _movement_state.backward:
		_update_thruster_audio("backward", true)
	if _movement_state.boosting:
		_update_thruster_audio("boost", true)

func _on_disable() -> void:
	# Stop all sounds
	_stop_all_audio()
	
	# Disable all thrusters
	for thruster in _active_thrusters:
		_set_thruster_emission(thruster, false)
	_active_thrusters.clear()

func physics_process_component(delta: float) -> void:
	if not _rigid_body or not enabled:
		return
	
	# Apply strategies to movement properties
	var current_properties = {
		"thrust": thrust_force,
		"reverse": reverse_force,
		"rotation": rotation_force,
		"max_speed": max_speed
	}
	
	# Apply all strategies that modify movement
	for strategy in _get_strategies():
		for property in current_properties:
			var method_name = "modify_" + property
			if strategy.has_method(method_name):
				current_properties[property] = strategy.call(method_name, current_properties[property])
	
	# Handle boost
	if _movement_state.boosting:
		current_properties.thrust *= boost_settings.x  # Boost multiplier
		current_properties.reverse *= boost_settings.x
		
		# Consume fuel
		_movement_state.fuel -= boost_fuel_rates.x * delta
		if _movement_state.fuel <= 0:
			_movement_state.fuel = 0
			stop_boost()
			boost_depleted.emit()
	elif boost_enabled and _movement_state.fuel < boost_fuel:
		# Regenerate fuel when not boosting
		_movement_state.fuel = min(_movement_state.fuel + (boost_fuel_rates.y * delta), boost_fuel)
		
		# Signal when fully recharged
		if _movement_state.fuel == boost_fuel and _movement_state.cooldown <= 0:
			boost_recharged.emit()
	
	# Update boost cooldown
	if _movement_state.cooldown > 0:
		_movement_state.cooldown -= delta
	
	# Apply movement forces
	_apply_movement_forces(current_properties, delta)
	
	# Cap maximum speed
	if _rigid_body.linear_velocity.length() > current_properties.max_speed:
		_rigid_body.linear_velocity = _rigid_body.linear_velocity.normalized() * current_properties.max_speed
	
	# Apply dampening
	_rigid_body.linear_velocity *= dampening_factor
	
	# Update audio positions
	_update_audio_positions()

# Get all strategies (more efficient than maintaining a separate array)
func _get_strategies() -> Array:
	var strategies = []
	for child in get_children():
		if child.has_method("modify_thrust") or child.has_method("modify_rotation") or \
		   child.has_method("modify_max_speed") or child.has_method("modify_reverse_thrust"):
			strategies.append(child)
	return strategies

# Core movement logic
func _apply_movement_forces(properties: Dictionary, _delta: float) -> void:
	# Forward thrust
	if _movement_state.forward:
		var forward_dir = Vector2.RIGHT.rotated(_rigid_body.rotation)
		_rigid_body.apply_central_force(forward_dir * properties.thrust)
		_set_thruster_emission(_thruster_nodes.get("main"), true)
	else:
		_set_thruster_emission(_thruster_nodes.get("main"), false)
	
	# Backward thrust
	if _movement_state.backward:
		var backward_dir = Vector2.LEFT.rotated(_rigid_body.rotation)
		_rigid_body.apply_central_force(backward_dir * properties.reverse)
		
		# Activate front thrusters and manage rotation during backward movement
		if _movement_state.rotation > 0:  # Turn right while moving backward
			_set_thruster_emission(_thruster_nodes.get("right_front"), true)
			_set_thruster_emission(_thruster_nodes.get("left_front"), false)
			_rigid_body.apply_torque(properties.rotation * 0.3)
		elif _movement_state.rotation < 0:  # Turn left while moving backward
			_set_thruster_emission(_thruster_nodes.get("left_front"), true)
			_set_thruster_emission(_thruster_nodes.get("right_front"), false)
			_rigid_body.apply_torque(-properties.rotation * 0.3)
		else:  # Just moving backward without turning
			_set_thruster_emission(_thruster_nodes.get("left_front"), true)
			_set_thruster_emission(_thruster_nodes.get("right_front"), true)
	else:
		_set_thruster_emission(_thruster_nodes.get("left_front"), false)
		_set_thruster_emission(_thruster_nodes.get("right_front"), false)
	
	# Rotation when not moving backward
	if not _movement_state.backward:
		if _movement_state.rotation > 0:  # Turn right
			_set_thruster_emission(_thruster_nodes.get("left_rear"), true)
			_rigid_body.apply_torque(properties.rotation)
		else:
			_set_thruster_emission(_thruster_nodes.get("left_rear"), false)
		
		if _movement_state.rotation < 0:  # Turn left
			_set_thruster_emission(_thruster_nodes.get("right_rear"), true)
			_rigid_body.apply_torque(-properties.rotation)
		else:
			_set_thruster_emission(_thruster_nodes.get("right_rear"), false)

# Set thruster emission state with tracking
func _set_thruster_emission(thruster: Node, emitting: bool) -> void:
	if not thruster:
		return
	
	# Track active thrusters for easier cleanup
	if emitting and not _active_thrusters.has(thruster):
		_active_thrusters.append(thruster)
	elif not emitting and _active_thrusters.has(thruster):
		_active_thrusters.erase(thruster)
	
	# Set emission based on node type
	if thruster is CPUParticles2D or thruster is GPUParticles2D:
		thruster.emitting = emitting
	elif thruster.has_method("set_deferred"):
		thruster.set_deferred("emitting", emitting)
	elif thruster is Node2D:
		thruster.visible = emitting

# Centralized audio management
func _update_thruster_audio(audio_type: String, active: bool) -> void:
	if not enable_audio or not _audio_manager:
		return
	
	# Stop current sound if deactivating
	if not active:
		if _sound_players.has(audio_type):
			var player = _sound_players[audio_type]
			if player:
				player.stop()
			_sound_players.erase(audio_type)
		return
	
	# Don't restart if already playing
	if _sound_players.has(audio_type):
		return
	
	# Get audio settings
	var settings = audio_settings.get(audio_type)
	if not settings:
		return
	
	# Start sound
	if _audio_manager.has_method("play_sfx"):
		var player = _audio_manager.play_sfx(
			settings.name,
			owner_entity.global_position,
			settings.pitch,
			settings.volume
		)
		
		if player and player.stream and player is AudioStreamPlayer:
			# Configure looping
			var stream = player.stream as AudioStreamWAV
			if stream:
				stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
				stream.loop_begin = 0
				stream.loop_end = stream.data.size()
		
		_sound_players[audio_type] = player

# Stop all audio at once
func _stop_all_audio() -> void:
	for audio_type in _sound_players:
		var player = _sound_players[audio_type]
		if player:
			player.stop()
	_sound_players.clear()

# Update audio positions
func _update_audio_positions() -> void:
	if not owner_entity or not enable_audio:
		return
	
	for audio_type in _sound_players:
		var player = _sound_players[audio_type]
		if player and is_instance_valid(player):
			player.position = owner_entity.global_position

# Public movement control methods
func thrust_forward(activate: bool = true) -> void:
	var was_active = _movement_state.forward
	_movement_state.forward = activate
	
	# Handle audio
	if was_active != _movement_state.forward:
		_update_thruster_audio("main", _movement_state.forward)
		thrusting_changed.emit(_movement_state.forward)

func thrust_backward(activate: bool = true) -> void:
	var was_active = _movement_state.backward
	_movement_state.backward = activate
	
	# Handle audio
	if was_active != _movement_state.backward:
		_update_thruster_audio("backward", _movement_state.backward)

func rotate_left() -> void:
	var was_rotating = _movement_state.rotation != 0
	_movement_state.rotation = -1.0
	
	if not was_rotating:
		_update_thruster_audio("rotation", true)

func rotate_right() -> void:
	var was_rotating = _movement_state.rotation != 0
	_movement_state.rotation = 1.0
	
	if not was_rotating:
		_update_thruster_audio("rotation", true)

func stop_rotation() -> void:
	var was_rotating = _movement_state.rotation != 0
	_movement_state.rotation = 0.0
	
	if was_rotating:
		_update_thruster_audio("rotation", false)

func start_boost() -> void:
	if not boost_enabled or _movement_state.boosting or _movement_state.cooldown > 0 or _movement_state.fuel <= 0:
		return
	
	_movement_state.boosting = true
	_update_thruster_audio("boost", true)
	boost_activated.emit()

func stop_boost() -> void:
	if not _movement_state.boosting:
		return
	
	_movement_state.boosting = false
	_movement_state.cooldown = boost_settings.z  # Cooldown time
	_update_thruster_audio("boost", false)

# Utility methods
func get_boost_fuel_percent() -> float:
	return _movement_state.fuel / boost_fuel

func get_current_velocity() -> Vector2:
	return _rigid_body.linear_velocity if _rigid_body else Vector2.ZERO

func get_current_speed() -> float:
	return get_current_velocity().length()

# Strategy management - simplified
func add_movement_strategy(strategy) -> void:
	if strategy.has_method("apply_to_component"):
		strategy.apply_to_component(self)
	else:
		add_child(strategy)

func remove_movement_strategy(strategy) -> void:
	if strategy.has_method("remove_from_component"):
		strategy.remove_from_component()
	elif strategy is Node and strategy.get_parent() == self:
		strategy.queue_free()
