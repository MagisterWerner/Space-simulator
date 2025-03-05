# ship_rotating_state.gd
extends State
class_name ShipRotatingState

# Use timestamp-based suppression instead of a simple boolean flag
static var _last_message_time: float = 0.0
const MESSAGE_COOLDOWN: float = 0.2  # seconds - prevents duplicate messages within this timeframe

func enter(_params: Dictionary = {}) -> void:
	# Check if enough time has passed since last message
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_message_time > MESSAGE_COOLDOWN:
		print("Entering rotating state")
		_last_message_time = current_time
	
	# Apply rotation based on current input state
	var ship = owner as PlayerShip
	if ship:
		var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
		if movement:
			if Input.is_action_pressed("move_left"):
				movement.rotate_left()
			elif Input.is_action_pressed("move_right"):
				movement.rotate_right()

func exit() -> void:
	# Stop rotation when leaving this state
	var ship = owner as PlayerShip
	if ship:
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
