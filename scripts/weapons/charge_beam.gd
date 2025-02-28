class_name ChargeBeam
extends WeaponStrategy

# Charge beam specific properties
@export var min_damage: float = 5.0
@export var max_damage: float = 40.0
@export var min_width: float = 4.0
@export var max_width: float = 12.0
@export var charge_time: float = 2.0
@export var beam_color: Color = Color(1.0, 0.5, 0.0)  # Orange

var current_charge: float = 0.0
var is_charging: bool = false
var charge_visual: Node2D = null

func _init():
	weapon_name = "Charge Beam"
	cooldown = 0.2
	damage = min_damage
	energy_cost = 15.0
	projectile_speed = 1200.0
	range = 1000.0

func process(delta: float) -> void:
	# Reset charge if not charging
	if not is_charging:
		current_charge = 0.0
		
	# Update charge visual if it exists
	if charge_visual:
		charge_visual.queue_redraw()

func charge(amount: float) -> float:
	is_charging = true
	
	# Increase charge
	current_charge += amount
	current_charge = min(current_charge, charge_time)
	
	# Return charge progress (0-1)
	return current_charge / charge_time

func release_charge() -> bool:
	is_charging = false
	
	# Return whether the charge was significant
	return current_charge > 0.1

func fire(entity, spawn_position: Vector2, direction: Vector2) -> Array:
	# Calculate damage and width based on charge
	var charge_percent = current_charge / charge_time
	var actual_damage = lerp(min_damage, max_damage, charge_percent)
	var beam_width = lerp(min_width, max_width, charge_percent)
	
	# Create custom laser projectile
	var laser_scene = load("res://laser.tscn")
	var laser = laser_scene.instantiate()
	
	# Set position
	var spawn_offset = direction * 30
	laser.global_position = spawn_position + spawn_offset
	
	# Configure the laser
	laser.direction = direction
	laser.rotation = direction.angle()
	laser.is_player_laser = entity.is_in_group("player")
	laser.damage = actual_damage
	laser.speed = projectile_speed
	
	# Customize appearance for charge beam
	if laser.has_node("Sprite2D"):
		var sprite = laser.get_node("Sprite2D")
		sprite.modulate = beam_color
		
		# Scale the width but maintain length proportions
		var original_scale = sprite.scale
		sprite.scale.y = beam_width / 4.0  # Assuming default width is 4
	
	# Add to scene
	entity.get_tree().current_scene.add_child(laser)
	
	# Reset charge after firing
	current_charge = 0.0
	
	return [laser]

# Create a visual indicator for charging
func create_charge_visual(entity) -> Node2D:
	# Remove existing visual if any
	if charge_visual and charge_visual.is_inside_tree():
		charge_visual.queue_free()
	
	# Create new charge visual
	charge_visual = Node2D.new()
	charge_visual.name = "ChargeVisual"
	charge_visual.z_index = 100
	
	# Set draw function
	charge_visual.set_script(load("res://scripts/weapons/charge_visual.gd"))
	charge_visual.charge_beam = self
	
	# Add to entity
	entity.add_child(charge_visual)
	
	return charge_visual
