# scripts/states/player_state_immobilized.gd
extends State
class_name PlayerStateImmobilized

func enter() -> void:
	super.enter()
	
	# Set player state
	entity.is_immobilized = true
	
	# For RigidBody2D, freeze the body
	if entity is RigidBody2D:
		entity.freeze = true
		# Reset velocities to zero
		entity.linear_velocity = Vector2.ZERO
		entity.angular_velocity = 0.0
		
		# Disable all thrusters
		if entity.has_node("L/RearThruster"):
			entity.get_node("L/RearThruster").set_deferred("emitting", false)
		if entity.has_node("R/RearThruster"):
			entity.get_node("R/RearThruster").set_deferred("emitting", false)
		if entity.has_node("L/FrontThruster"):
			entity.get_node("L/FrontThruster").set_deferred("emitting", false)
		if entity.has_node("R/FrontThruster"):
			entity.get_node("R/FrontThruster").set_deferred("emitting", false)
		if entity.has_node("MainThruster"):
			entity.get_node("MainThruster").set_deferred("emitting", false)
	
	# Show a message if not already shown
	var main = entity.get_node_or_null("/root/Main")
	if main and main.has_method("show_message") and entity.respawn_timer > 4.9:
		main.show_message("You are immobilized. Respawning in 5 seconds...")

func exit() -> void:
	super.exit()
	
	# Unfreeze the RigidBody2D when leaving immobilized state
	if entity is RigidBody2D:
		entity.freeze = false

func process(_delta: float) -> void:
	# Update the respawn timer is handled in the player script
	pass
