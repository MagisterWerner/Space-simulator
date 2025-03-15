extends WeaponComponent
class_name MissileLauncherComponent

# Missile-specific properties
@export var tracking_range: float = 600.0
@export var tracking_speed: float = 3.0
@export var explosion_radius: float = 50.0
@export var missile_lifetime: float = 5.0
@export var missile_color: Color = Color(0.9, 0.5, 0.1, 1.0)
@export var muzzle_offset: Vector2 = Vector2(20, 0)
@export var launch_velocity: float = 200.0

# Projectile scene
var projectile_scene = preload("res://scenes/projectiles/missile_projectile.tscn")

# Muzzle flash and sound effect
var smoke_effect: Node2D = null
var audio_player: AudioStreamPlayer2D = null

# Targeting
var target_node: Node2D = null
var _nearest_enemy_distance: float = 0.0

func _ready() -> void:
	# Call parent ready function first
	super._ready()
	
	# Set missile launcher defaults
	weapon_name = "Missile Launcher"
	damage = 25.0
	fire_rate = 1.0
	projectile_speed = 300.0
	max_ammo = 12
	current_ammo = max_ammo
	reload_time = 4.0
	
	# Connect signals
	if has_node("/root/EventManager"):
		EventManager.safe_connect("game_paused", _on_game_paused)
	
	# Set up smoke effect
	_setup_smoke_effect()
	
	# Set up audio player
	_setup_audio_player()

func _process(delta: float) -> void:
	# Call parent process
	super._process(delta)
	
	# Find nearest target if enabled
	if enabled:
		_find_nearest_target()

# Override fire method for missile-specific behavior
func fire() -> bool:
	# Call parent method to handle basic firing logic
	if not super.fire():
		return false
	
	# Create missile
	var missile = _create_missile()
	if not missile:
		return false
	
	# Play effects
	_show_smoke_effect()
	_play_fire_sound()
	
	# Emit signal
	weapon_fired.emit(missile)
	
	return true

# Create a missile
func _create_missile() -> Node2D:
	if not projectile_scene:
		push_error("MissileLauncherComponent: Projectile scene not set")
		return null
	
	# Check for ProjectilePoolManager first
	if has_node("/root/ProjectilePoolManager"):
		var projectile_manager = get_node("/root/ProjectilePoolManager")
		var direction = Vector2.RIGHT.rotated(global_rotation)
		var spawn_position = global_position + muzzle_offset.rotated(global_rotation)
		
		var missile = projectile_manager.get_projectile("missile", spawn_position, direction, owner_entity)
		
		if missile:
			# Configure missile
			_configure_missile(missile)
			return missile
	
	# Fallback to direct instantiation if no pool manager
	var missile = projectile_scene.instantiate()
	
	# Add to the scene
	get_tree().current_scene.add_child(missile)
	
	# Set properties
	missile.global_position = global_position + muzzle_offset.rotated(global_rotation)
	
	# Configure the missile
	_configure_missile(missile)
	
	return missile

# Configure missile properties
func _configure_missile(missile: Node) -> void:
	# Set direction
	var direction = Vector2.RIGHT.rotated(global_rotation)
	
	# Configure missile properties
	if missile.has_method("fire"):
		missile.fire(direction, owner_entity)
	else:
		# Basic properties if no fire method
		missile.rotation = global_rotation
		
		if "speed" in missile:
			missile.speed = projectile_speed
		
		if "damage" in missile:
			missile.damage = damage
		
		if "shooter" in missile:
			missile.shooter = owner_entity
	
	# Set tracking properties
	if missile.has_method("set_tracking"):
		missile.set_tracking(target_node, tracking_speed)
	elif "tracking_target" in missile:
		missile.tracking_target = target_node
		if "tracking_speed" in missile:
			missile.tracking_speed = tracking_speed
	
	# Set explosion properties
	if missile.has_method("set_explosion_radius"):
		missile.set_explosion_radius(explosion_radius)
	elif "explosion_radius" in missile:
		missile.explosion_radius = explosion_radius
	
	# Set lifetime
	if missile.has_method("set_lifetime"):
		missile.set_lifetime(missile_lifetime)
	elif "lifetime" in missile:
		missile.lifetime = missile_lifetime
	
	# Set color if applicable
	if "modulate" in missile:
		missile.modulate = missile_color
	
	# Apply strategy modifications
	for strategy in applied_strategies:
		if strategy.has_method("modify_projectile"):
			strategy.modify_projectile(missile)

