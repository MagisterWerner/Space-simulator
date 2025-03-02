extends Node
class_name GameSoundSystem

# Bus indices - these should match your AudioBus setup in Project Settings
const MASTER_BUS_IDX = 0
const MUSIC_BUS_IDX = 1
const SFX_BUS_IDX = 2

# Audio resources
var laser_sound: AudioStream
var missile_sound: AudioStream
var thruster_sound: AudioStream
var music_track: AudioStream

# Collections of active audio players
var active_players: Dictionary = {}
var thruster_players: Dictionary = {}
var missile_players: Dictionary = {}
var music_player: AudioStreamPlayer = null

# Sound effect pool for optimization
var sfx_pool: Array[AudioStreamPlayer] = []
const POOL_SIZE = 16  # Adjust based on your needs

# Default volumes
var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 1.0

# Signals
signal sound_finished(sound_id: String)

func _ready() -> void:
	# Load sound resources
	_load_sound_resources()
	
	# Initialize sound effect pool
	_initialize_sound_pool()
	
	# Start background music
	play_music()
	
	# Set initial volumes
	set_master_volume(master_volume)
	set_music_volume(music_volume)
	set_sfx_volume(sfx_volume)

func _load_sound_resources() -> void:
	# Load laser sound from sfxr file
	var laser_sfxr_path = "res://sounds/laser.sfxr"
	if ResourceLoader.exists(laser_sfxr_path):
		laser_sound = load(laser_sfxr_path)
	else:
		print_debug("Warning: Could not load laser.sfxr")
	
	# Load missile sound from sfxr file
	var missile_sfxr_path = "res://sounds/missile.sfxr"
	if ResourceLoader.exists(missile_sfxr_path):
		missile_sound = load(missile_sfxr_path)
	else:
		print_debug("Warning: Could not load missile.sfxr")
	
	# Load thruster OGG file
	var thruster_path = "res://sounds/thruster.ogg"
	if ResourceLoader.exists(thruster_path):
		thruster_sound = load(thruster_path)
	else:
		print_debug("Warning: Could not load thruster.ogg")
	
	# Load background music
	var music_path = "res://music/safety2.ogg"
	if ResourceLoader.exists(music_path):
		music_track = load(music_path)
	else:
		print_debug("Warning: Could not load background music")

func _initialize_sound_pool() -> void:
	for i in range(POOL_SIZE):
		var player = AudioStreamPlayer.new()
		player.bus = "SFX"
		player.finished.connect(_on_sound_finished.bind(player))
		add_child(player)
		player.name = "SFXPlayer_" + str(i)
		sfx_pool.append(player)

func play_music() -> void:
	if music_track == null:
		print_debug("Cannot play music: music track not loaded")
		return
		
	if music_player == null:
		music_player = AudioStreamPlayer.new()
		music_player.bus = "Music"
		add_child(music_player)
		music_player.name = "MusicPlayer"
	
	music_player.stream_paused = false
	music_player.stream = music_track
	music_player.volume_db = linear_to_db(music_volume)
	
	# Set to loop
	if music_player.stream:
		if music_player.stream is AudioStreamOggVorbis:
			music_player.stream.loop = true
	
	music_player.play()

func stop_music() -> void:
	if music_player != null:
		music_player.stop()

func pause_music() -> void:
	if music_player != null:
		music_player.stream_paused = true

func resume_music() -> void:
	if music_player != null:
		music_player.stream_paused = false

# Gets an available player from the pool or creates a new one if needed
func _get_audio_player() -> AudioStreamPlayer:
	for player in sfx_pool:
		if not player.playing:
			return player
	
	# If all players are in use, create a new one (less optimal but ensures sounds play)
	print_debug("Sound pool exhausted - consider increasing POOL_SIZE")
	var player = AudioStreamPlayer.new()
	player.bus = "SFX"
	player.finished.connect(_on_sound_finished.bind(player))
	add_child(player)
	sfx_pool.append(player)
	return player

# Play a laser sound effect
func play_laser(position: Vector2 = Vector2.ZERO) -> String:
	if laser_sound == null:
		print_debug("Cannot play laser sound: not loaded")
		return ""
		
	var player = _get_audio_player()
	player.stream = laser_sound
	player.volume_db = linear_to_db(sfx_volume)
	player.pitch_scale = randf_range(0.95, 1.05)  # Slight variation
	player.play()
	
	var sound_id = "laser_" + str(player.get_instance_id())
	active_players[sound_id] = player
	return sound_id

