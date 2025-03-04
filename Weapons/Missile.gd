extends Area2D

var speed = 400
var rotation_speed = 5
var target = null
var missile_thruster_sound = null


func _ready() -> void:
# The missile shoots out at a random angle
	rotation += randf_range(-0.1, 0.1)
	
#Play the missile thruster sound
	#missile_thruster_sound = SoundManager.play_sound(Globals.sfx_missile)
	#missile_thruster_sound.volume_db = -15


func _physics_process(delta) -> void:
	if target and weakref(target).get_ref():
		var direction = target.position - position
		direction = direction.normalized()
		var rotateAmount = direction.cross(transform.y)
		rotate(rotateAmount * rotation_speed * delta)
		global_translate(-transform.y * speed * delta)
	else:
		position -= transform.y * speed * delta
		get_tree().create_timer(0.4).connect("timeout", Callable(self, "_find_target"))


func _on_ProjectileHoming_body_entered(body) -> void:
	if body.is_in_group("ASTEROIDS") or body.is_in_group('ENEMIES'):
		body.call_deferred("explode") # Trigger explosion code on the instanced Asteroid scene
		explode()


func _on_Lifetime_timeout() -> void:
	explode()


func _find_target() -> void:
	var units = []
	for overlapping_body in get_node("DetectionRange").get_overlapping_bodies():
		if overlapping_body.is_in_group('ASTEROIDS') or overlapping_body.is_in_group('ENEMIES'):
			units.append(overlapping_body)
	if units.size() > 0:
		var closest = units[0]
		for unit in units:
			if position.distance_to(unit.global_position) < position.distance_to(closest.global_position):
				closest = unit
		target = closest
	else:
		target = null


func explode() -> void:
		# Instance the explosion scene
		var explosion = Globals.scene_explosion.instantiate()
		explosion.set_position(self.global_position)
		explosion.emission_sphere_radius = 1
		ObjectRegistry._effects.add_child(explosion)

	# Remove the missile instance and stop the thruster sound
#		missile_thruster_sound.stop()
		queue_free()