# Find a target for the missile
func _find_nearest_target() -> void:
	# Reset target if it's no longer valid
	if target_node and (not is_instance_valid(target_node) or not target_node.is_visible_in_tree()):
		target_node = null
	
	# Use EntityManager if available
	if has_node("/root/EntityManager"):
		var entities = EntityManager.get_entities_in_radius(global_position, tracking_range, "enemy", owner_entity)
		
		if not entities.is_empty():
			# Find closest valid target
			var closest_distance = tracking_range
			var closest_entity = null
			
			for entity in entities:
				if is_instance_valid(entity) and entity.is_inside_tree():
					var distance = global_position.distance_to(entity.global_position)
					if distance < closest_distance:
						closest_distance = distance
						closest_entity = entity
			
			if closest_entity:
				target_node = closest_entity
				_nearest_enemy_distance = closest_distance
				return
	
	# Fallback: look for enemies manually
	var enemies = get_tree().get_nodes_in_group("enemies")
	if enemies.is_empty():
		target_node = null
		return
	
	var closest_distance = tracking_range
	var closest_enemy = null
	
	for enemy in enemies:
		if is_instance_valid(enemy) and enemy.is_inside_tree():
			var distance = global_position.distance_to(enemy.global_position)
			if distance < closest_distance:
				closest_distance = distance
				closest_enemy = enemy
	
	target_node = closest_enemy
	_nearest_enemy_distance = closest_distance if closest_enemy else 0.0

# Setup smoke effect
func _setup_smoke_effect() -> void:
	# Check if we already have a smoke effect
	smoke_effect = get_node_or_null("SmokeEffect")
	
	if not smoke_effect:
		# Create a simple smoke effect
		smoke_effect = CPUParticles2D.new()
		smoke_effect.name = "SmokeEffect"
		add_child(smoke_effect)
		
		# Configure smoke particles
		smoke_effect.emitting = false
		smoke_effect.one_shot = true
		smoke_effect.explosiveness = 0.8
		smoke_effect.lifetime = 0.8
		smoke_effect.amount = 10
		smoke_effect.direction = Vector2(-1, 0)  # Emit backwards
		smoke_effect.spread = 30.0
		smoke_effect.gravity = Vector2(0, -10)
		smoke_effect.initial_velocity_min = 20.0
		smoke_effect.initial_velocity_max = 40.0
		smoke_effect.scale_amount_min = 2.0
		smoke_effect.scale_amount_max = 4.0
		
		# Set smoke color
		var gradient = Gradient.new()
		gradient.add_point(0.0, Color(0.8, 0.8, 0.8, 0.8))
		gradient.add_point(1.0, Color(0.5, 0.5, 0.5, 0.0))
		smoke_effect.color_ramp = gradient
		
		# Position the smoke effect
		smoke_effect.position = muzzle_offset

# Setup audio player
func _setup_audio_player() -> void:
	# Check if we already have an audio player
	audio_player = get_node_or_null("AudioPlayer")
	
	if not audio_player:
		# Create audio player
		audio_player = AudioStreamPlayer2D.new()
		audio_player.name = "AudioPlayer"
		audio_player.bus = "SFX"
		
		# Try to load a sound
		var fire_sound = load("res://assets/audio/missile.wav")
		if fire_sound:
			audio_player.stream = fire_sound
		
		add_child(audio_player)

# Show smoke effect
func _show_smoke_effect() -> void:
	if not smoke_effect:
		return
	
	# Restart the smoke emission
	smoke_effect.restart()

# Play fire sound
func _play_fire_sound() -> void:
	# Use AudioManager if available
	if has_node("/root/AudioManager"):
		AudioManager.play_sfx("missile", global_position)
	elif audio_player:
		audio_player.play()

# Event handlers
func _on_game_paused() -> void:
	# Pause processing when game is paused
	set_process(false)

# Get distance to nearest target (for HUD display)
func get_target_distance() -> float:
	return _nearest_enemy_distance

# Check if we have a valid target
func has_target() -> bool:
	return target_node != null and is_instance_valid(target_node)

# Get target position if any
func get_target_position() -> Vector2:
	if target_node and is_instance_valid(target_node):
		return target_node.global_position
	return Vector2.ZERO
