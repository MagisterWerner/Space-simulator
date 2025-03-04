# player_state_normal.gd
extends State
class_name PlayerStateNormal

var movement_component
var combat_component

func enter() -> void:
	super.enter()
	movement_component = entity.get_node_or_null("MovementComponent")
	combat_component = entity.get_node_or_null("CombatComponent")
	entity.is_immobilized = false
	
	if entity is RigidBody2D:
		entity.freeze = false
	
	if movement_component:
		movement_component.set_speed(300)

func process(delta: float) -> void:
	if entity.is_immobilized:
		return
	
	var direction = Vector2.ZERO
	
	if Input.is_action_pressed("ui_right"):
		direction.x += 1
	if Input.is_action_pressed("ui_left"):
		direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		direction.y += 1
	if Input.is_action_pressed("ui_up"):
		direction.y -= 1
	
	if movement_component:
		if direction.length() > 0:
			movement_component.move(direction)
		else:
			movement_component.stop()
	
	if combat_component:
		if Input.is_action_pressed("primary_fire"):
			if entity.is_charging_weapon:
				entity.current_charge = combat_component.update_charge(delta)
			elif combat_component.can_fire():
				entity.shoot()
		
		if Input.is_physical_key_pressed(KEY_SPACE) and combat_component.can_fire():
			entity.shoot()
