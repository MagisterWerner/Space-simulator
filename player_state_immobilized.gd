# player_state_immobilized.gd
class_name PlayerStateImmobilized
extends State

func enter() -> void:
	super.enter()
	print("Player immobilized")
	
	# Ensure player state is consistent
	entity.is_immobilized = true
	entity.movement_speed = 0  # This now uses the property getter
	
	# Show a message if not already shown
	var main = entity.get_node_or_null("/root/Main")
	if main and main.has_method("show_message") and entity.respawn_timer > 4.9:
		main.show_message("You are immobilized. Respawning in 5 seconds...")

func process(delta: float) -> void:
	# Update the respawn timer
	entity.respawn_timer -= delta
	
	# Check if we should respawn
	if entity.respawn_timer <= 0:
		# Change back to normal state
		state_machine.change_state("Normal")
		
		# Respawn at initial planet
		var main = entity.get_node_or_null("/root/Main")
		if main and main.has_method("respawn_player_at_initial_planet"):
			main.respawn_player_at_initial_planet()
