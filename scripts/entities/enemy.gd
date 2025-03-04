# enemy.gd
extends Node2D
class_name Enemy

var health_component
var combat_component
var movement_component
var state_machine

var original_position: Vector2
var is_active: bool = true
var detection_range: float = 300.0
var thruster_active: bool = false
var sound_system = null

func _ready():
	z_index = 5
	add_to_group("enemies")
	
	health_component = $HealthComponent
	combat_component = $CombatComponent
	movement_component = $MovementComponent
	state_machine = $StateMachine
	sound_system = get_node_or_null("/root/SoundSystem")
	
	original_position = global_position
	
	if health_component:
		health_component.connect("died", _on_died)
		
	if movement_component:
		movement_component.connect("cell_changed", _on_cell_changed)
	
	if state_machine:
		call_deferred("_check_for_player")

func _process(_delta):
	update_thruster_sound()

func _check_for_player():
	if state_machine:
		state_machine.change_state("Follow" if is_player_in_same_cell() else "Idle")

func update_active_state(is_active_state: bool):
	is_active = is_active_state
	visible = is_active
	
	if !is_active_state:
		stop_thruster_sound()
	
	process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
	
	if health_component:
		health_component.set_active(is_active)
	if combat_component:
		combat_component.set_active(is_active)
	if movement_component:
		movement_component.set_active(is_active)
	if state_machine:
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED

func is_player_in_same_cell() -> bool:
	var player = get_node_or_null("/root/Main/Player")
	
	if player and movement_component:
		var player_cell = Vector2i(-1, -1)
		
		if player.has_method("get_current_cell"):
			player_cell = player.get_current_cell()
		elif player.has_method("get_cell_position"):
			player_cell = player.get_cell_position()
		
		return player_cell.x == movement_component.cell_x and player_cell.y == movement_component.cell_y
	
	return false

func shoot_at_player(player: Node2D):
	if combat_component and player:
		var direction = (player.global_position - global_position).normalized()
		combat_component.fire(direction)
		
		if sound_system:
			sound_system.play_laser(global_position)

func can_see_player(player: Node2D) -> bool:
	if not player:
		return false
		
	var distance = global_position.distance_to(player.global_position)
	return distance <= detection_range and is_player_in_same_cell()

func check_laser_hit(laser) -> bool:
	return combat_component.check_collision(laser) if combat_component else false

func take_damage(amount: float) -> bool:
	return health_component.take_damage(amount) if health_component else false

func get_collision_rect() -> Rect2:
	var sprite = $Sprite2D
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		var scaled_size = texture_size * 0.7
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	
	return Rect2(-16, -16, 32, 32)

func get_current_cell() -> Vector2i:
	return Vector2i(movement_component.cell_x, movement_component.cell_y) if movement_component else Vector2i(-1, -1)

func update_thruster_sound():
	if not sound_system or not is_active:
		return
		
	var is_moving = movement_component and movement_component.velocity.length() > 0
	
	if is_moving and not thruster_active:
		start_thruster_sound()
	elif not is_moving and thruster_active:
		stop_thruster_sound()

func start_thruster_sound():
	if sound_system:
		sound_system.start_thruster(get_instance_id())
		thruster_active = true

func stop_thruster_sound():
	if sound_system:
		sound_system.stop_thruster(get_instance_id())
		thruster_active = false

func _on_died():
	var explode_component = $ExplodeFireComponent if has_node("ExplodeFireComponent") else null
	
	if explode_component and explode_component.has_method("explode"):
		explode_component.explode()
	
	stop_thruster_sound()
	queue_free()

func _on_cell_changed(_cell_x, _cell_y):
	_check_for_player()
