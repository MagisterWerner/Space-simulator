# player_ship.gd
extends RigidBody2D
class_name PlayerShip

@export var speed := 5

@export var move_right_action := "move_right"
@export var move_left_action := "move_left"
@export var move_down_action := "move_down"
@export var move_up_action := "move_up"

func _physics_process(_delta: float) -> void:
	update_movement()

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
