# ship_rotating_state.gd
extends State
class_name ShipRotatingState

func enter(_params: Dictionary = {}) -> void:
	var ship = owner as PlayerShip
	if not ship:
		return
		
	var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
	if not movement:
		return
		
	# Apply rotation based on current input state
	if Input.is_action_pressed("move_left"):
		movement.rotate_left()
	elif Input.is_action_pressed("move_right"):
		movement.rotate_right()

func exit() -> void:
	var ship = owner as PlayerShip
	if not ship:
		return
		
	var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
	if movement:
		movement.stop_rotation()

func update(_delta: float) -> void:
	var ship = owner as PlayerShip
	if not ship:
		return
		
	# Get movement component
	var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
	if not movement:
		return
	
	# Handle rotation
	if Input.is_action_pressed("move_left"):
		movement.rotate_left()
	elif Input.is_action_pressed("move_right"):
		movement.rotate_right()
	else:
		movement.stop_rotation()
		state_machine.transition_to("idle")
	
	# If thrusting, transition to moving state
	if Input.is_action_pressed("move_up"):
		state_machine.transition_to("moving")
