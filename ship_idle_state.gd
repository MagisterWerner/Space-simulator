# ship_idle_state.gd
extends State
class_name ShipIdleState

func enter(params: Dictionary = {}) -> void:
	var ship = owner as PlayerShip
	if ship:
		var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
		if movement:
			movement.thrust_forward(false)
			movement.stop_rotation()
			movement.stop_boost()

func update(delta: float) -> void:
	# Check for input to transition to other states
	if Input.is_action_pressed("move_up"):
		state_machine.transition_to("moving")
	elif Input.is_action_pressed("move_left") or Input.is_action_pressed("move_right"):
		state_machine.transition_to("rotating")

# ---------------------------------------------------------

# ship_moving_state.gd
extends State
class_name ShipMovingState

func enter(params: Dictionary = {}) -> void:
	var ship = owner as PlayerShip
	if ship:
		var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
		if movement:
			movement.thrust_forward(true)

func exit() -> void:
	var ship = owner as PlayerShip
	if ship:
		var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
		if movement:
			movement.thrust_forward(false)

func update(delta: float) -> void:
	var ship = owner as PlayerShip
	if not ship:
		return
		
	# Get movement component
	var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
	if not movement:
		return
	
	# Handle rotation while moving
	if Input.is_action_pressed("move_left"):
		movement.rotate_left()
	elif Input.is_action_pressed("move_right"):
		movement.rotate_right()
	else:
		movement.stop_rotation()
	
	# Handle boost
	if Input.is_action_pressed("boost"):
		movement.start_boost()
	else:
		movement.stop_boost()
	
	# Check for transition back to idle
	if not Input.is_action_pressed("move_up"):
		state_machine.transition_to("idle")

# ---------------------------------------------------------

# ship_rotating_state.gd
extends State
class_name ShipRotatingState

func enter(params: Dictionary = {}) -> void:
	pass

func update(delta: float) -> void:
	var ship = owner as PlayerShip
	if not ship:
		return
		
	# Get movement component
	var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
	if not movement:
		return
	
	# Handle rotation
	if Input.is_action_pressed("move_left"):
		movement.rotate_left()
	elif Input.is_action_pressed("move_right"):
		movement.rotate_right()
	else:
		movement.stop_rotation()
		state_machine.transition_to("idle")
	
	# If thrusting, transition to moving state
	if Input.is_action_pressed("move_up"):
		state_machine.transition_to("moving")

# ---------------------------------------------------------

# ship_combat_state.gd
extends State
class_name ShipCombatState

var target: Node2D
var weapon_component: WeaponComponent

func enter(params: Dictionary = {}) -> void:
	if params.has("target"):
		target = params.target
	
	var ship = owner as PlayerShip
	if ship:
		weapon_component = ship.get_node_or_null("WeaponComponent") as WeaponComponent

func exit() -> void:
	target = null

func update(delta: float) -> void:
	var ship = owner as PlayerShip
	if not ship:
		return
	
	# Check if we still have a valid target
	if not is_instance_valid(target):
		state_machine.transition_to("idle")
		return
	
	# Get movement component
	var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
	if not movement:
		return
	
	# Player movement control still works in combat
	if Input.is_action_pressed("move_up"):
		movement.thrust_forward(true)
	else:
		movement.thrust_forward(false)
	
	if Input.is_action_pressed("move_left"):
		movement.rotate_left()
	elif Input.is_action_pressed("move_right"):
		movement.rotate_right()
	else:
		movement.stop_rotation()
	
	# Fire weapon when primary action is pressed
	if Input.is_action_pressed("p1_primary") and weapon_component:
		weapon_component.fire()
	
	# Exit combat mode
	if Input.is_action_just_pressed("p1_secondary"):
		state_machine.transition_to("idle")

# ---------------------------------------------------------

# ship_damaged_state.gd
extends State
class_name ShipDamagedState

var recovery_timer: float = 0.0
var recovery_time: float = 2.0  # Time in damaged state before recovering

func enter(params: Dictionary = {}) -> void:
	recovery_timer = 0.0
	
	if params.has("recovery_time"):
		recovery_time = params.recovery_time
	
	var ship = owner as PlayerShip
	if ship:
		# Simulate damage by reducing control
		var movement = ship.get_node_or_null("MovementComponent") as MovementComponent
		if movement:
			# Apply rotation in a random direction to simulate impact
			if randf() > 0.5:
				movement.rotate_left()
			else:
				movement.rotate_right()

func update(delta: float) -> void:
	recovery_timer += delta
	
	# After recovery time, go back to idle
	if recovery_timer >= recovery_time:
		state_machine.transition_to("idle")

# ---------------------------------------------------------

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

# ---------------------------------------------------------

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
			health.heal(health.max_health, null)
	
	# Transition to idle after respawning
	state_machine.transition_to("idle")
