extends State
class_name EnemyStateFollow

var movement_component
var combat_component
var check_interval: float = 0.5
var check_timer: float = 0.0
var max_follow_distance: float = 300.0
var min_distance: float = 40.0

func enter() -> void:
	super.enter()
	
	# Get references to components
	movement_component = entity.get_node_or_null("MovementComponent")
	combat_component = entity.get_node_or_null("CombatComponent")
	
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
	
	# Set facing direction using movement component
	if movement_component:
		movement_component.set_facing_direction(direction.normalized())
	
	# Only follow if within max follow distance and not too close
	if distance_to_player < max_follow_distance and distance_to_player > min_distance:
		# Calculate potential new position
		direction = direction.normalized()
		var potential_position = entity.global_position + direction * (movement_component.speed if movement_component else 150.0) * delta
		
		# Check for collisions with other enemies before moving
		if not would_collide_with_enemies(potential_position):
			if movement_component:
				movement_component.move(direction)
			else:
				entity.global_position = potential_position
	else:
		# Stop if too close or too far
		if movement_component:
			movement_component.stop()
	
	# Try to shoot at player if possible
	if combat_component and combat_component.can_fire() and entity.can_see_player(player):
		entity.shoot_at_player(player)

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
