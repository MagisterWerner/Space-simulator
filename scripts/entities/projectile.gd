# scripts/entities/projectile.gd
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
	# Pre-calculate velocity once
	velocity = Vector2(speed, 0).rotated(rotation)
	body_entered.connect(_on_body_entered)

func _process(delta: float) -> void:
	# Apply movement
	position += velocity * delta
	
	# Update lifetime - queue_free at end
	lifetime += delta
	if lifetime >= lifespan:
		queue_free()

func _on_body_entered(body: Node2D) -> void:
	# Skip already hit bodies and shooter
	if body == shooter or hit_targets.has(body):
		return
	
	# Get health component efficiently
	var health = body.get_node_or_null("HealthComponent") as HealthComponent
	if health:
		health.apply_damage(damage, "projectile", shooter)
		hit_target.emit(body)
		hit_targets.append(body)
	
	# Spawn impact effect only if needed
	if impact_effect_scene:
		var impact = impact_effect_scene.instantiate()
		get_tree().current_scene.add_child(impact)
		impact.global_position = global_position
	
	# Handle piercing logic with early exits
	if not pierce_targets:
		queue_free()
		return
		
	# Limited piercing
	if pierce_count > 0:
		pierce_count -= 1
		if pierce_count <= 0:
			queue_free()
	# Else unlimited piercing - do nothing

# More efficient property setters
func set_damage(value: float) -> void:
	damage = value

func set_speed(value: float) -> void:
	speed = value
	# Only recalculate velocity if node is in tree
	if is_inside_tree():
		velocity = Vector2(speed, 0).rotated(rotation)

func set_lifespan(value: float) -> void:
	lifespan = value

func set_shooter(node: Node) -> void:
	shooter = node

func set_piercing(value: bool, count: int = 0) -> void:
	pierce_targets = value
	pierce_count = count
