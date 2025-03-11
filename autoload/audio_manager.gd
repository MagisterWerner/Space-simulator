extends Node

# Core signals
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
const DEFAULT_POOL_SIZE = 10
const MAX_POOL_SIZE = 30

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
var _initialized = false
var _buses_initialized = false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_initialize_audio_system")

func _initialize_audio_system():
	if _initialized: return
	
	_setup_audio_buses()
	_create_music_players()
	_load_settings()
	
	_initialized = true

func _setup_audio_buses():
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
	
	_apply_volume_settings()
	_buses_initialized = true
	audio_buses_initialized.emit()

func _create_music_players():
	_music_player = AudioStreamPlayer.new()
	_music_player.bus = MUSIC_BUS
	add_child(_music_player)
	_music_player.finished.connect(_on_music_finished)
	
	_next_music_player = AudioStreamPlayer.new()
	_next_music_player.bus = MUSIC_BUS
	_next_music_player.volume_db = MIN_DB
	add_child(_next_music_player)
	_next_music_player.finished.connect(_on_next_music_finished)

func _on_music_finished():
	music_finished.emit()

func _on_next_music_finished():
	pass # Handled by tween

func _load_settings():
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

func save_settings():
	var config_file = ConfigFile.new()
	
	for key in config:
		config_file.set_value("audio", key, config[key])
	
	config_file.save("user://audio_settings.cfg")

func _apply_volume_settings():
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

func _linear_to_db(linear_value):
	if linear_value <= 0: return MIN_DB
	return 20.0 * log(linear_value) / log(10.0)

func _db_to_linear(db_value):
	return pow(10.0, db_value / 20.0)

# Music Methods
func preload_music(track_name, file_path):
	if _loaded_music.has(track_name): return
	
	var stream = load(file_path)
	if !stream:
		push_error("AudioManager: Failed to load music: " + file_path)
		return
	
	_loaded_music[track_name] = stream

func unload_music(track_name):
	if _loaded_music.has(track_name):
		if _current_music == track_name:
			stop_music()
		_loaded_music.erase(track_name)

func play_music(track_name, crossfade = true):
	if not _initialized:
		call_deferred("play_music", track_name, crossfade)
		return
	
	if !config.music_enabled or (_current_music == track_name and _music_player.playing):
		return
	
	if !_loaded_music.has(track_name):
		push_error("AudioManager: Music track not loaded: " + track_name)
		return
	
	var track = _loaded_music[track_name]
	
	if crossfade and _current_music != null and _music_player.playing:
		_next_music_player.stream = track
		_next_music_player.volume_db = MIN_DB
		_next_music_player.play()
		
		if _music_tween:
			_music_tween.kill()
		_music_tween = create_tween()
		_music_tween.tween_property(_music_player, "volume_db", MIN_DB, config.music_fade_duration)
		_music_tween.parallel().tween_property(_next_music_player, "volume_db", 0, config.music_fade_duration)
		_music_tween.tween_callback(_swap_music_players)
	else:
		stop_music()
		_music_player.stream = track
		_music_player.play()
	
	_current_music = track_name
	music_changed.emit(track_name)

func stop_music():
	if _music_tween:
		_music_tween.kill()
	
	_music_player.stop()
	_next_music_player.stop()
	_current_music = null

func pause_music():
	_music_player.stream_paused = true
	_next_music_player.stream_paused = true

func resume_music():
	if !config.music_enabled: return
	
	_music_player.stream_paused = false
	_next_music_player.stream_paused = false

func _swap_music_players():
	var temp = _music_player
	_music_player = _next_music_player
	_next_music_player = temp
	_next_music_player.stop()

# SFX Methods
func preload_sfx(sfx_name, file_path, pool_size = DEFAULT_POOL_SIZE):
	if _loaded_sfx.has(sfx_name): return
	
	var stream = load(file_path)
	if !stream:
		push_error("AudioManager: Failed to load SFX: " + file_path)
		return
	
	_loaded_sfx[sfx_name] = stream
	_create_sfx_pool(sfx_name, pool_size)

func is_sfx_loaded(sfx_name):
	return _loaded_sfx.has(sfx_name)

