# autoload/audio_manager.gd
# =========================
# Purpose:
#   Comprehensive audio management system for background music and sound effects.
#   Designed for high-performance in bullet-hell style games with optimized audio pooling.
#   Handles volume control, audio buses, and persistence of audio settings.
#
# Interface:
#   Signals:
#     - music_changed(track_name)
#     - volume_changed(bus_name, volume_db)
#
#   Music Methods:
#     - preload_music(track_name, file_path)
#     - preload_music_directory(directory_path, recursive)
#     - play_music(track_name, crossfade)
#     - stop_music()
#     - pause_music()
#     - resume_music()
#
#   SFX Methods:
#     - preload_sfx(sfx_name, file_path, pool_size)
#     - preload_sfx_directory(directory_path, recursive)
#     - play_sfx(sfx_name, position, pitch_scale, volume_db)
#     - play_sfx_with_culling(sfx_name, position, max_distance, pitch_scale)
#     - stop_sfx(sfx_name)
#     - stop_all_sfx()
#     - resize_sfx_pool(sfx_name, new_size)
#
#   Volume Control:
#     - set_master_volume(volume)
#     - set_music_volume(volume)
#     - set_sfx_volume(volume)
#     - set_music_enabled(enabled)
#     - set_sfx_enabled(enabled)
#     - save_settings()
#
# Dependencies:
#   - None
#
# Usage Example:
#   # Initialize audio resources
#   AudioManager.preload_music("main_theme", "res://audio/music/main_theme.ogg")
#   AudioManager.preload_sfx("laser", "res://audio/sfx/laser.wav", 30)
#   
#   # Play audio
#   AudioManager.play_music("main_theme")
#   AudioManager.play_sfx("laser", player_position, randf_range(0.95, 1.05))

extends Node

# Signal declarations
signal music_changed(track_name)
signal volume_changed(bus_name, volume_db)
signal music_finished
signal sfx_pool_created(sfx_name, pool_size)
signal audio_buses_initialized

# Constants
const MUSIC_BUS = "Music"
const SFX_BUS = "SFX"
const MASTER_BUS = "Master"

const MIN_DB = -80.0
const MAX_DB = 0.0

# Configuration
var config = {
	"music_enabled": true,
	"sfx_enabled": true,
	"music_volume": 0.8,
	"sfx_volume": 1.0,
	"master_volume": 1.0,
	"music_fade_duration": 1.0,
	"positional_audio": true
}

# Resource tracking
var _loaded_music = {}
var _loaded_sfx = {}
var _current_music = null
var _music_player = null
var _next_music_player = null
var _sfx_pools = {}
var _music_tween = null

# Pool configuration
const DEFAULT_POOL_SIZE = 10
const MAX_POOL_SIZE = 30

# Initialization flags
var _initialized = false
var _buses_initialized = false

# Initialization
func _ready() -> void:
	# Call deferred to ensure this runs after scene tree is ready
	call_deferred("_initialize_audio_system")
	
	# Make this node process even when game is paused
	process_mode = Node.PROCESS_MODE_ALWAYS

# Deferred initialization to ensure this happens after all other autoloads
func _initialize_audio_system() -> void:
	if _initialized:
		return
		
	# Log initialization
	print("AudioManager: Initializing audio system...")
	
	# Setup audio buses
	_setup_audio_buses()
	
	# Create music players
	_create_music_players()
	
	# Load saved settings
	_load_settings()
	
	_initialized = true
	print("AudioManager: Audio system initialized successfully")

# Create necessary audio buses if they don't exist
func _setup_audio_buses() -> void:
	var _audio_bus_count = AudioServer.get_bus_count()
	
	# Check for Master bus (should always exist as bus 0)
	if AudioServer.get_bus_name(0) != MASTER_BUS:
		push_warning("AudioManager: Master bus not found at index 0, audio routing may not work correctly")
	
	# Create Music bus if needed
	var music_bus_idx = AudioServer.get_bus_index(MUSIC_BUS)
	if music_bus_idx == -1:
		music_bus_idx = AudioServer.get_bus_count()
		AudioServer.add_bus()
		AudioServer.set_bus_name(music_bus_idx, MUSIC_BUS)
		AudioServer.set_bus_send(music_bus_idx, "Master")
	
	# Create SFX bus if needed
	var sfx_bus_idx = AudioServer.get_bus_index(SFX_BUS)
	if sfx_bus_idx == -1:
		sfx_bus_idx = AudioServer.get_bus_count()
		AudioServer.add_bus()
		AudioServer.set_bus_name(sfx_bus_idx, SFX_BUS)
		AudioServer.set_bus_send(sfx_bus_idx, "Master")
	
	# Apply initial volume settings
	_apply_volume_settings()
	
	_buses_initialized = true
	audio_buses_initialized.emit()

