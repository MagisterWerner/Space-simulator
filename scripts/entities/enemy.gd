extends Node2D
class_name Enemy

# Component references
var health_component
var combat_component
var movement_component
var state_machine

# Enemy-specific properties
var original_position: Vector2
var is_active: bool = true
var detection_range: float = 300.0 # Add explicit detection range

func _ready():
	# Set basic properties
	z_index = 5
	add_to_group("enemies")
	
	# Get component references
	health_component = $HealthComponent
	combat_component = $CombatComponent
	movement_component = $MovementComponent
	state_machine = $StateMachine
	
	# Store original position
	original_position = global_position
	
	# Connect signals
	if health_component:
		health_component.connect("died", _on_died)
		
	if movement_component:
		movement_component.connect("cell_changed", _on_cell_changed)
	
	# Initialize state machine if available
	if state_machine:
		call_deferred("_check_for_player")

func _check_for_player():
	if state_machine:
		if is_player_in_same_cell():
			state_machine.change_state("Follow")
		else:
			state_machine.change_state("Idle")

func update_active_state(is_active_state: bool):
	is_active = is_active_state
	visible = is_active
	
	# Update process states
	process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
	
	# Update all components
	if health_component:
		health_component.set_active(is_active)
	if combat_component:
		combat_component.set_active(is_active)
	if movement_component:
		movement_component.set_active(is_active)
	if state_machine:
		state_machine.process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
	is_active = is_active_state
	visible = is_active
	
	# Update process states
	process_mode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
	
	# Update all components
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
		
		# Try to get player's cell either through its movement component or directly
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

func can_see_player(player: Node2D) -> bool:
	if not player:
		return false
		
	# Get distance to player
	var distance = global_position.distance_to(player.global_position)
	
	# Check if player is within range and in the same cell
	return distance <= detection_range and is_player_in_same_cell()

func check_laser_hit(laser) -> bool:
	if combat_component:
		return combat_component.check_collision(laser)
	return false

func take_damage(amount: float) -> bool:
	if health_component:
		return health_component.take_damage(amount)
	return false

func get_collision_rect() -> Rect2:
	var sprite = $Sprite2D
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		# Make the collision rect a bit smaller than the sprite
		var scaled_size = texture_size * 0.7
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	else:
		# Fallback collision rect
		return Rect2(-16, -16, 32, 32)

func get_current_cell() -> Vector2i:
	if movement_component:
		return Vector2i(movement_component.cell_x, movement_component.cell_y)
	return Vector2i(-1, -1)

# Signal handlers
func _on_died():
	queue_free()

func _on_cell_changed(_cell_x, _cell_y):
	# Check if player is in the same cell when cell changes
	_check_for_player()
