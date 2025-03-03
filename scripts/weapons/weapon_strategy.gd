class_name WeaponStrategy
extends Resource

# Properties all weapons should have
@export var weapon_name: String = "Base Weapon"
@export var cooldown: float = 0.5
@export var damage: float = 10.0
@export var energy_cost: float = 5.0
@export var projectile_speed: float = 1000.0
@export var range: float = 500.0
@export var icon: Texture2D

# Virtual function to be implemented by each weapon strategy
func fire(_entity, _spawn_position: Vector2, _direction: Vector2) -> Array:
	# Return an array of projectiles created
	return []
	
# Virtual function for any weapon update logic
func process(_delta: float) -> void:
	pass
	
# Virtual function for weapon charge mechanics
func charge(_amount: float) -> float:
	# Return charge progress (0-1)
	return 0.0
	
# Virtual function for releasing a charged weapon
func release_charge() -> bool:
	# Return whether the charge was successfully released
	return false
	
# Get specific properties for this weapon type
func get_properties() -> Dictionary:
	return {
		"name": weapon_name,
		"cooldown": cooldown,
		"damage": damage,
		"energy_cost": energy_cost,
		"projectile_speed": projectile_speed,
		"range": range
	}
