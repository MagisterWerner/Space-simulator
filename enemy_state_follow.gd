class_name EnemyStateFollow
extends EnemyStateBase

var check_interval = 0.5  # Check if player is still in cell every half second
var check_timer = 0.0
var max_follow_distance = 300.0  # Maximum distance to follow player
var min_distance = 40.0  # Minimum distance to maintain from player and other enemies

func enter():
	super.enter()
	print("Enemy entering follow state")
	check_timer = 0.0

func exit():
	super.exit()
	print("Enemy exiting follow state")

func process(delta):
	var player = get_node_or_null("/root/Main/Player")
	if not player:
		return
	
	# Check if player is still in the same cell periodically
	check_timer -= delta
	if check_timer <= 0:
		check_timer = check_interval
		if not enemy.is_player_in_same_cell():
			enemy.check_for_player()
			return
	
	# Calculate distance to player
	var distance_to_player = enemy.global_position.distance_to(player.global_position)
	
	# Only follow if within max follow distance and not too close
	if distance_to_player < max_follow_distance and distance_to_player > min_distance:
		# Calculate potential new position
		var direction = player.global_position - enemy.global_position
		direction = direction.normalized()
		var potential_position = enemy.global_position + direction * enemy.movement_speed * delta
		
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
		
	# Check distance to player first
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
