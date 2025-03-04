extends Area2D

var laser_speed = 1250

func _ready() -> void:
# Play the laser sound at random pitch for variation
	#var laser_sound = SoundManager.play_sound(Globals.sfx_laser)
	#laser_sound.volume_db = -15
	#laser_sound.pitch_scale = randf_range(0.75, 1.25)

	position = Vector2(position.x,position.y)


func _physics_process(delta):
	position -= transform.y * laser_speed * delta


# Trigger the explode-function on instanced RigidBody2D-scenes and remove the instanced laser
func _on_Laser_body_entered(body: Node) -> void:
	if body.is_in_group("ASTEROIDS") or body.is_in_group("ENEMIES"):
		body.call_deferred("explode")
		_on_Lifetime_timeout()


# Trigger the explode-function on instanced Area2D-scenes and remove the instanced laser
func _on_Laser_area_entered(body: Area2D) -> void:
	if body.is_in_group("MISSILES"):
		body.call_deferred("explode")
		_on_Lifetime_timeout()


func _on_Lifetime_timeout() -> void:
# Remove the laser instance
	queue_free()
