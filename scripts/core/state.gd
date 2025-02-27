# scripts/core/state.gd
class_name State
extends Node

# References to the state machine and entity
var state_machine = null
var entity = null

# Configuration flags
var process_enabled = true
var physics_process_enabled = true
var input_processing_enabled = true

func _ready():
	# Ensure this state is disabled initially
	set_process(false)
	set_physics_process(false)
	
	# Initial state configuration - can be overridden in child classes
	process_enabled = true
	physics_process_enabled = true
	input_processing_enabled = true

# Initialize the state with references
func initialize(sm, e):
	state_machine = sm
	entity = e
	
# Called when entering this state
func enter():
	set_process(process_enabled)
	set_physics_process(physics_process_enabled)
	# Input processing is handled by the state machine

# Called when exiting this state
func exit():
	set_process(false)
	set_physics_process(false)

# Handle input in this state
func handle_input(_event):
	pass

# Process logic for this state
func process(_delta):
	pass

# Physics process for this state
func physics_process(_delta):
	pass

# Check for state transitions - should be implemented by child classes
# Returns the name of the state to transition to, or an empty string if no transition should occur
func get_transition():
	return ""

# Helper function to check if this state is enabled (can be overridden)
func is_enabled():
	return true
