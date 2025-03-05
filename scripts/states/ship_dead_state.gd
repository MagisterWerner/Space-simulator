# ship_dead_state.gd
extends State
class_name ShipDeadState

var respawn_timer: float = 0.0
var respawn_time: float = 5.0

func enter(params: Dictionary = {}) -> void:
	respawn_timer = 0.0
	
	if params.has("respawn_time"):
		respawn_time = params.respawn_time
	
	var ship = owner as PlayerShip
	if ship:
		# Disable all components
		for child in ship.get_children():
			if child is Component:
				child.disable()
		
		# Play death effect/animation if available
		if ship.has_method("play_death_effect"):
			ship.play_death_effect()

func update(delta: float) -> void:
	respawn_timer += delta
	
	# After respawn time, transition to respawn state
	if respawn_timer >= respawn_time:
		state_machine.transition_to("respawning")
