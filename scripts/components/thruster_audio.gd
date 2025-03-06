extends Node
class_name ThrusterAudio

# Thruster sound controller for player ship
# Attach this script to your player ship or as a child node

# Configuration
@export var main_thruster_volume_db: float = 0.0
@export var rotation_thruster_volume_db: float = -6.0  # Half volume (-6dB)
@export var thruster_sound_name: String = "thruster"
@export var thruster_pitch_main: float = 1.0
@export var thruster_pitch_rotation: float = 1.1  # Slightly higher pitch for rotation

# Sound player references
var _main_thruster_player = null
var _rotation_thruster_player = null

# State tracking
var _main_thruster_active: bool = false
var _rotation_thruster_active: bool = false

# The player node (parent)
var _player: Node2D

func _ready():
	# Get reference to the player (parent)
	_player = get_parent()
	
	# Verify the AudioManager is available
	if not Engine.has_singleton("Audio"):
		push_error("AudioManager not found as singleton. Add it to your AutoLoad list as 'Audio'")
	
	# Ensure the thruster sound is preloaded
	if not _is_sound_preloaded():
		push_warning("Thruster sound '" + thruster_sound_name + "' not preloaded. Attempting to preload now.")
		Audio.preload_sfx(thruster_sound_name, "res://audio/sfx/" + thruster_sound_name + ".wav", 2)

# Check if our thruster sound is preloaded
func _is_sound_preloaded() -> bool:
	# This is an indirect way to check since AudioManager doesn't expose _loaded_sfx
	# Try to play the sound with volume set to MIN_DB (-80) which is effectively silent
	var test_player = Audio.play_sfx(thruster_sound_name, Vector2.ZERO, 1.0, -80.0)
	var preloaded = test_player != null
	
	# Stop the test sound
	if test_player != null:
		test_player.stop()
	
	return preloaded

# Update thruster positions each frame if active
func _process(_delta):
	# Update position for active sound players
	if _main_thruster_active and _main_thruster_player:
		_main_thruster_player.position = _player.global_position
	
	if _rotation_thruster_active and _rotation_thruster_player:
		_rotation_thruster_player.position = _player.global_position

# Start main thruster sound
func start_main_thruster():
	if _main_thruster_active:
		return
	
	_main_thruster_active = true
	_main_thruster_player = Audio.play_sfx(
		thruster_sound_name, 
		_player.global_position, 
		thruster_pitch_main, 
		main_thruster_volume_db
	)
	
	# Configure for looping
	if _main_thruster_player:
		# Ensure the sound loops
		if _main_thruster_player.stream and not _main_thruster_player.stream.loop:
			var looping_stream = _main_thruster_player.stream.duplicate()
			looping_stream.loop = true
			_main_thruster_player.stream = looping_stream

# Stop main thruster sound
func stop_main_thruster():
	if not _main_thruster_active:
		return
	
	_main_thruster_active = false
	
	if _main_thruster_player:
		_main_thruster_player.stop()
		_main_thruster_player = null

# Start rotation thruster sound
func start_rotation_thruster():
	if _rotation_thruster_active:
		return
	
	_rotation_thruster_active = true
	_rotation_thruster_player = Audio.play_sfx(
		thruster_sound_name, 
		_player.global_position, 
		thruster_pitch_rotation, 
		rotation_thruster_volume_db
	)
	
	# Configure for looping
	if _rotation_thruster_player:
		# Ensure the sound loops
		if _rotation_thruster_player.stream and not _rotation_thruster_player.stream.loop:
			var looping_stream = _rotation_thruster_player.stream.duplicate()
			looping_stream.loop = true
			_rotation_thruster_player.stream = looping_stream

# Stop rotation thruster sound
func stop_rotation_thruster():
	if not _rotation_thruster_active:
		return
	
	_rotation_thruster_active = false
	
	if _rotation_thruster_player:
		_rotation_thruster_player.stop()
		_rotation_thruster_player = null

# Stop all thruster sounds
func stop_all_thrusters():
	stop_main_thruster()
	stop_rotation_thruster()

# Cleanup when node is removed
func _exit_tree():
	stop_all_thrusters()
