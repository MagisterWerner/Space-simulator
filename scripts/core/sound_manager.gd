extends Node

# References to audio streams
var laser_sound: AudioStream
var thruster_sound: AudioStream
var explosion_sound: AudioStream
var explosion_debris_sound: AudioStream
var explosion_fire_sound: AudioStream
var missile_sound: AudioStream

# Pool of audio players for explosion sounds
var explosion_audio_players = []
const MAX_EXPLOSION_PLAYERS = 5

func _ready():
	# Load sound effects
	load_sound_effects()
	
	# Create explosion audio player pool
	create_explosion_audio_pool()

# Load all sound effects
func load_sound_effects():
	# Load laser sound
	var laser_path = "res://sounds/laser.sfxr"
	if ResourceLoader.exists(laser_path):
		laser_sound = load(laser_path)
	
	# Load thruster sound
	var thruster_path = "res://sounds/thruster.wav"
	if ResourceLoader.exists(thruster_path):
		thruster_sound = load(thruster_path)
	
	# Load explosion sounds
	var explosion_path = "res://sounds/explosion.wav"
	if ResourceLoader.exists(explosion_path):
		explosion_sound = load(explosion_path)
		
	var explosion_debris_path = "res://sounds/explosion_debris.wav"
	if ResourceLoader.exists(explosion_debris_path):
		explosion_debris_sound = load(explosion_debris_path)
		
	var explosion_fire_path = "res://sounds/explosion_fire.wav"
	if ResourceLoader.exists(explosion_fire_path):
		explosion_fire_sound = load(explosion_fire_path)
	
	# Load missile sound
	var missile_path = "res://sounds/missile.sfxr"
	if ResourceLoader.exists(missile_path):
		missile_sound = load(missile_path)

# Create a pool of audio players for explosions
func create_explosion_audio_pool():
	for i in range(MAX_EXPLOSION_PLAYERS):
		var player = AudioStreamPlayer2D.new()
		player.max_distance = 500
		player.bus = "Effects"
		player.finished.connect(_on_explosion_audio_finished.bind(player))
		explosion_audio_players.append(player)
		add_child(player)

# Handle explosion sound finished playing
func _on_explosion_audio_finished(player):
	player.stop()

# Play laser sound at position
func play_laser(position: Vector2):
	if laser_sound:
		var player = get_player_node_at_position(position)
		if player and player.has_node("WeaponAudioStreamPlayer"):
			var audio_player = player.get_node("WeaponAudioStreamPlayer")
			audio_player.stream = laser_sound
			audio_player.position = position
			audio_player.play()

# Play thruster sound at position
func play_thruster(position: Vector2, velocity_ratio: float = 1.0):
	if thruster_sound:
		var player = get_player_node_at_position(position)
		if player and player.has_node("EngineAudioStreamPlayer"):
			var audio_player = player.get_node("EngineAudioStreamPlayer")
			
			# Only set the stream if it's not already set or has changed
			if audio_player.stream != thruster_sound:
				audio_player.stream = thruster_sound
			
			# Set position and volume based on velocity ratio
			audio_player.position = position
			audio_player.volume_db = linear_to_db(max(0.1, velocity_ratio))
			
			# Make sure it's playing
			if not audio_player.playing:
				audio_player.play()

# Stop thruster sound
func stop_thruster():
	var player = get_player_node()
	if player and player.has_node("EngineAudioStreamPlayer"):
		var audio_player = player.get_node("EngineAudioStreamPlayer")
		if audio_player.playing:
			audio_player.stop()

# Play explosion sound at position
func play_explosion(position: Vector2):
	if explosion_sound or explosion_fire_sound or explosion_debris_sound:
		# Choose a random explosion sound
		var sound_options = []
		if explosion_sound:
			sound_options.append(explosion_sound)
		if explosion_fire_sound:
			sound_options.append(explosion_fire_sound)
		if explosion_debris_sound:
			sound_options.append(explosion_debris_sound)
		
		if sound_options.size() > 0:
			var rng = RandomNumberGenerator.new()
			rng.randomize()
			var chosen_sound = sound_options[rng.randi() % sound_options.size()]
			
			# Find an available player
			for player in explosion_audio_players:
				if not player.playing:
					player.stream = chosen_sound
					player.position = position
					player.play()
					return

# Play missile sound at position
func play_missile(position: Vector2):
	if missile_sound:
		var player = get_player_node_at_position(position)
		if player and player.has_node("WeaponAudioStreamPlayer"):
			var audio_player = player.get_node("WeaponAudioStreamPlayer")
			audio_player.stream = missile_sound
			audio_player.position = position
			audio_player.play()

# Helper function to get player node at position
func get_player_node_at_position(position: Vector2):
	var player = get_player_node()
	return player

# Helper function to get player node 
func get_player_node():
	# Try to get PlayerOne first, then fallback to Player
	var player = get_node_or_null("/root/Main/PlayerOne")
	if not player:
		player = get_node_or_null("/root/Main/Player")
	return player
