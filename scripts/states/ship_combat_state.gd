# ship_combat_state.gd
extends State
class_name ShipCombatState

var target: Node2D
var weapon_component: WeaponComponent

func enter(params: Dictionary = {}) -> void:
	if params.has("target"):
		target = params.target
	
	var ship = owner as PlayerShip
	if ship:
		weapon_component = ship.get_node_or_null("WeaponComponent") as WeaponComponent

func exit() -> void:
	target = null

func update(_delta: float) -> void:
	var ship = owner as PlayerShip
	if not ship:
		return
	
	# Check if we still have a valid target
	if not is_instance_valid(target):
		state_machine.transition_to("idle")
		return
	
	# Get movement component
	var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
	if not movement:
		return
	
	# Player movement control still works in combat
	if Input.is_action_pressed("move_up"):
		movement.thrust_forward(true)
	else:
		movement.thrust_forward(false)
	
	if Input.is_action_pressed("move_left"):
		movement.rotate_left()
	elif Input.is_action_pressed("move_right"):
		movement.rotate_right()
	else:
		movement.stop_rotation()
	
	# Fire weapon when primary action is pressed
	if Input.is_action_pressed("p1_primary") and weapon_component:
		weapon_component.fire()
	
	# Exit combat mode
	if Input.is_action_just_pressed("p1_secondary"):
		state_machine.transition_to("idle")
