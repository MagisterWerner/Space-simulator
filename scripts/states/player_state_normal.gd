# scripts/states/player_state_normal.gd
extends State
class_name PlayerStateNormal

var combat_component

func enter() -> void:
	super.enter()
	
	# Get references to components
	combat_component = entity.get_node_or_null("CombatComponent")
	
	# Ensure player is not immobilized
	entity.is_immobilized = false
	
	# Make sure RigidBody2D isn't frozen
	if entity is RigidBody2D:
		entity.freeze = false
		
		# Set physics properties
		entity.gravity_scale = 0.0
		entity.linear_damp = 0.1
		entity.angular_damp = 1.0
	
	# Set speed through the component
	if "speed" in entity:
		entity.speed = 300

func process(delta: float) -> void:
	# Skip if player is immobilized
	if entity.is_immobilized:
		return
	
	# Note: Most movement is handled directly in the player's _physics_process method
	# via the update_thrusters function, matching the control scheme from player_one.gd
	
	# This state mainly handles weapon charging behavior
	if Input.is_action_just_pressed("primary_fire") and combat_component:
		# Check if this is a chargeable weapon
		var current_weapon = combat_component.get_current_weapon_name()
		if current_weapon == "ChargeBeam" and combat_component.can_fire():
			entity.is_charging_weapon = combat_component.start_charging()
