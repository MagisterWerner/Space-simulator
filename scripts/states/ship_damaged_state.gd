# scripts/states/ship_damaged_state.gd
extends State
class_name ShipDamagedState

var recovery_timer: float = 0.0
var recovery_time: float = 2.0

func enter(params: Dictionary = {}) -> void:
	recovery_timer = 0.0
	
	if params.has("recovery_time"):
		recovery_time = params.recovery_time
	
	var ship = owner as PlayerShip
	if not ship:
		return
		
	# Get movement component - fail fast if not available
	var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
	if not movement:
		return
	
	# Apply simulated damage effect using SeedManager for determinism
	var seed_manager = Engine.get_singleton("SeedManager")
	if seed_manager and seed_manager.has_method("get_random_bool"):
		# Use a deterministic seed combining ship ID and current time
		var damage_seed = ship.get_instance_id() + int(Time.get_ticks_msec() / 1000.0)
		
		# Apply rotation based on deterministic random value
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
