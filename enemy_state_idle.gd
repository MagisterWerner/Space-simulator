class_name EnemyStateIdle
extends EnemyStateBase

var return_speed = 0.5  # Slow return to original position
var check_interval = 1.0  # Check for player every second
var check_timer = 0.0
var min_distance = 40.0  # Minimum distance to maintain from other enemies

func enter():
	super.enter()
	print("Enemy entering idle state")
	check_timer = 0.0

func exit():
	super.exit()
	print("Enemy exiting idle state")

func process(delta):
	# Check for player periodically
	check_timer -= delta
	if check_timer <= 0:
		check_timer = check_interval
		if enemy.is_player_in_same_cell():
			enemy.check_for_player()
			return
	
	# Gradually return to original position when idle
	if enemy.global_position.distance_to(enemy.original_position) > 5:
		var direction = enemy.original_position - enemy.global_position
		direction = direction.normalized()
		
		# Calculate potential new position
		var potential_position = enemy.global_position + direction * enemy.movement_speed * return_speed * delta
		
		# Check for collisions with other enemies before moving
		if not would_collide_with_enemies(potential_position):
			enemy.global_position = potential_position
	
	# Update current cell if moved to a different cell
	if enemy.update_cell_position():
		enemy.check_for_player()
	
	# Keep the enemy visible
	enemy.queue_redraw()

# Function to check if a potential position would cause collision with other enemies
func would_collide_with_enemies(potential_position):
	var enemy_spawner = get_node_or_null("/root/Main/EnemySpawner")
	if not enemy_spawner:
		return false
		
	# Check distance to player
	var player = get_node_or_null("/root/Main/Player")
	if player and potential_position.distance_to(player.global_position) < min_distance:
		return true
		
	# Check distance to other enemies
	for other_enemy in enemy_spawner.spawned_enemies:
		if is_instance_valid(other_enemy) and other_enemy != enemy:
			# Only check visible enemies (those in loaded chunks)
			if other_enemy.visible and potential_position.distance_to(other_enemy.global_position) < min_distance:
				return true
				
	return false
