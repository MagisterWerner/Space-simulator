extends Component
class_name CombatComponent

signal weapon_fired(position, direction)

@export var fire_cooldown: float = 0.5
@export var damage: float = 10.0
@export var range: float = 300.0
@export var is_player_weapon: bool = false

var current_cooldown: float = 0.0
var laser_scene: PackedScene = preload("res://laser.tscn")

func _process(delta):
	if current_cooldown > 0:
		current_cooldown -= delta

func fire(direction: Vector2) -> bool:
	if current_cooldown > 0:
		return false
		
	var laser = laser_scene.instantiate()
	
	# Set position slightly in front of the entity
	var spawn_offset = direction * 30
	laser.global_position = entity.global_position + spawn_offset
	
	# Set laser direction and properties
	laser.direction = direction
	laser.rotation = direction.angle()
	laser.is_player_laser = is_player_weapon
	laser.damage = damage
	
	# Add laser to the main scene
	entity.get_tree().current_scene.add_child(laser)
	
	# Reset cooldown
	current_cooldown = fire_cooldown
	
	emit_signal("weapon_fired", entity.global_position, direction)
	return true

func can_fire() -> bool:
	return current_cooldown <= 0

func check_collision(laser) -> bool:
	# Check collision with this entity's collision rect
	if entity.has_method("get_collision_rect"):
		var collision_rect = entity.get_collision_rect()
		var laser_rect = laser.get_collision_rect()
		
		# Offset to global coordinates
		collision_rect.position += entity.global_position
		laser_rect.position += laser.global_position
		
		# Only collide with lasers from the opposite type (player/enemy)
		if laser.is_player_laser != is_player_weapon:
			return collision_rect.intersects(laser_rect)
	
	return false
