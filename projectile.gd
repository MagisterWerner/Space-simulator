# projectile.gd
extends Area2D
class_name Projectile

signal hit_target(target)

@export var speed: float = 500.0
@export var damage: float = 10.0
@export var lifespan: float = 2.0
@export var pierce_targets: bool = false
@export var pierce_count: int = 0  # 0 means no piercing, > 0 is number of targets that can be pierced
@export var impact_effect_scene: PackedScene

var velocity: Vector2 = Vector2.ZERO
var lifetime: float = 0.0
var shooter: Node = null
var hit_targets: Array = []

func _ready() -> void:
	# Calculate velocity based on rotation
	velocity = Vector2(speed, 0).rotated(rotation)
	
	# Connect to body entered signal
	body_entered.connect(_on_body_entered)
	
	# Set up a timer to destroy the projectile after lifespan
	lifetime = 0.0

func _process(delta: float) -> void:
	# Move the projectile
	position += velocity * delta
	
	# Update lifetime and destroy if expired
	lifetime += delta
	if lifetime >= lifespan:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	# Ignore collisions with the shooter
	if body == shooter or hit_targets.has(body):
		return
	
	# Check if the body has a health component
	var health = body.get_node_or_null("HealthComponent") as HealthComponent
	if health:
		# Deal damage
		health.apply_damage(damage, "projectile", shooter)
		hit_target.emit(body)
		hit_targets.append(body)
	
	# Spawn impact effect if provided
	if impact_effect_scene:
		var impact = impact_effect_scene.instantiate()
		get_tree().current_scene.add_child(impact)
		impact.global_position = global_position
	
	# Handle piercing
	if pierce_targets:
		# If pierce_count is > 0, decrease it by 1
		if pierce_count > 0:
			pierce_count -= 1
			if pierce_count <= 0:
				queue_free()
		# If pierce_count is 0 or negative, it has unlimited piercing
	else:
		# No piercing, destroy projectile
		queue_free()

func set_damage(value: float) -> void:
	damage = value

func set_speed(value: float) -> void:
	speed = value
	if is_inside_tree():  # If the node is already in the tree, update the velocity
		velocity = Vector2(speed, 0).rotated(rotation)

func set_lifespan(value: float) -> void:
	lifespan = value

func set_shooter(node: Node) -> void:
	shooter = node

func set_piercing(value: bool, count: int = 0) -> void:
	pierce_targets = value
	pierce_count = count
