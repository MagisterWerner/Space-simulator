# scripts/core/entity.gd
class_name Entity
extends Node2D

# --- Common properties for all entities ---
@export var movement_speed: float = 300.0
@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var fire_cooldown: float = 0.5  # Seconds between shots
@export var is_invulnerable: bool = false

# --- Combat variables ---
var current_cooldown: float = 0.0
var invulnerability_timer: float = 0.0
var hit_flash_timer: float = 0.0
var hit_flash_duration: float = 0.2
var is_hit: bool = false

# --- State Machine Reference ---
@onready var state_machine = $StateMachine

# --- Grid positioning ---
var cell_x: int = -1
var cell_y: int = -1
var last_valid_position: Vector2 = Vector2.ZERO

# --- Cached nodes ---
var grid: Node2D
var main: Node2D
var laser_scene = preload("res://laser.tscn")

func _ready():
	# Initialize health
	current_health = max_health
	
	# Get references to commonly used nodes
	grid = get_node_or_null("/root/Main/Grid")
	main = get_node_or_null("/root/Main")
	
	# Calculate initial cell position
	update_cell_position()
	
	# Store initial position as the last valid position
	last_valid_position = global_position
	
	# Initialize state machine if it exists
	if state_machine:
		# State machine initialization should happen in child classes
		pass

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
			if has_node("Sprite2D"):
				get_node("Sprite2D").modulate = Color.WHITE

# Updates the entity's cell position in the grid
func update_cell_position() -> bool:
	if grid:
		var new_cell_x = int(floor(global_position.x / grid.cell_size.x))
		var new_cell_y = int(floor(global_position.y / grid.cell_size.y))
		
		if new_cell_x != cell_x or new_cell_y != cell_y:
			cell_x = new_cell_x
			cell_y = new_cell_y
			return true
	
	return false

# Handle taking damage
func take_damage(amount: float) -> void:
	# No damage if invulnerable
	if is_invulnerable:
		return
	
	# Apply damage
	current_health -= amount
	print(self.name + " took " + str(amount) + " damage. Health: " + str(current_health))
	
	# Visual feedback
	is_hit = true
	hit_flash_timer = hit_flash_duration
	if has_node("Sprite2D"):
		get_node("Sprite2D").modulate = Color.RED
	
	# Check for death
	if current_health <= 0:
		die()
	else:
		# Set temporary invulnerability (duration should be set by child classes)
		is_invulnerable = true

# Base die function to be overridden
func die() -> void:
	print(self.name + " died")
	queue_free()

# Base shooting function that handles common behavior
func shoot(is_player_laser: bool = false, direction: Vector2 = Vector2.RIGHT, damage: float = 10.0, color: Color = Color.RED) -> void:
	# Create the laser instance
	var laser = laser_scene.instantiate()
	
	# Set position slightly in front of the entity
	var spawn_offset = direction * 30
	laser.global_position = global_position + spawn_offset
	
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
	get_tree().current_scene.add_child(laser)
	
	# Reset cooldown
	current_cooldown = fire_cooldown

# Check if a laser has hit this entity
func check_laser_hit(laser) -> bool:
	# Skip if we're invulnerable
	if is_invulnerable:
		return false
	
	# Check if this is an appropriate laser type to hit us
	if (self.is_in_group("player") and laser.is_player_laser) or \
	   (self.is_in_group("enemies") and not laser.is_player_laser):
		return false
	
	# Get collision shapes
	var entity_rect = get_collision_rect()
	var laser_rect = laser.get_collision_rect()
	
	# Offset to global coordinates
	entity_rect.position += global_position
	laser_rect.position += laser.global_position
	
	# Check for intersection
	return entity_rect.intersects(laser_rect)

# Get entity collision rectangle for hit detection
func get_collision_rect() -> Rect2:
	var sprite = get_node_or_null("Sprite2D")
	if sprite and sprite.texture:
		var texture_size = sprite.texture.get_size()
		# Make the collision rect a bit smaller than the sprite for better gameplay
		var scaled_size = texture_size * 0.7
		return Rect2(-scaled_size.x/2, -scaled_size.y/2, scaled_size.x, scaled_size.y)
	else:
		# Fallback collision rect if no sprite
		return Rect2(-16, -16, 32, 32)

# Set immobilized state (to be implemented by child classes)
func set_immobilized(value: bool) -> void:
	pass
