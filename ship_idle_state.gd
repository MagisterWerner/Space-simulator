# ship_idle_state.gd
extends State
class_name ShipIdleState

func enter(params: Dictionary = {}) -> void:
	var ship = owner as PlayerShip
	if ship:
		var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
		if movement:
			movement.thrust_forward(false)
			movement.stop_rotation()
			movement.stop_boost()
			print("Entering idle state")
		else:
			print("MovementComponent not found on ship!")

func update(delta: float) -> void:
	# Debug print to verify this is being called
	if Input.is_action_just_pressed("move_up") or Input.is_action_just_pressed("move_left") or Input.is_action_just_pressed("move_right"):
		print("Input detected in IdleState: up=%s, left=%s, right=%s" % [
			Input.is_action_pressed("move_up"),
			Input.is_action_pressed("move_left"),
			Input.is_action_pressed("move_right")
		])
	
	# Check for input to transition to other states
	if Input.is_action_pressed("move_up"):
		print("Transitioning to moving state")
		state_machine.transition_to("moving")
	elif Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right"):
		print("Transitioning to rotating state")
		state_machine.transition_to("rotating")
