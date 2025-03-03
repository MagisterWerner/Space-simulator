class_name CombatManager
extends Node

func _process(_delta):
	check_all_laser_collisions()

func check_all_laser_collisions():
	# Get all lasers in the scene
	var lasers = get_tree().get_nodes_in_group("lasers")
	if lasers.size() == 0:
		return
	
	# Get player - check for PlayerOne first, then fallback to Player if needed
	var player = get_node_or_null("/root/Main/PlayerOne")
	if not player:
		player = get_node_or_null("/root/Main/Player")
	
	# Get all enemies (only consider enemies that are active/visible)
	var enemies = []
	var enemy_spawner = get_node_or_null("/root/Main/EnemySpawner")
	if enemy_spawner:
		for enemy in enemy_spawner.spawned_enemies:
			if is_instance_valid(enemy) and enemy.visible:
				enemies.append(enemy)
	
	# Get all asteroids
	var asteroids = get_tree().get_nodes_in_group("asteroids")
	
	# Check player lasers against enemies and asteroids
	for laser in lasers:
		if not is_instance_valid(laser):
			continue
			
		# Check if this is a player laser
		if laser.is_player_laser:
			# Check against all enemies
			for enemy in enemies:
				if enemy.check_laser_hit(laser):
					# Apply damage to enemy
					enemy.take_damage(laser.damage)
					
					# Destroy the laser
					laser.hit_target()
					break
			
			# Check against all asteroids if laser still exists
			if is_instance_valid(laser):
				for asteroid in asteroids:
					if asteroid.check_laser_hit(laser):
						# Apply damage to asteroid
						asteroid.take_damage(laser.damage)
						
						# Destroy the laser
						laser.hit_target()
						break
		else:
			# This is an enemy laser - check against player
			if player and player.check_laser_hit(laser):
				# Apply damage to player
				player.take_damage(laser.damage)
				
				# Destroy the laser
				laser.hit_target()
				
			# Check against all asteroids if laser still exists
			elif is_instance_valid(laser):
				for asteroid in asteroids:
					if asteroid.check_laser_hit(laser):
						# Apply damage to asteroid
						asteroid.take_damage(laser.damage)
						
						# Destroy the laser
						laser.hit_target()
						break
