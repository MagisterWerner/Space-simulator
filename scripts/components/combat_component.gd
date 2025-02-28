extends Component
class_name CombatComponent

signal weapon_fired(position, direction)
signal weapon_changed(new_weapon)
signal energy_depleted()

# Dependencies
var resource_component = null

# Weapon system variables
var current_weapon_strategy: WeaponStrategy
var weapon_strategies = {}  # Dictionary of all available weapons
var current_cooldown: float = 0.0
var is_charging: bool = false

# Default properties - used as fallbacks
@export var is_player_weapon: bool = false
@export var default_damage: float = 10.0
@export var default_cooldown: float = 0.5
@export var default_range: float = 300.0

func _initialize():
	# Get dependency on resource component if it exists
	resource_component = entity.get_node_or_null("ResourceComponent")
	
	# Initialize with the standard laser if no weapon is set
	if not current_weapon_strategy:
		add_weapon("StandardLaser", StandardLaser.new())
		set_weapon("StandardLaser")

func _process(delta):
	# Update cooldown
	if current_cooldown > 0:
		current_cooldown -= delta
	
	# Process current weapon strategy
	if current_weapon_strategy:
		current_weapon_strategy.process(delta)

func set_weapon(weapon_name: String) -> bool:
	if weapon_strategies.has(weapon_name):
		if current_weapon_strategy and current_weapon_strategy.weapon_name == weapon_name:
			return true  # Already using this weapon
			
		current_weapon_strategy = weapon_strategies[weapon_name]
		emit_signal("weapon_changed", current_weapon_strategy)
		
		# Create charge visual if this is a chargeable weapon
		if current_weapon_strategy is ChargeBeam:
			current_weapon_strategy.create_charge_visual(entity)
			
		return true
	return false

func add_weapon(weapon_name: String, strategy: WeaponStrategy) -> void:
	weapon_strategies[weapon_name] = strategy

func remove_weapon(weapon_name: String) -> bool:
	if weapon_strategies.has(weapon_name):
		var weapon = weapon_strategies[weapon_name]
		weapon_strategies.erase(weapon_name)
		
		# If we removed the current weapon, switch to another one
		if current_weapon_strategy == weapon:
			if weapon_strategies.size() > 0:
				current_weapon_strategy = weapon_strategies.values()[0]
				emit_signal("weapon_changed", current_weapon_strategy)
			else:
				current_weapon_strategy = null
		
		return true
	return false

func get_available_weapons() -> Array:
	return weapon_strategies.keys()

func fire(direction: Vector2) -> bool:
	# Check if we can fire
	if not can_fire() or not current_weapon_strategy:
		return false
	
	# Check if we need to release a charged weapon
	if is_charging:
		return release_charge()
	
	# Check if we have enough energy
	if resource_component and resource_component.has_method("use_resource"):
		var energy_cost = current_weapon_strategy.energy_cost
		if not resource_component.use_resource("energy", energy_cost):
			emit_signal("energy_depleted")
			return false
	
	# Use the weapon strategy to fire
	var projectiles = current_weapon_strategy.fire(entity, entity.global_position, direction)
	
	# Set cooldown
	current_cooldown = current_weapon_strategy.cooldown
	
	# Emit signal
	if projectiles.size() > 0:
		emit_signal("weapon_fired", entity.global_position, direction)
		return true
	
	return false

func can_fire() -> bool:
	return current_cooldown <= 0 and current_weapon_strategy != null

func start_charging() -> bool:
	if not can_fire() or not current_weapon_strategy:
		return false
		
	# Only allow charging for weapons that support it
	if current_weapon_strategy.has_method("charge"):
		is_charging = true
		return true
		
	return false

func update_charge(delta: float) -> float:
	if is_charging and current_weapon_strategy and current_weapon_strategy.has_method("charge"):
		return current_weapon_strategy.charge(delta)
	return 0.0

func release_charge() -> bool:
	if not is_charging or not current_weapon_strategy or not current_weapon_strategy.has_method("release_charge"):
		is_charging = false
		return false
	
	var charge_significant = current_weapon_strategy.release_charge()
	is_charging = false
	
	if charge_significant:
		# Fire the charged weapon
		return fire(get_facing_direction())
	
	return false

func get_facing_direction() -> Vector2:
	# Try to get facing direction from movement component
	var movement = entity.get_node_or_null("MovementComponent")
	if movement and movement.has_method("get_facing_direction"):
		return movement.facing_direction
	
	# If entity has a Sprite2D, use its rotation
	var sprite = entity.get_node_or_null("Sprite2D")
	if sprite:
		return Vector2.RIGHT.rotated(sprite.rotation)
	
	# Default to right direction
	return Vector2.RIGHT

func get_current_weapon_name() -> String:
	if current_weapon_strategy:
		return current_weapon_strategy.weapon_name
	return "None"

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
