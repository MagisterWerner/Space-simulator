# scripts/states/player_state_normal.gd
extends State
class_name PlayerStateNormal

var movement_component
var combat_component

func enter() -> void:
	super.enter()
	
	# Get references to components
	movement_component = entity.get_node_or_null("MovementComponent")
	combat_component = entity.get_node_or_null("CombatComponent")
	
	# Ensure player is not immobilized
	entity.is_immobilized = false
	
	# Make sure RigidBody2D isn't frozen
	if entity is RigidBody2D:
		entity.freeze = false
	
	# Set speed through the component
	if movement_component:
		movement_component.set_speed(300)

func process(delta: float) -> void:
	# Skip if player is immobilized
	if entity.is_immobilized:
		return
	
	# Handle movement
	var direction = Vector2.ZERO
	
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	
	# Move the player using the movement component
	if movement_component:
		if direction.length() > 0:
			movement_component.move(direction)
		else:
			movement_component.stop()
	
	# Handle shooting
	if Input.is_action_pressed("primary_fire") and combat_component:
		if entity.is_charging_weapon:
			# Update charge value if charging
			entity.current_charge = combat_component.update_charge(delta)
		else:
			# Try to shoot if not charging and cooldown is ready
			if combat_component.can_fire():
				entity.shoot()
	
	# Extra primary fire check
	if Input.is_physical_key_pressed(KEY_SPACE) and combat_component:
		if combat_component.can_fire():
			entity.shoot()
