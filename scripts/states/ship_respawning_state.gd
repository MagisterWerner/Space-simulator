# ship_respawning_state.gd
extends State
class_name ShipRespawningState

func enter(params: Dictionary = {}) -> void:
	var ship = owner as PlayerShip
	if ship:
		# Re-enable all components
		for child in ship.get_children():
			if child is Component:
				child.enable()
		
		# Reset ship position if needed
		if params.has("respawn_position"):
			ship.global_position = params.respawn_position
		else:
			# Default to screen center
			var viewport_size = ship.get_viewport_rect().size
			ship.global_position = viewport_size / 2
		
		# Reset ship rotation
		ship.rotation = 0
		
		# Reset physics state
		if ship is RigidBody2D:
			ship.linear_velocity = Vector2.ZERO
			ship.angular_velocity = 0
		
		# Heal the ship
		var health = ship.get_node_or_null("HealthComponent") as HealthComponent
		if health:
			health.heal(health.max_health)
	
	# Transition to idle after respawning
	state_machine.transition_to("idle")
