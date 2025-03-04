# sound_manager.gd
extends Node
class_name GameSoundSystem

const MASTER_BUS_IDX = 0
const MUSIC_BUS_IDX = 1
const SFX_BUS_IDX = 2

var laser_sound: AudioStream
var missile_sound: AudioStream
var thruster_sound: AudioStream
var music_track: AudioStream
var fire_explosion_sound: AudioStream
var debris_explosion_sound: AudioStream

var active_players: Dictionary = {}
var thruster_players: Dictionary = {}
var missile_players: Dictionary = {}
var music_player: AudioStreamPlayer = null

var sfx_pool: Array[AudioStreamPlayer] = []
const POOL_SIZE = 16

var master_volume: float = 1.0
var music_volume: float = 0.7
var sfx_volume: float = 1.0

signal sound_finished(sound_id: String)

func _ready() -> void:
	_load_sound_resources()
	_initialize_sound_pool()
	play_music()
	
	set_master_volume(master_volume)
	set_music_volume(music_volume)
	set_sfx_volume(sfx_volume)

func _load_sound_resources() -> void:
	var sound_paths = {
		"laser": "res://sounds/laser.sfxr",
		"missile": "res://sounds/missile.sfxr",
		"thruster": "res://sounds/thruster.wav",
		"fire_explosion": "res://sounds/explosion_fire.wav",
		"debris_explosion": "res://sounds/explosion_debris.wav",
		"music": "res://music/space.ogg"
	}
	
	for key in sound_paths:
		var path = sound_paths[key]
		if ResourceLoader.exists(path):
			match key:
				"laser": laser_sound = load(path)
				"missile": missile_sound = load(path)
				"thruster": thruster_sound = load(path)
				"fire_explosion": fire_explosion_sound = load(path)
				"debris_explosion": debris_explosion_sound = load(path)
				"music": music_track = load(path)

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
		return
		
	if music_player == null:
		music_player = AudioStreamPlayer.new()
		music_player.bus = "Music"
		add_child(music_player)
		music_player.name = "MusicPlayer"
	
	music_player.stream_paused = false
	music_player.stream = music_track
	music_player.volume_db = linear_to_db(music_volume)
	
	if music_player.stream is AudioStreamOggVorbis:
		music_player.stream.loop = true
	
	music_player.play()

func stop_music() -> void:
	if music_player:
		music_player.stop()

func pause_music() -> void:
	if music_player:
		music_player.stream_paused = true

func resume_music() -> void:
	if music_player:
		music_player.stream_paused = false

func _get_audio_player() -> AudioStreamPlayer:
	for player in sfx_pool:
		if not player.playing:
			return player
	
	var player = AudioStreamPlayer.new()
	player.bus = "SFX"
	player.finished.connect(_on_sound_finished.bind(player))
	add_child(player)
	sfx_pool.append(player)
	return player

func play_laser(_position: Vector2 = Vector2.ZERO) -> String:
	if laser_sound == null:
		return ""
		
	var player = _get_audio_player()
	player.stream = laser_sound
	player.volume_db = linear_to_db(sfx_volume)
	player.pitch_scale = randf_range(0.95, 1.05)
	player.play()
	
	var sound_id = "laser_" + str(player.get_instance_id())
	active_players[sound_id] = player
	return sound_id

func play_explosion(position: Vector2, is_fire: bool = false) -> String:
	var explosion_sound = fire_explosion_sound if is_fire else debris_explosion_sound
	
	if explosion_sound == null:
		return ""
	
	var player = _get_audio_player()
	player.stream = explosion_sound
	player.volume_db = linear_to_db(sfx_volume * 0.8)
	player.pitch_scale = randf_range(0.9, 1.1)
	player.play()
	
	var sound_id = "explosion_" + str(player.get_instance_id())
	active_players[sound_id] = player
	return sound_id

func play_missile(entity_id: int) -> void:
	if missile_sound == null or missile_players.has(entity_id):
		return
	
	var player = _get_audio_player()
	player.stream = missile_sound
	player.volume_db = linear_to_db(sfx_volume * 0.7)
	player.pitch_scale = randf_range(0.9, 1.1)
	
	if player.stream is AudioStreamOggVorbis:
		player.stream.loop = true
	
	player.play()
	
	missile_players[entity_id] = player
	var sound_id = "missile_" + str(entity_id)
	active_players[sound_id] = player

func stop_missile(entity_id: int) -> void:
	if not missile_players.has(entity_id):
		return
		
	var player = missile_players[entity_id]
	player.stop()
	
	var sound_id = "missile_" + str(entity_id)
	active_players.erase(sound_id)
	missile_players.erase(entity_id)

func start_thruster(entity_id: int) -> void:
	if thruster_sound == null or thruster_players.has(entity_id):
		return
	
	var player = _get_audio_player()
	player.stream = thruster_sound
	player.volume_db = linear_to_db(sfx_volume * 0.6)
	player.pitch_scale = randf_range(0.9, 1.1)
	
	if player.stream is AudioStreamOggVorbis:
		player.stream.loop = true
	
	player.play()
	
	thruster_players[entity_id] = player
	var sound_id = "thruster_" + str(entity_id)
	active_players[sound_id] = player

func stop_thruster(entity_id: int) -> void:
	if not thruster_players.has(entity_id):
		return
		
	var player = thruster_players[entity_id]
	player.stop()
	
	var sound_id = "thruster_" + str(entity_id)
	active_players.erase(sound_id)
	thruster_players.erase(entity_id)

func play_sound(stream: AudioStream, volume: float = 1.0, pitch: float = 1.0) -> String:
	if stream == null:
		return ""
		
	var player = _get_audio_player()
	player.stream = stream
	player.volume_db = linear_to_db(volume * sfx_volume)
	player.pitch_scale = pitch
	player.play()
	
	var sound_id = "sound_" + str(player.get_instance_id())
	active_players[sound_id] = player
	return sound_id

func stop_sound(sound_id: String) -> bool:
	if active_players.has(sound_id):
		active_players[sound_id].stop()
		active_players.erase(sound_id)
		return true
	return false

func stop_all_sounds() -> void:
	for player in sfx_pool:
		player.stop()
	
	active_players.clear()
	thruster_players.clear()
	missile_players.clear()

func set_master_volume(vol: float) -> void:
	master_volume = clamp(vol, 0.0, 1.0)
	AudioServer.set_bus_volume_db(MASTER_BUS_IDX, linear_to_db(master_volume))

func set_music_volume(vol: float) -> void:
	music_volume = clamp(vol, 0.0, 1.0)
	AudioServer.set_bus_volume_db(MUSIC_BUS_IDX, linear_to_db(music_volume))
	
	if music_player:
		music_player.volume_db = linear_to_db(music_volume)

func set_sfx_volume(vol: float) -> void:
	sfx_volume = clamp(vol, 0.0, 1.0)
	AudioServer.set_bus_volume_db(SFX_BUS_IDX, linear_to_db(sfx_volume))

func _on_sound_finished(player: AudioStreamPlayer) -> void:
	var finished_sound_id = ""
	
	for sound_id in active_players:
		if active_players[sound_id] == player:
			finished_sound_id = sound_id
			break
	
	if finished_sound_id != "":
		active_players.erase(finished_sound_id)
		sound_finished.emit(finished_sound_id)

func is_sound_playing(sound_id: String) -> bool:
	return active_players.has(sound_id) and active_players[sound_id].playing
