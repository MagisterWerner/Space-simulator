# scripts/components/entity_component.gd
class_name EntityComponent
extends Node

# --- Common properties for all entities ---
@export var movement_speed: float = 300.0
@export var max_health: float = 100.0
@export var fire_cooldown: float = 0.5  # Seconds between shots

# Runtime variables
var current_health: float = 100.0
var current_cooldown: float = 0.0
var is_invulnerable: bool = false
var invulnerability_timer: float = 0.0
var hit_flash_timer: float = 0.0
var hit_flash_duration: float = 0.2
var is_hit: bool = false

# Owner entity (parent node)
var owner_entity = null

func _ready():
	# Get reference to owner entity
	owner_entity = get_parent()
	if not owner_entity:
		push_error("EntityComponent must be a child of a Node2D")
		return
	
	# Initialize health
	current_health = max_health
	print("EntityComponent initialized for: " + owner_entity.name)

func _process(delta):
	# Update shooting cooldown
	if current_cooldown > 0:
		current_cooldown -= delta
	
	# Update invulnerability timer
	if is_invulnerable:
		invulnerability_timer -= delta
		if invulnerability_timer <= 0:
			is_invulnerable = false
			
	# Update hit flash effect
	if is_hit:
		hit_flash_timer -= delta
		if hit_flash_timer <= 0:
			is_hit = false
			if owner_entity.has_node("Sprite2D"):
				owner_entity.get_node("Sprite2D").modulate = Color.WHITE

# Handle taking damage
func take_damage(amount: float) -> void:
	# No damage if invulnerable
	if is_invulnerable:
		return
	
	# Apply damage
	current_health -= amount
	print(owner_entity.name + " took " + str(amount) + " damage. Health: " + str(current_health))
	
	# Visual feedback
	is_hit = true
	hit_flash_timer = hit_flash_duration
	if owner_entity.has_node("Sprite2D"):
		owner_entity.get_node("Sprite2D").modulate = Color.RED
	
	# Check for death
	if current_health <= 0:
		die()
	else:
		# Set temporary invulnerability
		is_invulnerable = true
		invulnerability_timer = 1.0  # Default value, can be overridden

# Base die function to be implemented by users
func die() -> void:
	# Emit a signal that can be handled by the owner
	print(owner_entity.name + " died")
	
	# Call a die method on the owner if it exists
	if owner_entity.has_method("on_death"):
		owner_entity.on_death()

# Shooting helper function
func shoot(position: Vector2, direction: Vector2, is_player_laser: bool = false, damage: float = 10.0) -> void:
	# Create the laser instance
	var laser_scene = load("res://laser.tscn")
	var laser = laser_scene.instantiate()
	
	# Set position slightly in front of the entity
	var spawn_offset = direction * 30
	laser.global_position = position + spawn_offset
	
	# Set laser direction and rotation
	laser.direction = direction
	laser.rotation = direction.angle()
	
	# Configure the laser
	laser.is_player_laser = is_player_laser
	laser.damage = damage
	
	# Set laser color
	var sprite = laser.get_node("Sprite2D")
	if sprite:
		if is_player_laser:
			sprite.texture = load("res://sprites/weapons/laser_blue.png")
		else:
			sprite.texture = load("res://sprites/weapons/laser_red.png")
	
	# Add laser to scene
	owner_entity.get_tree().current_scene.add_child(laser)
	
	# Reset cooldown
	current_cooldown = fire_cooldown

# Helper function to check laser hit
func check_laser_hit(laser, collision_rect: Rect2, is_player: bool) -> bool:
	# Skip if invulnerable
	if is_invulnerable:
		return false
	
	# Check if this is an appropriate laser type to hit us
	if (is_player and laser.is_player_laser) or \
	   (not is_player and not laser.is_player_laser):
		return false
	
	# Get laser collision rect
	var laser_rect = laser.get_collision_rect()
	
	# Offset to global coordinates
	collision_rect.position += owner_entity.global_position
	laser_rect.position += laser.global_position
	
	# Check for intersection
	return collision_rect.intersects(laser_rect)
