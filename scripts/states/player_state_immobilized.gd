# scripts/states/player_state_immobilized.gd
extends State
class_name PlayerStateImmobilized

var movement_component

func enter() -> void:
	super.enter()
	
	# Get reference to movement component
	movement_component = entity.get_node_or_null("MovementComponent")
	
	# Set player state
	entity.is_immobilized = true
	
	# Stop movement through the component
	if movement_component:
		movement_component.stop()
		movement_component.set_speed(0)
		
		# For RigidBody2D, also freeze the body
		if entity is RigidBody2D:
			entity.freeze = true
			# Reset velocities to zero
			entity.linear_velocity = Vector2.ZERO
			entity.angular_velocity = 0.0
	
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
