# combat_component.gd
extends Component
class_name CombatComponent

signal weapon_fired(position, direction)
signal weapon_changed(new_weapon)
signal energy_depleted()

var resource_component: Node = null
var current_weapon_strategy: WeaponStrategy = null
var weapon_strategies: Dictionary = {}
var current_cooldown: float = 0.0
var is_charging: bool = false

@export var is_player_weapon: bool = false
@export var default_damage: float = 10.0
@export var default_cooldown: float = 0.5
@export var default_range: float = 300.0

func _initialize() -> void:
	resource_component = entity.get_node_or_null("ResourceComponent")
	
	if not current_weapon_strategy:
		add_weapon("StandardLaser", StandardLaser.new())
		set_weapon("StandardLaser")

func _process(delta: float) -> void:
	current_cooldown = max(0, current_cooldown - delta)
	if current_weapon_strategy:
		current_weapon_strategy.process(delta)

func set_weapon(weapon_name: String) -> bool:
	if weapon_name not in weapon_strategies:
		return false
	
	if current_weapon_strategy and current_weapon_strategy.weapon_name == weapon_name:
		return true
	
	current_weapon_strategy = weapon_strategies[weapon_name]
	emit_signal("weapon_changed", current_weapon_strategy)
	return true

func add_weapon(weapon_name: String, strategy: WeaponStrategy) -> void:
	weapon_strategies[weapon_name] = strategy

func remove_weapon(weapon_name: String) -> bool:
	if weapon_name not in weapon_strategies:
		return false
	
	var weapon = weapon_strategies[weapon_name]
	weapon_strategies.erase(weapon_name)
	
	if current_weapon_strategy == weapon:
		current_weapon_strategy = weapon_strategies.values()[0] if weapon_strategies else null
		emit_signal("weapon_changed", current_weapon_strategy)
	
	return true

func get_available_weapons() -> Array:
	return weapon_strategies.keys()

func fire(direction: Vector2) -> bool:
	if not can_fire():
		return false
	
	if is_charging:
		return release_charge()
	
	if resource_component and not resource_component.use_resource("energy", current_weapon_strategy.energy_cost):
		emit_signal("energy_depleted")
		return false
	
	var projectiles = current_weapon_strategy.fire(entity, entity.global_position, direction)
	current_cooldown = current_weapon_strategy.cooldown
	
	if projectiles:
		emit_signal("weapon_fired", entity.global_position, direction)
		return true
	
	return false

func can_fire() -> bool:
	return current_cooldown <= 0 and current_weapon_strategy != null

func start_charging() -> bool:
	if not can_fire() or not current_weapon_strategy or not current_weapon_strategy.has_method("charge"):
		return false
	
	is_charging = true
	return true

func update_charge(delta: float) -> float:
	return current_weapon_strategy.charge(delta) if is_charging else 0.0

func release_charge() -> bool:
	if not is_charging or not current_weapon_strategy or not current_weapon_strategy.has_method("release_charge"):
		is_charging = false
		return false
	
	var charge_significant = current_weapon_strategy.release_charge()
	is_charging = false
	
	return charge_significant and fire(get_facing_direction())

func get_facing_direction() -> Vector2:
	var movement = entity.get_node_or_null("MovementComponent")
	if movement and movement.has_method("get_facing_direction"):
		return movement.facing_direction
	
	var sprite = entity.get_node_or_null("Sprite2D")
	return Vector2.RIGHT.rotated(sprite.rotation) if sprite else Vector2.RIGHT

func get_current_weapon_name() -> String:
	return current_weapon_strategy.weapon_name if current_weapon_strategy else "None"

func check_collision(laser) -> bool:
	if not entity.has_method("get_collision_rect"):
		return false
	
	var collision_rect = entity.get_collision_rect()
	var laser_rect = laser.get_collision_rect()
	
	collision_rect.position += entity.global_position
	laser_rect.position += laser.global_position
	
	return (laser.is_player_laser != is_player_weapon) and collision_rect.intersects(laser_rect)
