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

func update(delta: float) -> void:
	# Check for input to transition to other states
	if Input.is_action_pressed("move_up"):
		print("Detected move_up, transitioning to moving")
		state_machine.transition_to("moving")
	elif Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right"):
		print("Detected move_left/right, transitioning to rotating")
		state_machine.transition_to("rotating")
