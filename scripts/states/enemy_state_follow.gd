# enemy_state_follow.gd
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
	movement_component = entity.get_node_or_null("MovementComponent")
	combat_component = entity.get_node_or_null("CombatComponent")
	check_timer = 0.0

func process(delta: float) -> void:
	var player = entity.get_node_or_null("/root/Main/Player")
	if not player:
		return
	
	check_timer -= delta
	if check_timer <= 0:
		check_timer = check_interval
		if not entity.is_player_in_same_cell():
			state_machine.change_state("Idle")
			return
	
	var direction = player.global_position - entity.global_position
	var distance_to_player = direction.length()
	direction = direction.normalized()
	
	if movement_component:
		movement_component.set_facing_direction(direction)
	
	if distance_to_player < max_follow_distance and distance_to_player > min_distance:
		var potential_position = entity.global_position + direction * (movement_component.speed if movement_component else 150.0) * delta
		
		if not would_collide_with_enemies(potential_position):
			if movement_component:
				movement_component.move(direction)
			else:
				entity.global_position = potential_position
	elif movement_component:
		movement_component.stop()
	
	if combat_component and combat_component.can_fire() and entity.can_see_player(player):
		entity.shoot_at_player(player)

func would_collide_with_enemies(potential_position: Vector2) -> bool:
	var enemy_spawner = entity.get_node_or_null("/root/Main/EnemySpawner")
	if not enemy_spawner:
		return false
		
	var player = entity.get_node_or_null("/root/Main/Player")
	if player and potential_position.distance_to(player.global_position) < min_distance:
		return true
		
	for other_enemy in enemy_spawner.spawned_enemies:
		if is_instance_valid(other_enemy) and other_enemy != entity and other_enemy.visible:
			if potential_position.distance_to(other_enemy.global_position) < min_distance:
				return true
				
	return false
