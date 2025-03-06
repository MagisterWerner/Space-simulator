extends Node
# Example usage of AudioManager

# 1. First, add AudioManager.gd as an autoload singleton in your project settings
# In Project > Project Settings > Autoload, add the script with name "Audio"

# 2. This example shows how to use the audio manager in a game scene

var _thruster_sound = null
var _thruster_sound_playing = false

func _ready():
	# Initialize audio resources
	
	# Preload music tracks
	Audio.preload_music("main_theme", "res://audio/music/main_theme.ogg")
	Audio.preload_music("battle_theme", "res://audio/music/battle_theme.mp3")
	Audio.preload_music("boss_theme", "res://audio/music/boss_theme.ogg")
	
	# Or load all music from a directory
	# Audio.preload_music_directory("res://audio/music")
	
	# Preload sound effects with appropriate pool sizes
	# For bullet hell games, increase pool size for frequently used sounds
	Audio.preload_sfx("laser", "res://audio/sfx/laser.wav", 30)  # Large pool for weapon sounds
	Audio.preload_sfx("explosion_small", "res://audio/sfx/explosion_small.wav", 20)
	Audio.preload_sfx("explosion_large", "res://audio/sfx/explosion_large.wav", 10)
	Audio.preload_sfx("thruster", "res://audio/sfx/thruster.sfxr", 5)
	Audio.preload_sfx("powerup", "res://audio/sfx/powerup.wav", 5)
	
	# Start background music
	Audio.play_music("main_theme")
	
	# Connect to player signals for sound effects
	$Player.weapon_fired.connect(_on_player_fire_weapon)
	$Player.thrust_started.connect(_on_player_thrust)
	$Player.thrust_stopped.connect(_on_player_stop_thrust)
	
	# Connect to game state signals for music changes
	$GameState.boss_battle_started.connect(_on_enter_boss_battle)
	$GameState.level_completed.connect(_on_victory)
	
	# Set up UI connections for audio settings
	$UI/SettingsMenu/MasterSlider.value_changed.connect(_on_master_volume_changed)
	$UI/SettingsMenu/MusicSlider.value_changed.connect(_on_music_volume_changed)
	$UI/SettingsMenu/SFXSlider.value_changed.connect(_on_sfx_volume_changed)
	$UI/SettingsMenu/MusicToggle.toggled.connect(_on_music_toggle_changed)
	$UI/SettingsMenu/SFXToggle.toggled.connect(_on_sfx_toggle_changed)

# Play sound effects based on game events

func _on_player_fire_weapon():
	# Play with positional audio
	var player_position = $Player.global_position
	
	# Add slight pitch variation for more natural sound
	var pitch = randf_range(0.95, 1.05)
	
	Audio.play_sfx("laser", player_position, pitch)

func _on_enemy_destroyed(enemy):
	var position = enemy.global_position
	var size = enemy.size
	
	# Choose explosion type based on enemy size
	var sfx_name = "explosion_small"
	if size == "large":
		sfx_name = "explosion_large"
	
	# Add randomization to make explosions sound more varied
	var pitch = randf_range(0.9, 1.1)
	var volume = randf_range(-2.0, 0.0)
	
	Audio.play_sfx(sfx_name, position, pitch, volume)

func _on_player_thrust():
	if !_thruster_sound_playing:
		# Track the sound player for looping effects
		_thruster_sound = Audio.play_sfx("thruster", $Player.global_position)
		_thruster_sound_playing = true

func _on_player_stop_thrust():
	if _thruster_sound_playing and _thruster_sound:
		_thruster_sound.stop()
		_thruster_sound_playing = false

# Follow the player position for looping positional sounds
func _process(_delta):
	if _thruster_sound_playing and _thruster_sound:
		# Update position for moving sound sources
		_thruster_sound.position = $Player.global_position

# Change music for different game states

func _on_enter_boss_battle():
	# Crossfade to boss music
	Audio.play_music("boss_theme", true)

func _on_victory():
	# Stop all SFX for a dramatic effect
	Audio.stop_all_sfx()
	
	# Play victory theme
	Audio.play_music("main_theme", true)

# Handle audio settings UI

func _on_master_volume_changed(value):
	Audio.set_master_volume(value)
	Audio.save_settings()

func _on_music_volume_changed(value):
	Audio.set_music_volume(value)
	Audio.save_settings()

func _on_sfx_volume_changed(value):
	Audio.set_sfx_volume(value)
	Audio.save_settings()

func _on_music_toggle_changed(enabled):
	Audio.set_music_enabled(enabled)
	Audio.save_settings()

func _on_sfx_toggle_changed(enabled):
	Audio.set_sfx_enabled(enabled)
	Audio.save_settings()

# Clean up when scene changes
func _exit_tree():
	# Stop any looping sounds specifically tied to this scene
	if _thruster_sound_playing and _thruster_sound:
		_thruster_sound.stop()
		_thruster_sound_playing = false
