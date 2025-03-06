# ship_idle_state.gd
extends State
class_name ShipIdleState

func enter(_params: Dictionary = {}) -> void:
	# We no longer stop all movement when entering idle state
	# This allows the PlayerShip script to handle movement directly
	pass

func update(_delta: float) -> void:
	# Ship state transitions are now handled in the PlayerShip script
	# This state just represents the ship being in its default/resting state
	pass

func exit() -> void:
	# Clean exit with no behavior changes
	pass
