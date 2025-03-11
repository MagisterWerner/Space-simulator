# ship_damaged_state.gd
extends State
class_name ShipDamagedState

var recovery_timer: float = 0.0
var recovery_time: float = 2.0  # Time in damaged state before recovering

func enter(params: Dictionary = {}) -> void:
	recovery_timer = 0.0
	
	if params.has("recovery_time"):
		recovery_time = params.recovery_time
	
	var ship = owner as PlayerShip
	if ship:
		# Simulate damage by reducing control
		var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
		if movement:
			# Apply rotation in a random direction to simulate impact
			# Use SeedManager for deterministic randomization based on ship's instance id
			var seed_manager = get_node("/root/SeedManager")
			if seed_manager and seed_manager.get_random_value(ship.get_instance_id(), 0.0, 1.0) > 0.5:
				movement.rotate_left()
			else:
				movement.rotate_right()

func update(delta: float) -> void:
	recovery_timer += delta
	
	# After recovery time, go back to idle
	if recovery_timer >= recovery_time:
		state_machine.transition_to("idle")
