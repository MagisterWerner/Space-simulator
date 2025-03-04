extends Control

func _ready() -> void:
	Events.connect("player_position", Callable(self, "_updateCoordinates"))

func _updateCoordinates(player_position):
	var coords = str(Vector2(floor(player_position.x/10), floor(player_position.y/10)))
	$Number.text = coords
