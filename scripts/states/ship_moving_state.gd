# ship_moving_state.gd
extends State
class_name ShipMovingState

func enter(_params: Dictionary = {}) -> void:
	var ship = owner as PlayerShip
	if ship:
		var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
		if movement:
			movement.thrust_forward(true)

func exit() -> void:
	var ship = owner as PlayerShip
	if ship:
		var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
		if movement:
			movement.thrust_forward(false)
			movement.thrust_backward(false)

func update(_delta: float) -> void:
	var ship = owner as PlayerShip
	if not ship:
		return
		
	# Get movement component
	var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
	if not movement:
		return
	
	# Handle both forward and backward movement
	if Input.is_action_pressed("move_up"):
		movement.thrust_forward(true)
		movement.thrust_backward(false)
	elif Input.is_action_pressed("move_down"):
		movement.thrust_forward(false)
		movement.thrust_backward(true)
	else:
		movement.thrust_forward(false)
		movement.thrust_backward(false)
		state_machine.transition_to("idle")
	
	# Handle rotation
	if Input.is_action_pressed("move_left"):
		movement.rotate_left()
	elif Input.is_action_pressed("move_right"):
		movement.rotate_right()
	else:
		movement.stop_rotation()
	
	# Handle boost
	if Input.is_action_pressed("boost"):
		movement.start_boost()
	else:
		movement.stop_boost()
