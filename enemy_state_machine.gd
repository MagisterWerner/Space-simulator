class_name EnemyStateMachine
extends Node

# Reference to enemy node
var enemy: Node2D
var current_state: EnemyStateBase
var states: Dictionary = {}

func _ready():
	enemy = get_parent()
	
	# Register all child states
	for child in get_children():
		if child is EnemyStateBase:
			states[child.name] = child
			child.enemy = enemy
	
	# Initialize with default state if available
	if states.has("Idle"):
		change_state("Idle")

func _process(delta):
	if current_state:
		current_state.process(delta)

func _physics_process(delta):
	if current_state:
		current_state.physics_process(delta)

# Change to a different state
func change_state(state_name: String):
	if current_state and current_state.name == state_name:
		return  # Already in this state
		
	if current_state:
		current_state.exit()
	
	if states.has(state_name):
		current_state = states[state_name]
		current_state.enter()
		print("Enemy state changed to: ", state_name)
	else:
		push_error("State " + state_name + " not found in EnemyStateMachine")