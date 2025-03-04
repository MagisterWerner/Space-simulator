extends CanvasLayer

@onready var pause := self
@onready var resume_option := $MarginContainer/Control/VBoxOptions/Resume
@onready var pause_options = $MarginContainer/Control/VBoxOptions
@onready var color_rect = $ColorRect

@onready var pause_group = [pause_options, color_rect] # should be visible only in pause menu


func _ready():
	pause_hide()


func pause_show():

	for n in pause_group:
		n.show()

func pause_hide():
	for n in pause_group:
		if n:
			n.hide()


func _unhandled_input(event):
	if event.is_action_pressed("pause"):
		if get_tree().paused:
			resume()
		else:
			pause_game()
		get_viewport().set_input_as_handled()


func resume():
	get_tree().paused = false
	pause_hide()


func pause_game():
	resume_option.grab_focus()
	get_tree().paused = true
	pause_show()


func _on_Resume_pressed():
	resume()


func _on_PauseButton_pressed():
	pause_game()


func _on_main_menu_pressed():
	Game.change_scene_to_file("res://scenes/menu/menu.tscn", {"show_progress_bar": false})
