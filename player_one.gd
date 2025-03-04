# player_one.gd
extends RigidBody2D
class_name Player

var alive = true
@export var health_regeneration = 1
@export var MAX_HEALTH = 100
@export var speed = 2

@export var move_right_action := "p1_right"
@export var move_left_action := "p1_left"
@export var move_down_action := "p1_down"
@export var move_up_action := "p1_up"
@export var primary_action := "p1_primary"
@export var secondary_action := "p1_secondary"

var laser_attack_time = 0
var laser_cooldown_time = 250
var missile_attack_time = 0
var missile_cooldown_time = 1000
var AlternateLaser = 0

var collision_force : Vector2 = Vector2.ZERO
var previous_linear_velocity : Vector2 = Vector2.ZERO

signal player_stats_changed

@export var health: int = 100: set = _set_health
signal health_updated(new_value)

func _ready() -> void:
	Globals.set("node_player", self)

func _set_health(new_value:int) -> void:
	health = clamp(new_value, 0, MAX_HEALTH)
	emit_signal("health_updated", health)

func _integrate_forces(state : PhysicsDirectBodyState2D)->void:
	collision_force = Vector2.ZERO

	if state.get_contact_count() > 0:
		var dv : Vector2 = state.linear_velocity - previous_linear_velocity
		collision_force = dv / (state.inverse_mass * state.step)

	previous_linear_velocity = state.linear_velocity

func _process(delta):
	var new_health = min(health + health_regeneration * delta, MAX_HEALTH)
	if new_health != health:
		health = new_health
		emit_signal("player_stats_changed", self)
	elif health == MAX_HEALTH:
		emit_signal("player_stats_changed", self)

func _physics_process(_delta: float) -> void:
	Events.emit_signal("player_position", get_global_position())
	if alive:
		update_actor_direction()
	else:
		visible = false
		get_tree().create_timer(1.0).timeout.connect(Callable(self, "_PlayerDeath"))

func _PlayerDeath():
	get_tree().reload_current_scene()

func _damage(amount):
	health -= amount
	if health > 0:
		print("Your ship took ", amount, " damage and is now at ", health, "!")
	else:
		health = 0
		alive = false
		print("Your ship took ", amount, " damage and was detroyed!")
		explode()

func _on_Player_body_entered(body: Node) -> void:
	if alive:
		if is_instance_valid(body) and body.is_in_group("ASTEROIDS") or body.is_in_group("ENEMIES"):
			var dmg_amount = floor( ( (abs(collision_force.x)) + (abs(collision_force.y)) ) / 1000 )
			var crit = false
		
			if dmg_amount > 1:
				crit = true if randi() % 100 < 10 else false
				if crit:
					dmg_amount *= 2
				_damage(dmg_amount)

func update_actor_direction() -> void:
	if Input.get_action_strength(move_right_action) and !Input.get_action_strength(move_down_action) :
		apply_impulse(Vector2(0, -speed*0.5).rotated(rotation), $L.position.rotated(rotation))
		$L/RearThruster.set_deferred("emitting", true)
	else :
		$L/RearThruster.set_deferred("emitting", false)

	if Input.get_action_strength(move_left_action) and !Input.get_action_strength(move_down_action) :
		apply_impulse(Vector2(0, -speed*0.5).rotated(rotation), $R.position.rotated(rotation))
		$R/RearThruster.set_deferred("emitting", true)
	else :
		$R/RearThruster.set_deferred("emitting", false)

	if Input.get_action_strength(move_up_action) :
		apply_central_impulse(Vector2(0, -speed*8).rotated(rotation))
		$MainThruster.set_deferred("emitting", true)
	else :
		$MainThruster.set_deferred("emitting", false)

	if Input.get_action_strength(move_down_action) :
		apply_central_impulse(Vector2(0, +speed*2).rotated(rotation))
		$L/FrontThruster.set_deferred("emitting", true)
		$R/FrontThruster.set_deferred("emitting", true)

		if Input.get_action_strength(move_right_action) and !Input.get_action_strength(move_left_action) :
			apply_impulse(Vector2(0, +speed*0.5).rotated(rotation), $R.position.rotated(rotation))
			$R/FrontThruster.set_deferred("emitting", true)
			$L/FrontThruster.set_deferred("emitting", false)

		if Input.get_action_strength(move_left_action) and !Input.get_action_strength(move_right_action) :
			apply_impulse(Vector2(0, +speed*0.5).rotated(rotation), $L.position.rotated(rotation))
			$L/FrontThruster.set_deferred("emitting", true)
			$R/FrontThruster.set_deferred("emitting", false)

	else :
		$L/FrontThruster.set_deferred("emitting", false)
		$R/FrontThruster.set_deferred("emitting", false)
		
	if Input.get_action_strength(primary_action) :
		var now = Time.get_ticks_msec()
		if now >= laser_attack_time:
			fire_laser()
			laser_attack_time = now + laser_cooldown_time

	if Input.get_action_strength(secondary_action) :
		var now = Time.get_ticks_msec()
		if now >= missile_attack_time:
			fire_missile()
			missile_attack_time = now + missile_cooldown_time

func fire_laser():
	pass

func fire_missile():
	pass

func explode() -> void:
	pass
