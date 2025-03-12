# scripts/audio/background_music_controller.gd
# Purpose: Handles background music initialization and management
extends Node

const BACKGROUND_MUSIC_PATH = "res://assets/audio/space.ogg"
const MUSIC_TRACK_ID = "background_music"

@export var start_music_on_ready: bool = true
@export var enable_debug_log: bool = false
@export var music_fade_time: float = 1.0

var _initialized: bool = false
var _music_loaded: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Initialize music system
	_initialize_music()
	
	# Connect to game signals if EventManager exists
	if has_node("/root/EventManager"):
		var events = ["game_started", "game_paused", "game_resumed", "game_over", "game_restarted"]
		for event in events:
			EventManager.safe_connect(event, Callable(self, "_on_" + event))

func _initialize_music() -> void:
	if _initialized:
		return
		
	if not has_node("/root/AudioManager"):
		push_error("BackgroundMusicController: AudioManager not found!")
		return
	
	# Wait for AudioManager if needed
	if not AudioManager.is_initialized():
		debug_print("Waiting for AudioManager to initialize...")
		await get_tree().create_timer(0.5).timeout
		_initialize_music()
		return
	
	# Load and start music
	AudioManager.preload_music(MUSIC_TRACK_ID, BACKGROUND_MUSIC_PATH)
	_music_loaded = true
	
	if start_music_on_ready:
		AudioManager.play_music(MUSIC_TRACK_ID, true)
		debug_print("Background music started")
	
	_initialized = true
	debug_print("Music controller initialized")

# Game event handlers
func _on_game_started() -> void:
	if _initialized and _music_loaded and not AudioManager.is_music_playing():
		AudioManager.play_music(MUSIC_TRACK_ID, true)

func _on_game_paused() -> void:
	# Optional: modify music when game is paused
	pass

func _on_game_resumed() -> void:
	# Optional: restore music when game is resumed
	pass

func _on_game_over() -> void:
	# Optional: change music on game over
	pass

func _on_game_restarted() -> void:
	if _initialized and _music_loaded:
		AudioManager.play_music(MUSIC_TRACK_ID, true)

func debug_print(message: String) -> void:
	if enable_debug_log:
		print("BackgroundMusicController: " + message)
