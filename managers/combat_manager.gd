# combat_manager.gd
class_name CombatManager
extends Node

func _process(_delta):
	check_all_laser_collisions()

func check_all_laser_collisions():
	var lasers = get_tree().get_nodes_in_group("lasers")
	if lasers.is_empty():
		return
	
	var player = get_node_or_null("/root/Main/Player")
	
	var enemies = []
	var enemy_spawner = get_node_or_null("/root/Main/EnemySpawner")
	if enemy_spawner:
		for enemy in enemy_spawner.spawned_enemies:
			if is_instance_valid(enemy) and enemy.visible:
				enemies.append(enemy)
	
	var asteroids = get_tree().get_nodes_in_group("asteroids")
	
	for laser in lasers:
		if not is_instance_valid(laser):
			continue
			
		if laser.is_player_laser:
			handle_player_laser(laser, enemies, asteroids)
		else:
			handle_enemy_laser(laser, player, asteroids)

func handle_player_laser(laser, enemies, asteroids):
	# Check against enemies
	for enemy in enemies:
		if enemy.check_laser_hit(laser):
			enemy.take_damage(laser.damage)
			laser.hit_target()
			return
	
	# Check against asteroids
	for asteroid in asteroids:
		if asteroid.check_laser_hit(laser):
			asteroid.take_damage(laser.damage)
			laser.hit_target()
			return

func handle_enemy_laser(laser, player, asteroids):
	# Check against player
	if player and player.check_laser_hit(laser):
		player.take_damage(laser.damage)
		laser.hit_target()
		return
	
	# Check against asteroids
	for asteroid in asteroids:
		if asteroid.check_laser_hit(laser):
			asteroid.take_damage(laser.damage)
			laser.hit_target()
			return
