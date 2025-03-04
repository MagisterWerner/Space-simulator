extends RigidBody2D
class_name Enemy

@export var MAX_HEALTH = 50 # (int, 300)
var speed = 10
var rotation_speed = 2
var active = false

var laser_attack_time =  0
var missile_attack_time =  0
var missile_cooldown_time = 5000
var AlternateLaser = 0

var collision_force : Vector2 = Vector2.ZERO
var previous_linear_velocity : Vector2 = Vector2.ZERO


@export var health: int = 100: set = _set_health
signal health_updated(new_value)

func _set_health(new_value:int) -> void:
	health = clamp(new_value, 0, MAX_HEALTH)
	emit_signal("health_updated", health)
	

func _integrate_forces(state : PhysicsDirectBodyState2D)->void:
	collision_force = Vector2.ZERO

	if state.get_contact_count() > 0:
		var dv : Vector2 = state.linear_velocity - previous_linear_velocity
		collision_force = dv / (state.inverse_mass * state.step)

	previous_linear_velocity = state.linear_velocity


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Globals.set("node_target", self)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _physics_process(delta: float) -> void:
	if position.distance_to(Globals.node_player.global_position) > 100:
		var direction = Globals.get("node_player").global_position - global_position
		direction = direction.normalized()
		var rotateAmount = direction.cross(transform.y)
		rotate(rotateAmount * rotation_speed * delta)
#		global_translate(-transform.y * speed * delta)
		apply_central_impulse(Vector2(0, -speed).rotated(rotation))

		if active and position.distance_to(Globals.node_player.global_position) < 400:
			# Check if player can attack
			var now = Time.get_ticks_msec()
			if now >= laser_attack_time:
				var laser_cooldown_time = randf_range(500, 3000)
				fire_laser()
				# Add cooldown time to current time
				laser_attack_time = now + laser_cooldown_time

			# Check if player can attack
			elif active and now >= missile_attack_time:
				fire_missile()
				# Add cooldown time to current time
				missile_attack_time = now + missile_cooldown_time
				laser_attack_time += 1000

func _damage(dmg_amount):
	health -= dmg_amount

	if dmg_amount > 1:
		var crit = true if randi() % 100 < 10 else false
		if crit:
			dmg_amount *= 2
		get_node("../FCTMgr").show_value(Globals.get("node_target"), dmg_amount, crit)
	
	if health > 0:
		print("The enemy ship took ", dmg_amount, " damage and is now at ", health, "!")
	else:
		health = 0
		print("The enemy ship took ", dmg_amount, " damage and was destroyed!")
		explode()


func _on_Ship_body_entered(body: Node) -> void:
	if is_instance_valid(body) and body.is_in_group("ASTEROIDS") or body.is_in_group("PLAYERS"):
		var dmg_amount = floor( ( (abs(collision_force.x)) + (abs(collision_force.y)) ) / 1000 )
		_damage(dmg_amount)


func _on_VisibilityNotifier2D_screen_entered():
	active = true


func _on_VisibilityNotifier2D_screen_exited():
	active = false



func fire_laser() -> void:
	if AlternateLaser == 0:
		var rw = Globals.scene_enemy_laser.instantiate()
		rw.transform = $RW.global_transform
		ObjectRegistry._projectiles.add_child(rw)
		AlternateLaser = 1
		
	elif AlternateLaser == 1:
		var lw = Globals.scene_enemy_laser.instantiate()
		lw.transform = $LW.global_transform
		ObjectRegistry._projectiles.add_child(lw)
		AlternateLaser = 0


func fire_missile() -> void:
	var missile = Globals.scene_enemy_missile.instantiate()
	missile.transform = global_transform
#	get_tree().get_root().add_child(missile)
	ObjectRegistry._projectiles.add_child(missile)


func explode() -> void:
	# Instance the explosion scene
	var explosion = Globals.scene_explosion.instantiate()
	explosion.set_position(self.global_position)
	explosion.emission_sphere_radius = 2
	ObjectRegistry._effects.add_child(explosion)
