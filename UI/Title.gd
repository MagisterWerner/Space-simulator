extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


func _on_SinglePlayer_button_up() -> void:
	get_tree().change_scene_to_file("res://Main/Main.tscn")


func _on_SplitScreen_button_up() -> void:
	pass


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen"):
		get_window().mode = Window.MODE_EXCLUSIVE_FULLSCREEN if (not ((get_window().mode == Window.MODE_EXCLUSIVE_FULLSCREEN) or (get_window().mode == Window.MODE_FULLSCREEN))) else Window.MODE_WINDOWED
		get_viewport().set_input_as_handled()
