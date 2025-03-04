extends CPUParticles2D

func _ready() -> void:
	#var explosion_sound = SoundManager.play_sound(Globals.sfx_explosion) # Play the explosion sound
	#explosion_sound.volume_db = -15
	#explosion_sound.pitch_scale = randf_range(0.75, 1.25)
	await get_tree().create_timer(0.5).timeout
	queue_free()
