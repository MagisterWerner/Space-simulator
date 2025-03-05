# state.gd
extends Node
class_name State

# Reference to the state machine this state belongs to
var state_machine: StateMachine = null

# Called when the state is entered
func enter(_params: Dictionary = {}) -> void:
	pass

# Called when the state is exited
func exit() -> void:
	pass

# Called during _process
func update(_delta: float) -> void:
	pass

# Called during _physics_process
func physics_update(_delta: float) -> void:
	pass

# Called to handle input
func handle_input(_event: InputEvent) -> void:
	pass
