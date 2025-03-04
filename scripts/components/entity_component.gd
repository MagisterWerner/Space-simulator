# scripts/components/entity_component.gd
class_name EntityComponent
extends Node

@export var movement_speed: float = 300.0
@export var max_health: float = 100.0
@export var fire_cooldown: float = 0.5

var current_health: float = 100.0
var current_cooldown: float = 0.0
var is_invulnerable: bool = false
var invulnerability_timer: float = 0.0
var hit_flash_timer: float = 0.0
var is_hit: bool = false

func _ready():
	current_health = max_health

func _process(delta):
	current_cooldown = max(0, current_cooldown - delta)
	
	if is_invulnerable:
		invulnerability_timer -= delta
		is_invulnerable = invulnerability_timer > 0
	
	if is_hit:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0:
			is_hit = false
			var sprite = get_parent().get_node_or_null("Sprite2D")
			if sprite:
				sprite.modulate = Color.WHITE

func take_damage(amount: float) -> void:
	if is_invulnerable:
		return
	
	current_health -= amount
	is_hit = true
	hit_flash_timer = 0.2
	
	var sprite = get_parent().get_node_or_null("Sprite2D")
	if sprite:
		sprite.modulate = Color.RED
	
	if current_health <= 0:
		get_parent().on_death() if get_parent().has_method("on_death") else null
	else:
		is_invulnerable = true
		invulnerability_timer = 1.0

func shoot(position: Vector2, direction: Vector2, is_player_laser: bool = false, damage: float = 10.0) -> void:
	if current_cooldown > 0:
		return
	
	var resource_manager = get_node_or_null("/root/Main/ResourceManager")
	var laser = resource_manager.create_laser(is_player_laser) if resource_manager else load("res://laser.tscn").instantiate()
	
	if not laser:
		return
	
	laser.global_position = position + direction * 30
	laser.direction = direction
	laser.rotation = direction.angle()
	laser.is_player_laser = is_player_laser
	laser.damage = damage
	
	get_tree().current_scene.add_child(laser)
	current_cooldown = fire_cooldown

func check_laser_hit(laser, collision_rect: Rect2, is_player: bool) -> bool:
	if is_invulnerable or \
	   (is_player and laser.is_player_laser) or \
	   (not is_player and not laser.is_player_laser):
		return false
	
	var owner_pos = get_parent().global_position
	var laser_pos = laser.global_position
	
	collision_rect.position += owner_pos
	var laser_rect = laser.get_collision_rect()
	laser_rect.position += laser_pos
	
	return collision_rect.intersects(laser_rect)
