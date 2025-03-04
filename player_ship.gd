# player_ship.gd
extends RigidBody2D
class_name PlayerShip

@export var max_health := 100
@export var health := 100
@export var health_regeneration := 1
@export var speed := 2

@export var move_right_action := "move_right"
@export var move_left_action := "move_left"
@export var move_down_action := "move_down"
@export var move_up_action := "move_up"
@export var primary_action := "primary_action"
@export var secondary_action := "secondary_action"

var laser_attack_time := 0
var laser_cooldown_time := 250
var missile_attack_time := 0
var missile_cooldown_time := 1000
var alive := true

var collision_force := Vector2.ZERO
var previous_linear_velocity := Vector2.ZERO

signal health_updated(new_value)
signal player_destroyed

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	collision_force = Vector2.ZERO

	if state.get_contact_count() > 0:
		var dv := state.linear_velocity - previous_linear_velocity
		collision_force = dv / (state.inverse_mass * state.step)

	previous_linear_velocity = state.linear_velocity

func _process(delta: float) -> void:
	var new_health = min(health + health_regeneration * delta, max_health)
	if new_health != health:
		health = new_health
		emit_signal("health_updated", health)

func _physics_process(_delta: float) -> void:
	if alive:
		update_movement()
	else:
		visible = false
		get_tree().create_timer(1.0).timeout.connect(respawn)

func respawn() -> void:
	get_tree().reload_current_scene()

func take_damage(amount: int) -> void:
	health -= amount
	emit_signal("health_updated", health)
	
	if health <= 0:
		health = 0
		alive = false
		explode()

func update_movement() -> void:
	if Input.get_action_strength(move_right_action) and !Input.get_action_strength(move_down_action):
		apply_impulse(Vector2(0, -speed*0.5).rotated(rotation), $ThrusterPositions/Left.position.rotated(rotation))
		$ThrusterPositions/Left/RearThruster.set_deferred("emitting", true)
	else:
		$ThrusterPositions/Left/RearThruster.set_deferred("emitting", false)

	if Input.get_action_strength(move_left_action) and !Input.get_action_strength(move_down_action):
		apply_impulse(Vector2(0, -speed*0.5).rotated(rotation), $ThrusterPositions/Right.position.rotated(rotation))
		$ThrusterPositions/Right/RearThruster.set_deferred("emitting", true)
	else:
		$ThrusterPositions/Right/RearThruster.set_deferred("emitting", false)

	if Input.get_action_strength(move_up_action):
		apply_central_impulse(Vector2(0, -speed*8).rotated(rotation))
		$MainThruster.set_deferred("emitting", true)
	else:
		$MainThruster.set_deferred("emitting", false)

	if Input.get_action_strength(move_down_action):
		apply_central_impulse(Vector2(0, +speed*2).rotated(rotation))
		$ThrusterPositions/Left/FrontThruster.set_deferred("emitting", true)
		$ThrusterPositions/Right/FrontThruster.set_deferred("emitting", true)

		if Input.get_action_strength(move_right_action) and !Input.get_action_strength(move_left_action):
			apply_impulse(Vector2(0, +speed*0.5).rotated(rotation), $ThrusterPositions/Right.position.rotated(rotation))
			$ThrusterPositions/Right/FrontThruster.set_deferred("emitting", true)
			$ThrusterPositions/Left/FrontThruster.set_deferred("emitting", false)

		if Input.get_action_strength(move_left_action) and !Input.get_action_strength(move_right_action):
			apply_impulse(Vector2(0, +speed*0.5).rotated(rotation), $ThrusterPositions/Left.position.rotated(rotation))
			$ThrusterPositions/Left/FrontThruster.set_deferred("emitting", true)
			$ThrusterPositions/Right/FrontThruster.set_deferred("emitting", false)
	else:
		$ThrusterPositions/Left/FrontThruster.set_deferred("emitting", false)
		$ThrusterPositions/Right/FrontThruster.set_deferred("emitting", false)
		
	if Input.get_action_strength(primary_action):
		var now = Time.get_ticks_msec()
		if now >= laser_attack_time:
			fire_laser()
			laser_attack_time = now + laser_cooldown_time

	if Input.get_action_strength(secondary_action):
		var now = Time.get_ticks_msec()
		if now >= missile_attack_time:
			fire_missile()
			missile_attack_time = now + missile_cooldown_time

func fire_laser() -> void:
	pass

func fire_missile() -> void:
	pass

func explode() -> void:
	emit_signal("player_destroyed")

func _on_body_entered(body: Node) -> void:
	if alive and body.is_in_group("obstacles"):
		var dmg_amount = floor(((abs(collision_force.x)) + (abs(collision_force.y))) / 1000)
		if dmg_amount > 0:
			var is_critical = randf() < 0.1
			if is_critical:
				dmg_amount *= 2
			take_damage(dmg_amount)
