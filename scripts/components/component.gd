extends Node
class_name Component

signal enabled_state_changed(is_enabled)

# Common component properties
@export var enabled: bool = true
@export var component_name: String = ""
@export var debug_mode: bool = false

func _ready() -> void:
	# Check for debug settings in scene
	var main_scene = get_tree().current_scene
	var game_settings = main_scene.get_node_or_null("GameSettings")
	if game_settings and game_settings.has("debug_components"):
		debug_mode = game_settings.debug_mode and game_settings.debug_components
	
	# Set default component name if not provided
	if component_name.is_empty():
		component_name = get_script().resource_path.get_file().get_basename()

# Enable the component
func enable() -> void:
	if enabled:
		return
		
	enabled = true
	enabled_state_changed.emit(true)
	
	if debug_mode:
		print(component_name + " enabled")

# Disable the component
func disable() -> void:
	if not enabled:
		return
		
	enabled = false
	enabled_state_changed.emit(false)
	
	if debug_mode:
		print(component_name + " disabled")

# Toggle the component's enabled state
func toggle() -> void:
	if enabled:
		disable()
	else:
		enable()
