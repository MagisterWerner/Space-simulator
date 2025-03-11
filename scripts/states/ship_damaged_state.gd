# scripts/states/ship_damaged_state.gd
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
			if Engine.has_singleton("SeedManager"):
				var seed_manager = Engine.get_singleton("SeedManager")
				
				# Wait for SeedManager to be fully initialized if needed
				if seed_manager.has_method("is_initialized") and not seed_manager.is_initialized and seed_manager.has_signal("seed_initialized"):
					await seed_manager.seed_initialized
				
				# Use the ship's instance_id for deterministic damage rotation
				var damage_seed = ship.get_instance_id() + int(Time.get_ticks_msec() / 1000)
				if seed_manager.get_random_bool(damage_seed, 0.5):
					movement.rotate_left()
				else:
					movement.rotate_right()
			else:
				# Fallback to non-deterministic if SeedManager not available
				if randf() > 0.5:
					movement.rotate_left()
				else:
					movement.rotate_right()

func update(delta: float) -> void:
	recovery_timer += delta
	
	# After recovery time, go back to idle
	if recovery_timer >= recovery_time:
		state_machine.transition_to("idle")