# Create AudioStreamPlayers for music
func _create_music_players() -> void:
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	_music_player.volume_db = 0
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)
	
	_next_music_player = AudioStreamPlayer.new()
	_next_music_player.bus = MUSIC_BUS
	_next_music_player.volume_db = MIN_DB  # Start silent
	add_child(_next_music_player)
	_next_music_player.finished.connect(_on_next_music_finished)

func _on_music_finished() -> void:
	music_finished.emit()

func _on_next_music_finished() -> void:
	# Only handle if we're in the middle of a crossfade
	if _music_tween and _music_tween.is_running():
		pass # Let the tween handle it

# Load saved settings
func _load_settings() -> void:
	if FileAccess.file_exists("user://audio_settings.cfg"):
		var config_file = ConfigFile.new()
		var err = config_file.load("user://audio_settings.cfg")
		if err == OK:
			config.music_enabled = config_file.get_value("audio", "music_enabled", config.music_enabled)
			config.sfx_enabled = config_file.get_value("audio", "sfx_enabled", config.sfx_enabled)
			config.music_volume = config_file.get_value("audio", "music_volume", config.music_volume)
			config.sfx_volume = config_file.get_value("audio", "sfx_volume", config.sfx_volume)
			config.master_volume = config_file.get_value("audio", "master_volume", config.master_volume)
			config.music_fade_duration = config_file.get_value("audio", "music_fade_duration", config.music_fade_duration)
			config.positional_audio = config_file.get_value("audio", "positional_audio", config.positional_audio)
			
			_apply_volume_settings()

# Save settings
func save_settings() -> void:
	var config_file = ConfigFile.new()
	
	config_file.set_value("audio", "music_enabled", config.music_enabled)
	config_file.set_value("audio", "sfx_enabled", config.sfx_enabled)
	config_file.set_value("audio", "music_volume", config.music_volume)
	config_file.set_value("audio", "sfx_volume", config.sfx_volume)
	config_file.set_value("audio", "master_volume", config.master_volume)
	config_file.set_value("audio", "music_fade_duration", config.music_fade_duration)
	config_file.set_value("audio", "positional_audio", config.positional_audio)
	
	config_file.save("user://audio_settings.cfg")

# Apply volume settings to buses
func _apply_volume_settings() -> void:
	var master_bus_idx = AudioServer.get_bus_index(MASTER_BUS)
	var music_bus_idx = AudioServer.get_bus_index(MUSIC_BUS)
	var sfx_bus_idx = AudioServer.get_bus_index(SFX_BUS)
	
	if master_bus_idx >= 0:
		var volume_db = _linear_to_db(config.master_volume)
		AudioServer.set_bus_volume_db(master_bus_idx, volume_db)
		AudioServer.set_bus_mute(master_bus_idx, config.master_volume <= 0)
	
	if music_bus_idx >= 0:
		var volume_db = _linear_to_db(config.music_volume)
		AudioServer.set_bus_volume_db(music_bus_idx, volume_db)
		AudioServer.set_bus_mute(music_bus_idx, !config.music_enabled || config.music_volume <= 0)
	
	if sfx_bus_idx >= 0:
		var volume_db = _linear_to_db(config.sfx_volume)
		AudioServer.set_bus_volume_db(sfx_bus_idx, volume_db)
		AudioServer.set_bus_mute(sfx_bus_idx, !config.sfx_enabled || config.sfx_volume <= 0)

# Convert linear volume (0.0 to 1.0) to decibels
func _linear_to_db(linear_value: float) -> float:
	if linear_value <= 0:
		return MIN_DB
	return 20.0 * log(linear_value) / log(10.0)

# Convert decibels to linear volume (0.0 to 1.0)
func _db_to_linear(db_value: float) -> float:
	return pow(10.0, db_value / 20.0)

# MUSIC METHODS

# Preload a music track
func preload_music(track_name: String, file_path: String) -> void:
	if _loaded_music.has(track_name):
		return
	
	var stream = load(file_path)
	if !stream:
		push_error("AudioManager: Failed to load music: " + file_path)
		return
	
	_loaded_music[track_name] = stream