func unload_sfx(sfx_name):
	if !_loaded_sfx.has(sfx_name): return
	
	_loaded_sfx.erase(sfx_name)
	
	if _sfx_pools.has(sfx_name):
		for player in _sfx_pools[sfx_name]:
			if is_instance_valid(player):
				player.queue_free()
		_sfx_pools.erase(sfx_name)

func _create_sfx_pool(sfx_name, pool_size):
	if !_loaded_sfx.has(sfx_name) or !_initialized:
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

func resize_sfx_pool(sfx_name, new_size):
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
						player.set_meta("remove_when_done", true)

func _on_sfx_finished(player, sfx_name):
	if not is_instance_valid(player): return
	
	if player.has_meta("remove_when_done") and player.get_meta("remove_when_done"):
		player.queue_free()
		if _sfx_pools.has(sfx_name):
			var idx = _sfx_pools[sfx_name].find(player)
			if idx >= 0:
				_sfx_pools[sfx_name].remove_at(idx)

func play_sfx(sfx_name, position = null, pitch_scale = 1.0, volume_db = 0.0):
	if not _initialized or !config.sfx_enabled:
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
	
	# If no player available, expand pool and try again
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

func play_sfx_with_culling(sfx_name, position, max_distance = 2000.0, pitch_scale = 1.0):
	var player_pos = Vector2.ZERO
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
	var volume_db = _linear_to_db(distance_factor) * 0.5
	
	return play_sfx(sfx_name, position, pitch_scale, volume_db)

func _find_available_sfx_player(sfx_name):
	if !_sfx_pools.has(sfx_name):
		return null
	
	for player in _sfx_pools[sfx_name]:
		if is_instance_valid(player) and !player.playing:
			return player
	
	return null

func stop_sfx(sfx_name):
	if !_sfx_pools.has(sfx_name):
		return
	
	for player in _sfx_pools[sfx_name]:
		if is_instance_valid(player):
			player.stop()

func stop_all_sfx():
	for sfx_name in _sfx_pools.keys():
		stop_sfx(sfx_name)

# Volume Control
func set_master_volume(volume):
	config.master_volume = clamp(volume, 0.0, 1.0)
	_apply_volume_settings()
	volume_changed.emit(MASTER_BUS, _linear_to_db(config.master_volume))

func set_music_volume(volume):
	config.music_volume = clamp(volume, 0.0, 1.0)
	_apply_volume_settings()
	volume_changed.emit(MUSIC_BUS, _linear_to_db(config.music_volume))

func set_sfx_volume(volume):
	config.sfx_volume = clamp(volume, 0.0, 1.0)
	_apply_volume_settings()
	volume_changed.emit(SFX_BUS, _linear_to_db(config.sfx_volume))

func set_music_enabled(enabled):
	config.music_enabled = enabled
	_apply_volume_settings()
	
	if !enabled:
		pause_music()
	else:
		resume_music()

func set_sfx_enabled(enabled):
	config.sfx_enabled = enabled
	_apply_volume_settings()
	
	if !enabled:
		stop_all_sfx()

func set_music_fade_duration(duration):
	config.music_fade_duration = max(0.1, duration)

func set_positional_audio(enabled):
	if config.positional_audio == enabled:
		return
		
	config.positional_audio = enabled
	
	# Rebuild all pools with appropriate player types
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

func get_current_music():
	return _current_music if _current_music else ""

func is_music_playing():
	return is_instance_valid(_music_player) and _music_player.playing || is_instance_valid(_next_music_player) and _next_music_player.playing

# Batch loading helpers
func preload_sfx_directory(directory_path, recursive = false):
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
				elif file_name.ends_with(".wav") or file_name.ends_with(".sfxr"):
					var sfx_name = file_name.get_basename()
					preload_sfx(sfx_name, full_path)
				
			file_name = dir.get_next()
		
		dir.list_dir_end()

func preload_music_directory(directory_path, recursive = false):
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
				elif file_name.ends_with(".mp3") or file_name.ends_with(".ogg"):
					var track_name = file_name.get_basename()
					preload_music(track_name, full_path)
				
			file_name = dir.get_next()
		
		dir.list_dir_end()

func is_initialized():
	return _initialized and _buses_initialized
