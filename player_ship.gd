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
	# For rotating right (yaw right)
	if Input.get_action_strength(move_right_action) and !Input.get_action_strength(move_down_action):
		# Apply torque to rotate clockwise
		apply_torque(speed * 250)
		$ThrusterPositions/Left/RearThruster.set_deferred("emitting", true)
	else:
		$ThrusterPositions/Left/RearThruster.set_deferred("emitting", false)

	# For rotating left (yaw left)
	if Input.get_action_strength(move_left_action) and !Input.get_action_strength(move_down_action):
		# Apply torque to rotate counter-clockwise
		apply_torque(-speed * 250)
		$ThrusterPositions/Right/RearThruster.set_deferred("emitting", true)
	else:
		$ThrusterPositions/Right/RearThruster.set_deferred("emitting", false)

	# For moving forward in the direction the ship is facing
	if Input.get_action_strength(move_up_action):
		# Apply force in the direction the ship is facing (rotated right/90 degrees from original)
		apply_central_impulse(Vector2(speed*8, 0).rotated(rotation))
		$MainThruster.set_deferred("emitting", true)
	else:
		$MainThruster.set_deferred("emitting", false)

	# For moving backward (opposite to the direction the ship is facing)
	if Input.get_action_strength(move_down_action):
		# Apply force opposite to the direction the ship is facing
		apply_central_impulse(Vector2(-speed*2, 0).rotated(rotation))
		$ThrusterPositions/Left/FrontThruster.set_deferred("emitting", true)
		$ThrusterPositions/Right/FrontThruster.set_deferred("emitting", true)

		# For combined backward and right movement
		if Input.get_action_strength(move_right_action) and !Input.get_action_strength(move_left_action):
			apply_torque(speed * 250)
			$ThrusterPositions/Right/FrontThruster.set_deferred("emitting", true)
			$ThrusterPositions/Left/FrontThruster.set_deferred("emitting", false)

		# For combined backward and left movement
		if Input.get_action_strength(move_left_action) and !Input.get_action_strength(move_right_action):
			apply_torque(-speed * 250)
			$ThrusterPositions/Left/FrontThruster.set_deferred("emitting", true)
			$ThrusterPositions/Right/FrontThruster.set_deferred("emitting", false)
	else:
		$ThrusterPositions/Left/FrontThruster.set_deferred("emitting", false)
		$ThrusterPositions/Right/FrontThruster.set_deferred("emitting", false)
