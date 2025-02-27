class_name EnemyStateIdle
extends State

var return_speed: float = 0.5  # Slow return to original position
var check_interval: float = 1.0  # Check for player every second
var check_timer: float = 0.0
var min_distance: float = 40.0  # Minimum distance to maintain from other enemies

func enter() -> void:
	super.enter()
	print("Enemy entering idle state")
	check_timer = 0.0

func process(delta: float) -> void:
	# Check for player periodically
	check_timer -= delta
	if check_timer <= 0:
		check_timer = check_interval
		if entity.is_player_in_same_cell():
			state_machine.change_state("Follow")
			return
	
	# Gradually return to original position when idle
	if entity.global_position.distance_to(entity.original_position) > 5:
		var direction = entity.original_position - entity.global_position
		direction = direction.normalized()
		
		# Calculate potential new position
		var potential_position = entity.global_position + direction * entity.movement_speed * return_speed * delta
		
		# Check for collisions with other enemies before moving
		if not would_collide_with_enemies(potential_position):
			entity.global_position = potential_position
	
	# Update current cell if moved to a different cell
	if entity.update_cell_position():
		entity.check_for_player()

# Function to check if a potential position would cause collision with other enemies
func would_collide_with_enemies(potential_position: Vector2) -> bool:
	var enemy_spawner = entity.get_node_or_null("/root/Main/EnemySpawner")
	if not enemy_spawner:
		return false
		
	# Check distance to player
	var player = entity.get_node_or_null("/root/Main/Player")
	if player and potential_position.distance_to(player.global_position) < min_distance:
		return true
		
	# Check distance to other enemies
	for other_enemy in enemy_spawner.spawned_enemies:
		if is_instance_valid(other_enemy) and other_enemy != entity:
			# Only check visible enemies (those in loaded chunks)
			if other_enemy.visible and potential_position.distance_to(other_enemy.global_position) < min_distance:
				return true
				
	return false
