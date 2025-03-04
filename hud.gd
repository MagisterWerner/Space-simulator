# hud.gd
extends CanvasLayer

@onready var health_bar = $HealthBar
@onready var speed_label = $SpeedLabel

var player_ship: PlayerShip

func _ready() -> void:
	await get_tree().process_frame
	
	var players = get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		player_ship = players[0]
		player_ship.connect("health_updated", _on_player_health_updated)
		health_bar.max_value = player_ship.max_health
		health_bar.value = player_ship.health

func _process(_delta: float) -> void:
	if player_ship:
		var speed = player_ship.linear_velocity.length()
		speed_label.text = "Speed: %d" % int(speed)

func _on_player_health_updated(new_health: int) -> void:
	health_bar.value = new_health
