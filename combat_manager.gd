extends Node

# Called when the node enters the scene tree for the first time
func _ready():
	print("Combat manager initialized")

# Called every frame
func _process(_delta):
	# Process laser collisions
	check_all_laser_collisions()

# Check for collisions between lasers and entities
func check_all_laser_collisions():
	# Get all lasers in the scene
	var lasers = get_tree().get_nodes_in_group("lasers")
	if lasers.size() == 0:
		return
	
	# Get player
	var player = get_node_or_null("/root/Main/Player")
	
	# Get all enemies (only consider enemies that are active/visible)
	var enemies = []
	var enemy_spawner = get_node_or_null("/root/Main/EnemySpawner")
	if enemy_spawner:
		for enemy in enemy_spawner.spawned_enemies:
			if is_instance_valid(enemy) and enemy.visible:
				enemies.append(enemy)
	
	# Check player lasers against enemies
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
		else:
			# This is an enemy laser - check against player
			if player and player.check_laser_hit(laser):
				# Apply damage to player
				player.take_damage(laser.damage)
				
				# Destroy the laser
				laser.hit_target()