# Play a missile sound effect continuously
func play_missile(entity_id: int) -> void:
	if missile_sound == null:
		print_debug("Cannot play missile sound: not loaded")
		return
		
	if missile_players.has(entity_id):
		# Already playing for this missile
		return
	
	var player = _get_audio_player()
	player.stream = missile_sound
	player.volume_db = linear_to_db(sfx_volume * 0.7)
	player.pitch_scale = randf_range(0.9, 1.1)  # Some variation
	
	# Enable looping for missile sounds
	if player.stream is AudioStreamOggVorbis:
		player.stream.loop = true
	
	player.play()
	
	missile_players[entity_id] = player
	var sound_id = "missile_" + str(entity_id)
	active_players[sound_id] = player

# Stop missile sound for a specific entity
func stop_missile(entity_id: int) -> void:
	if missile_players.has(entity_id):
		var player = missile_players[entity_id]
		player.stop()
		
		var sound_id = "missile_" + str(entity_id)
		if active_players.has(sound_id):
			active_players.erase(sound_id)
		
		missile_players.erase(entity_id)

# Start playing thruster sound (continuous)
func start_thruster(entity_id: int) -> void:
	if thruster_sound == null:
		print_debug("Cannot play thruster sound: not loaded")
		return
		
	if thruster_players.has(entity_id):
		# Already playing for this entity
		return
	
	var player = _get_audio_player()
	player.stream = thruster_sound
	player.volume_db = linear_to_db(sfx_volume * 0.6)  # Slightly quieter
	player.pitch_scale = randf_range(0.9, 1.1)  # More variation for thrusters
	
	# Enable looping for thruster sounds
	if player.stream is AudioStreamOggVorbis:
		player.stream.loop = true
	
	player.play()
	
	thruster_players[entity_id] = player
	var sound_id = "thruster_" + str(entity_id)
	active_players[sound_id] = player

# Stop thruster sound for a specific entity
func stop_thruster(entity_id: int) -> void:
	if thruster_players.has(entity_id):
		var player = thruster_players[entity_id]
		player.stop()
		
		var sound_id = "thruster_" + str(entity_id)
		if active_players.has(sound_id):
			active_players.erase(sound_id)
		
		thruster_players.erase(entity_id)

# Generic method to play any sound at a specified volume and pitch
func play_sound(stream: AudioStream, volume: float = 1.0, pitch: float = 1.0) -> String:
	if stream == null:
		print_debug("Cannot play sound: stream is null")
		return ""
		
	var player = _get_audio_player()
	player.stream = stream
	player.volume_db = linear_to_db(volume * sfx_volume)
	player.pitch_scale = pitch
	player.play()
	
	var sound_id = "sound_" + str(player.get_instance_id())
	active_players[sound_id] = player
	return sound_id

# Stop a specific sound
func stop_sound(sound_id: String) -> bool:
	if active_players.has(sound_id):
		active_players[sound_id].stop()
		active_players.erase(sound_id)
		return true
	return false

# Stop all sounds except music
func stop_all_sounds() -> void:
	for player in sfx_pool:
		player.stop()
	
	active_players.clear()
	thruster_players.clear()
	missile_players.clear()

# Volume control methods
func set_master_volume(vol: float) -> void:
	master_volume = clamp(vol, 0.0, 1.0)
	AudioServer.set_bus_volume_db(MASTER_BUS_IDX, linear_to_db(master_volume))

func set_music_volume(vol: float) -> void:
	music_volume = clamp(vol, 0.0, 1.0)
	AudioServer.set_bus_volume_db(MUSIC_BUS_IDX, linear_to_db(music_volume))
	
	if music_player != null:
		music_player.volume_db = linear_to_db(music_volume)

func set_sfx_volume(vol: float) -> void:
	sfx_volume = clamp(vol, 0.0, 1.0)
	AudioServer.set_bus_volume_db(SFX_BUS_IDX, linear_to_db(sfx_volume))

# Callback when a sound finishes playing
func _on_sound_finished(player: AudioStreamPlayer) -> void:
	var finished_sound_id = ""
	
	for sound_id in active_players:
		if active_players[sound_id] == player:
			finished_sound_id = sound_id
			break
	
	if finished_sound_id != "":
		active_players.erase(finished_sound_id)
		sound_finished.emit(finished_sound_id)

# Utility method to check if a specific sound is playing
func is_sound_playing(sound_id: String) -> bool:
	return active_players.has(sound_id) and active_players[sound_id].playing
