extends Area2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	get_parent().material.set("shader_param/width", 0.0)


func _on_Hitbox_body_entered(body: Node) -> void:
	if body is Player:
		get_parent().material.set("shader_param/width", 3.0)
		print("You have reached a large trading vessel. [", self.name, "]")

		get_tree().create_timer(5).connect("timeout", Callable(self, "_timeout").bind(body))


func _on_Hitbox_body_exited(body: Node) -> void:
	if body is Player:
		get_parent().material.set("shader_param/width", 0.0)


func _timeout(body: Node):
	if not SoundManager.is_music_playing(Globals.music_safety):
		SoundManager.play_music(Globals.music_safety, 1)
	if body.health < body.MAX_HEALTH:
		body.health = body.MAX_HEALTH
#		emit_signal("player_stats_changed", body)
		print("Your ship is now fully repaired!")