# Unload a music track
func unload_music(track_name: String) -> void:
	if _loaded_music.has(track_name):
		if _current_music == track_name:
			stop_music()
		_loaded_music.erase(track_name)

# Play a music track with optional crossfade
func play_music(track_name: String, crossfade: bool = true) -> void:
	# Make sure we're initialized
	if not _initialized:
		push_warning("AudioManager: Attempting to play music before initialization, deferring...")
		call_deferred("play_music", track_name, crossfade)
		return
	
	if !config.music_enabled:
		return
	
	if _current_music == track_name and _music_player.playing:
		return
	
	# Load the track if not already loaded
	if !_loaded_music.has(track_name):
		push_error("AudioManager: Music track not loaded: " + track_name)
		return
	
	var track = _loaded_music[track_name]
	
	if crossfade and _current_music != null and _music_player.playing:
		# Set up the next track
		_next_music_player.stream = track
		_next_music_player.volume_db = MIN_DB
		_next_music_player.play()
		
		# Create tween for crossfade
		if _music_tween:
			_music_tween.kill()
		_music_tween = create_tween()
		_music_tween.tween_property(_music_player, "volume_db", MIN_DB, config.music_fade_duration)
		_music_tween.parallel().tween_property(_next_music_player, "volume_db", 0, config.music_fade_duration)
		_music_tween.tween_callback(_swap_music_players)
	else:
		# Just play immediately
		stop_music()
		_music_player.stream = track
		_music_player.play()
	
	_current_music = track_name
	music_changed.emit(track_name)

# Stop the currently playing music
func stop_music() -> void:
	if _music_tween:
		_music_tween.kill()
	
	_music_player.stop()
	_next_music_player.stop()
	_current_music = null

# Pause the music
func pause_music() -> void:
	_music_player.stream_paused = true
	_next_music_player.stream_paused = true

# Resume the music
func resume_music() -> void:
	if !config.music_enabled:
		return
	
	_music_player.stream_paused = false
	_next_music_player.stream_paused = false

# Swap music players after crossfade
func _swap_music_players() -> void:
	var temp = _music_player
	_music_player = _next_music_player
	_next_music_player = temp
	_next_music_player.stop()

# SOUND EFFECT METHODS

# Preload a sound effect
func preload_sfx(sfx_name: String, file_path: String, pool_size: int = DEFAULT_POOL_SIZE) -> void:
	if _loaded_sfx.has(sfx_name):
		return
	
	var stream = load(file_path)
	if !stream:
		push_error("AudioManager: Failed to load SFX: " + file_path)
		return
	
	_loaded_sfx[sfx_name] = stream
	_create_sfx_pool(sfx_name, pool_size)

# Check if a sound is loaded
func is_sfx_loaded(sfx_name: String) -> bool:
	return _loaded_sfx.has(sfx_name)

# Unload a sound effect
func unload_sfx(sfx_name: String) -> void:
	if _loaded_sfx.has(sfx_name):
		_loaded_sfx.erase(sfx_name)
		
		# Clean up pool
		if _sfx_pools.has(sfx_name):
			for player in _sfx_pools[sfx_name]:
				if is_instance_valid(player):
					player.queue_free()
			_sfx_pools.erase(sfx_name)

# Create a pool of audio players for a sound effect
func _create_sfx_pool(sfx_name: String, pool_size: int) -> void:
	if !_loaded_sfx.has(sfx_name):
		return
	
	# Make sure we're initialized
	if not _initialized:
		call_deferred("_create_sfx_pool", sfx_name, pool_size)
		return
	
	pool_size = clamp(pool_size, 1, MAX_POOL_SIZE)
	
	var pool = []
	for i in range(pool_size):
		var player
		
		if config.positional_audio:
			player = AudioStreamPlayer2D.new()
			player.max_distance = 2000
			player.attenuation = 1.0
		else:
			player = AudioStreamPlayer.new()
		
		player.stream = _loaded_sfx[sfx_name]
		player.bus = SFX_BUS
		player.finished.connect(_on_sfx_finished.bind(player, sfx_name))
		player.name = "SFX_" + sfx_name + "_" + str(i)
		add_child(player)
		pool.append(player)
	
	_sfx_pools[sfx_name] = pool
	sfx_pool_created.emit(sfx_name, pool_size)

