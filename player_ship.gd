# player_ship.gd
extends RigidBody2D
class_name PlayerShip

signal player_damaged(amount)
signal player_died
signal player_respawned

# Core Components
@onready var health_component: HealthComponent = $HealthComponent
@onready var movement_component: MovementComponent = $MovementComponent
@onready var shield_component: ShieldComponent = $ShieldComponent
@onready var weapon_component: WeaponComponent = $WeaponComponent
@onready var state_machine: StateMachine = $StateMachine

# Debug properties
@export var debug_mode: bool = false

func _ready() -> void:
	# Connect component signals
	if health_component:
		health_component.damaged.connect(_on_health_damaged)
		health_component.died.connect(_on_health_died)
	
	# Ensure we're in the player group
	if not is_in_group("player"):
		add_to_group("player")

func _physics_process(delta: float) -> void:
	# The actual movement is handled by MovementComponent and StateMachine
	pass

func _on_health_damaged(amount: float, source: Node) -> void:
	# Emit player damaged signal
	player_damaged.emit(amount)
	
	# Change state to damaged if health is low
	if health_component and health_component.is_critical() and state_machine:
		state_machine.transition_to("damaged")
	
	debug_print("Player took %s damage" % amount)

func _on_health_died() -> void:
	# Emit player died signal
	player_died.emit()
	
	# Change state to dead
	if state_machine:
		state_machine.transition_to("dead")
	
	debug_print("Player died")

func respawn(position: Vector2 = Vector2.ZERO) -> void:
	# Reset position
	global_position = position
	
	# Reset physics state
	linear_velocity = Vector2.ZERO
	angular_velocity = 0
	
	# Enable components
	for child in get_children():
		if child is Component:
			child.enable()
	
	# Heal the ship
	if health_component:
		health_component.heal(health_component.max_health, null)
	
	# Reset shield
	if shield_component:
		shield_component.current_shield = shield_component.max_shield
		shield_component.shield_changed.emit(shield_component.current_shield, shield_component.max_shield)
	
	# Change state to idle
	if state_machine:
		state_machine.transition_to("idle")
	
	# Emit player respawned signal
	player_respawned.emit()
	
	debug_print("Player respawned")

func play_death_effect() -> void:
	# Optional: Implement death effect here
	pass

func add_upgrade_strategy(strategy: Strategy, component_name: String) -> bool:
	var component = get_node_or_null(component_name)
	
	if not component or not component is Component:
		debug_print("Failed to add strategy: component not found")
		return false
	
	# Apply the strategy to the component
	strategy.apply_to_component(component)
	
	debug_print("Added strategy: %s to %s" % [strategy.strategy_name, component_name])
	return true

func remove_upgrade_strategy(strategy: Strategy) -> void:
	if strategy.owner_component:
		strategy.remove_from_component()
		debug_print("Removed strategy: %s" % strategy.strategy_name)

func _on_body_entered(body: Node) -> void:
	# Handle collision with other bodies
	if body.is_in_group("asteroid"):
		# Take collision damage from asteroids
		if health_component:
			var impact_velocity = linear_velocity.length()
			var damage = impact_velocity * 0.05  # Scale damage based on impact velocity
			health_component.apply_damage(damage, "collision", body)
	
	elif body.is_in_group("enemy"):
		# Take collision damage from enemies
		if health_component:
			health_component.apply_damage(20.0, "collision", body)
	
	debug_print("Collided with: %s" % body.name)

func debug_print(message: String) -> void:
	if debug_mode:
		print("[PlayerShip] %s" % message)
