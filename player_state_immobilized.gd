class_name PlayerStateImmobilized
extends PlayerStateBase

func enter():
	super.enter()
	print("Player immobilized")

func exit():
	super.exit()
	print("Player movement restored")

# No movement processing in immobilized state
func process(_delta):
	# Simply keep the player visible
	player.queue_redraw()