# Resize a sound effect pool
func resize_sfx_pool(sfx_name: String, new_size: int) -> void:
	new_size = clamp(new_size, 1, MAX_POOL_SIZE)
	
	if !_sfx_pools.has(sfx_name):
		if _loaded_sfx.has(sfx_name):
			_create_sfx_pool(sfx_name, new_size)
		return
	
	var current_size = _sfx_pools[sfx_name].size()
	
	if new_size > current_size:
		# Add more players
		for i in range(current_size, new_size):
			var player
			
			if config.positional_audio:
				player = AudioStreamPlayer2D.new()
				player.max_distance = 2000
				player.attenuation = 1.0
			else:
				player = AudioStreamPlayer.new()
			
			player.stream = _loaded_sfx[sfx_name]
			player.bus = SFX_BUS
			player.finished.connect(_on_sfx_finished.bind(player, sfx_name))
			player.name = "SFX_" + sfx_name + "_" + str(i)
			add_child(player)
			_sfx_pools[sfx_name].append(player)
	elif new_size < current_size:
		# Remove excess players
		for i in range(new_size, current_size):
			if i < _sfx_pools[sfx_name].size():
				var player = _sfx_pools[sfx_name][i]
				if is_instance_valid(player):
					if !player.playing:
						player.queue_free()
						_sfx_pools[sfx_name].remove_at(i)
					else:
						# Mark for later removal
						player.set_meta("remove_when_done", true)

# Handle finished sound effect
func _on_sfx_finished(player: Node, sfx_name: String) -> void:
	if not is_instance_valid(player):
		return
		
	if player.has_meta("remove_when_done") and player.get_meta("remove_when_done"):
		player.queue_free()
		if _sfx_pools.has(sfx_name):
			var idx = _sfx_pools[sfx_name].find(player)
			if idx >= 0:
				_sfx_pools[sfx_name].remove_at(idx)

# Play a sound effect
func play_sfx(sfx_name: String, position = null, pitch_scale: float = 1.0, volume_db: float = 0.0) -> Node:
	# Make sure we're initialized
	if not _initialized:
		push_warning("AudioManager: Attempting to play sound before initialization")
		return null
	
	if !config.sfx_enabled:
		return null
	
	if !_loaded_sfx.has(sfx_name):
		push_error("AudioManager: Sound effect not loaded: " + sfx_name)
		return null
	
	if !_sfx_pools.has(sfx_name):
		_create_sfx_pool(sfx_name, DEFAULT_POOL_SIZE)
	
	# Find an available player
	var player = _find_available_sfx_player(sfx_name)
	
	if player:
		player.pitch_scale = pitch_scale
		player.volume_db = volume_db
		
		if player is AudioStreamPlayer2D and position != null:
			player.position = position
		
		player.play()
		return player
	
	# If no player is available, expand pool and try again
	if _sfx_pools[sfx_name].size() < MAX_POOL_SIZE:
		resize_sfx_pool(sfx_name, _sfx_pools[sfx_name].size() + min(5, MAX_POOL_SIZE - _sfx_pools[sfx_name].size()))
		return play_sfx(sfx_name, position, pitch_scale, volume_db)
	
	# If still no player available, use oldest playing one
	var oldest_player = _sfx_pools[sfx_name][0]
	oldest_player.stop()
	
	oldest_player.pitch_scale = pitch_scale
	oldest_player.volume_db = volume_db
	
	if oldest_player is AudioStreamPlayer2D and position != null:
		oldest_player.position = position
	
	oldest_player.play()
	return oldest_player

# Play sound with distance-based culling
func play_sfx_with_culling(sfx_name: String, position: Vector2, max_distance: float = 2000.0, pitch_scale: float = 1.0) -> Node:
	# Find player position
	var player_pos = Vector2.ZERO
	
	# Find player position from EntityManager or player group
	var player_ships = get_tree().get_nodes_in_group("player")
	if not player_ships.is_empty() and is_instance_valid(player_ships[0]):
		player_pos = player_ships[0].global_position
	
	var distance = position.distance_to(player_pos)
	
	# Don't play sounds beyond the maximum distance
	if distance > max_distance:
		return null
		
	# Adjust volume based on distance
	var audible_distance = max_distance * 0.8
	var distance_factor = clamp(1.0 - (distance / audible_distance), 0.0, 1.0)
	var volume_db = _linear_to_db(distance_factor) * 0.5  # Scale to reasonable dB range
	
	return play_sfx(sfx_name, position, pitch_scale, volume_db)

# Find an available sound effect player from pool
func _find_available_sfx_player(sfx_name: String) -> Node:
	if !_sfx_pools.has(sfx_name):
		return null
	
	# First try to find a non-playing player
	for player in _sfx_pools[sfx_name]:
		if is_instance_valid(player) and !player.playing:
			return player
	
	return null

