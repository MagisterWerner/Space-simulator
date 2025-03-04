# state_machine.gd
class_name StateMachine
extends Node

var entity = null
var current_state = null
var previous_state = null
var states = {}
var state_history = []
var max_history_size = 10

func _ready():
	entity = get_parent()
	if not entity:
		push_error("StateMachine must be a child of a Node")
		return
	
	for child in get_children():
		if child.has_method("enter") and child.has_method("exit"):
			states[child.name] = child
			
			if child.has_method("initialize"):
				child.initialize(self, entity)
			
			if "state_machine" in child:
				child.state_machine = self
			if "entity" in child:
				child.entity = entity

func _process(delta):
	if current_state and current_state.has_method("process"):
		current_state.process(delta)

func _physics_process(delta):
	if current_state and current_state.has_method("physics_process"):
		current_state.physics_process(delta)

func _input(event):
	if current_state and current_state.has_method("handle_input"):
		current_state.handle_input(event)

func change_state(state_name):
	if not states.has(state_name):
		push_error("Cannot change to non-existent state: " + state_name)
		return false
	
	if current_state:
		current_state.exit()
		previous_state = current_state
		
		state_history.append(current_state.name)
		if state_history.size() > max_history_size:
			state_history.pop_front()
	
	current_state = states[state_name]
	current_state.enter()
	return true

func go_back_to_previous_state():
	if previous_state:
		return change_state(previous_state.name)
	return false

func get_current_state_name():
	if current_state:
		return current_state.name
	return ""

func has_state(state_name):
	return states.has(state_name)
