# Primary node that takes care of sending setup instructions to some of the
# game's sub-systems; passing along the location of the map viewport for
# mappable objects, informing pirates of obstacles in the world, and 
# giving the player access to the game camera.
extends Node

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if (not ((get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN) or (get_window().mode == Window.MODE_FULLSCREEN))) else Window.MODE_WINDOWED
		get_viewport().set_input_as_handled()
