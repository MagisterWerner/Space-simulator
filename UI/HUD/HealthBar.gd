extends ColorRect

func _on_Player_player_stats_changed(player):
	$Bar.size.x = 72 * player.health / player.MAX_HEALTH
