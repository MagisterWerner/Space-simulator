# player_state_immobilized.gd
extends State
class_name PlayerStateImmobilized

var movement_component

func enter() -> void:
	super.enter()
	movement_component = entity.get_node_or_null("MovementComponent")
	entity.is_immobilized = true
	
	if movement_component:
		movement_component.stop()
		movement_component.set_speed(0)
		
	if entity is RigidBody2D:
		entity.freeze = true
		entity.linear_velocity = Vector2.ZERO
		entity.angular_velocity = 0.0
	
	var main = entity.get_node_or_null("/root/Main")
	if main and main.has_method("show_message") and entity.respawn_timer > 4.9:
		main.show_message("You are immobilized. Respawning in 5 seconds...")

func exit() -> void:
	super.exit()
	if entity is RigidBody2D:
		entity.freeze = false

func process(_delta: float) -> void:
	pass
