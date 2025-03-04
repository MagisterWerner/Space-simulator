# enemy_state_idle.gd
extends State
class_name EnemyStateIdle

var movement_component
var return_speed: float = 0.5
var check_interval: float = 1.0
var check_timer: float = 0.0
var min_distance: float = 40.0

func enter() -> void:
	super.enter()
	movement_component = entity.get_node_or_null("MovementComponent")
	check_timer = 0.0

func process(delta: float) -> void:
	check_timer -= delta
	if check_timer <= 0:
		check_timer = check_interval
		if entity.is_player_in_same_cell():
			state_machine.change_state("Follow")
			return
	
	if entity.global_position.distance_to(entity.original_position) > 5:
		var direction = (entity.original_position - entity.global_position).normalized()
		
		if movement_component:
			var original_speed = movement_component.speed
			movement_component.speed = original_speed * return_speed
			movement_component.move(direction)
			movement_component.speed = original_speed
		else:
			var potential_position = entity.global_position + direction * 150.0 * return_speed * delta
			
			if not would_collide_with_enemies(potential_position):
				entity.global_position = potential_position
	elif movement_component:
		movement_component.stop()

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
