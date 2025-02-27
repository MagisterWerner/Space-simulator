# enemy_state_follow.gd
class_name EnemyStateFollow
extends State

var check_interval: float = 0.5  # Check if player is still in cell every half second
var check_timer: float = 0.0
var max_follow_distance: float = 300.0  # Maximum distance to follow player
var min_distance: float = 40.0  # Minimum distance to maintain from player and other enemies

func enter() -> void:
	super.enter()
	print("Enemy entering follow state")
	check_timer = 0.0

func process(delta: float) -> void:
	var player = entity.get_node_or_null("/root/Main/Player")
	if not player:
		return
	
	# Check if player is still in the same cell periodically
	check_timer -= delta
	if check_timer <= 0:
		check_timer = check_interval
		if not entity.is_player_in_same_cell():
			state_machine.change_state("Idle")
			return
	
	# Calculate distance to player
	var distance_to_player = entity.global_position.distance_to(player.global_position)
	
	# Update rotation to face player regardless of movement
	var direction = player.global_position - entity.global_position
	var angle = direction.angle()
	
	if entity.has_node("Sprite2D"):
		entity.get_node("Sprite2D").rotation = angle
	
	# Only follow if within max follow distance and not too close
	if distance_to_player < max_follow_distance and distance_to_player > min_distance:
		# Calculate potential new position
		direction = direction.normalized()
		var potential_position = entity.global_position + direction * entity.movement_speed * delta
		
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
		
	# Check distance to player first
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
