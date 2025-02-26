class_name PlayerStateMachine
extends Node

# Reference to player node
var player: Node2D
var current_state: PlayerStateBase
var states: Dictionary = {}

func _ready():
	player = get_parent()
	
	# Register all child states
	for child in get_children():
		if child is PlayerStateBase:
			states[child.name] = child
			child.player = player
	
	# Initialize with default state if available
	if states.has("Normal"):
		change_state("Normal")

func _process(delta):
	if current_state:
		current_state.process(delta)

func _physics_process(delta):
	if current_state:
		current_state.physics_process(delta)

func _input(event):
	if current_state:
		current_state.handle_input(event)

# Change to a different state
func change_state(state_name: String):
	if current_state:
		current_state.exit()
	
	if states.has(state_name):
		current_state = states[state_name]
		current_state.enter()
		print("Player state changed to: ", state_name)
	else:
		push_error("State " + state_name + " not found in PlayerStateMachine")
