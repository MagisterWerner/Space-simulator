# scripts/audio/background_music_controller.gd
# Purpose: Handles background music initialization and management
# Save this as res://scripts/audio/background_music_controller.gd

extends Node

# Music track paths
const BACKGROUND_MUSIC_PATH = "res://assets/audio/space.ogg"
const MUSIC_TRACK_ID = "background_music"

# Configuration
@export var start_music_on_ready: bool = true
@export var enable_debug_log: bool = false
@export var music_fade_time: float = 1.0

# State tracking
var _initialized: bool = false
var _music_loaded: bool = false

func _ready() -> void:
	# Set up process mode to continue during pause
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Wait a short time to ensure AudioManager is initialized
	await get_tree().create_timer(0.2).timeout
	
	# Initialize and start music
	_initialize_music()
	
	# Connect to game signals
	if has_node("/root/EventManager"):
		EventManager.safe_connect("game_started", _on_game_started)
		EventManager.safe_connect("game_paused", _on_game_paused)
		EventManager.safe_connect("game_resumed", _on_game_resumed)
		EventManager.safe_connect("game_over", _on_game_over)
		EventManager.safe_connect("game_restarted", _on_game_restarted)

# Initialize music system
func _initialize_music() -> void:
	if _initialized:
		return
	
	if not has_node("/root/AudioManager"):
		push_error("BackgroundMusicController: AudioManager not found!")
		return
	
	if not AudioManager.is_initialized():
		debug_print("Waiting for AudioManager to initialize...")
		await get_tree().create_timer(0.5).timeout
		_initialize_music()
		return
	
	# Check if music file exists
	if not ResourceLoader.exists(BACKGROUND_MUSIC_PATH):
		push_error("BackgroundMusicController: Music file not found: " + BACKGROUND_MUSIC_PATH)
		return
	
	# Preload the music track
	AudioManager.preload_music(MUSIC_TRACK_ID, BACKGROUND_MUSIC_PATH)
	_music_loaded = true
	
	# Start the music if auto-start is enabled
	if start_music_on_ready:
		AudioManager.play_music(MUSIC_TRACK_ID, true)
		debug_print("Background music started")
	
	_initialized = true
	debug_print("Music controller initialized")

# Game event handlers
func _on_game_started() -> void:
	debug_print("Game started")
	if _initialized and _music_loaded and not AudioManager.is_music_playing():
		AudioManager.play_music(MUSIC_TRACK_ID, true)

func _on_game_paused() -> void:
	debug_print("Game paused")
	# Optionally: modify music when game is paused
	# AudioManager.set_music_volume(0.5)

func _on_game_resumed() -> void:
	debug_print("Game resumed")
	# Optionally: restore music when game is resumed
	# AudioManager.set_music_volume(0.8)

func _on_game_over() -> void:
	debug_print("Game over")
	# Optionally: change music on game over
	# AudioManager.stop_music()
	# AudioManager.play_music("game_over_music", true)

func _on_game_restarted() -> void:
	debug_print("Game restarted")
	AudioManager.play_music(MUSIC_TRACK_ID, true)

# Utility functions
func debug_print(message: String) -> void:
	if enable_debug_log:
		print("BackgroundMusicController: " + message)
