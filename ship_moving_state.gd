# ship_moving_state.gd
extends State
class_name ShipMovingState

func enter(params: Dictionary = {}) -> void:
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

func update(delta: float) -> void:
	var ship = owner as PlayerShip
	if not ship:
		return
		
	# Get movement component
	var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
	if not movement:
		return
	
	# Handle rotation while moving
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
	
	# Check for transition back to idle
	if not Input.is_action_pressed("move_up"):
		state_machine.transition_to("idle")