# Stop all instances of a sound effect
func stop_sfx(sfx_name: String) -> void:
	if !_sfx_pools.has(sfx_name):
		return
	
	for player in _sfx_pools[sfx_name]:
		if is_instance_valid(player):
			player.stop()

# Stop all sound effects
func stop_all_sfx() -> void:
	for sfx_name in _sfx_pools.keys():
		stop_sfx(sfx_name)

# VOLUME CONTROL

# Set master volume (0.0 to 1.0)
func set_master_volume(volume: float) -> void:
	config.master_volume = clamp(volume, 0.0, 1.0)
	_apply_volume_settings()
	volume_changed.emit(MASTER_BUS, _linear_to_db(config.master_volume))

# Set music volume (0.0 to 1.0)
func set_music_volume(volume: float) -> void:
	config.music_volume = clamp(volume, 0.0, 1.0)
	_apply_volume_settings()
	volume_changed.emit(MUSIC_BUS, _linear_to_db(config.music_volume))

# Set SFX volume (0.0 to 1.0)
func set_sfx_volume(volume: float) -> void:
	config.sfx_volume = clamp(volume, 0.0, 1.0)
	_apply_volume_settings()
	volume_changed.emit(SFX_BUS, _linear_to_db(config.sfx_volume))

# Enable/disable music
func set_music_enabled(enabled: bool) -> void:
	config.music_enabled = enabled
	_apply_volume_settings()
	
	if !enabled:
		pause_music()
	else:
		resume_music()

# Enable/disable sound effects
func set_sfx_enabled(enabled: bool) -> void:
	config.sfx_enabled = enabled
	_apply_volume_settings()
	
	if !enabled:
		stop_all_sfx()

# Set music fade duration
func set_music_fade_duration(duration: float) -> void:
	config.music_fade_duration = max(0.1, duration)

# Enable/disable positional audio
func set_positional_audio(enabled: bool) -> void:
	var previous_value = config.positional_audio
	config.positional_audio = enabled
	
	# If setting changed, rebuild all pools with appropriate player types
	if previous_value != enabled:
		var sfx_names = _sfx_pools.keys()
		for sfx_name in sfx_names:
			var pool_size = _sfx_pools[sfx_name].size()
			
			# Clean up existing pool
			for player in _sfx_pools[sfx_name]:
				if is_instance_valid(player):
					player.queue_free()
			_sfx_pools.erase(sfx_name)
			
			# Recreate with new setting
			_create_sfx_pool(sfx_name, pool_size)

# Utility method to get current music track
func get_current_music() -> String:
	return _current_music if _current_music else ""

# Utility method to get if music is playing
func is_music_playing() -> bool:
	return is_instance_valid(_music_player) and _music_player.playing || is_instance_valid(_next_music_player) and _next_music_player.playing

# Helper for batch loading multiple files
func preload_sfx_directory(directory_path: String, recursive: bool = false) -> void:
	if not DirAccess.dir_exists_absolute(directory_path):
		push_error("AudioManager: Directory not found: " + directory_path)
		return
		
	var dir = DirAccess.open(directory_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path = directory_path + "/" + file_name
				
				if dir.current_is_dir() and recursive:
					preload_sfx_directory(full_path, recursive)
				else:
					if file_name.ends_with(".wav") or file_name.ends_with(".sfxr"):
						var sfx_name = file_name.get_basename()
						preload_sfx(sfx_name, full_path)
				
				file_name = dir.get_next()
		
		dir.list_dir_end()

# Helper for batch loading multiple music files
func preload_music_directory(directory_path: String, recursive: bool = false) -> void:
	if not DirAccess.dir_exists_absolute(directory_path):
		push_error("AudioManager: Directory not found: " + directory_path)
		return
		
	var dir = DirAccess.open(directory_path)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		
		while file_name != "":
			if file_name != "." and file_name != "..":
				var full_path = directory_path + "/" + file_name
				
				if dir.current_is_dir() and recursive:
					preload_music_directory(full_path, recursive)
				else:
					if file_name.ends_with(".mp3") or file_name.ends_with(".ogg"):
						var track_name = file_name.get_basename()
						preload_music(track_name, full_path)
				
				file_name = dir.get_next()
		
		dir.list_dir_end()

# Get initialization status
func is_initialized() -> bool:
	return _initialized and _buses_initialized
