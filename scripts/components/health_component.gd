extends Component
class_name HealthComponent

signal damaged(amount, type, source)
signal healed(amount, source)
signal died
signal revived
signal health_changed(current, maximum)

# Health configuration
@export var max_health: float = 100.0
@export var current_health: float = 100.0
@export var shield_damage_reduction: float = 0.0
@export var critical_health_threshold: float = 0.3  # Percentage of max health
@export var destroyed_on_death: bool = false
@export var invulnerable: bool = false

# Damage types that this component is immune to
@export var immune_damage_types: Array[String] = []

# Damage type effectiveness (1.0 = normal, <1.0 = resistance, >1.0 = weakness)
@export var damage_type_modifiers: Dictionary = {}

# Internal state
var is_dead: bool = false
var owner_entity = null
var _shield_component = null

# Effect variables
var _hit_flash_timer: float = 0.0
var _invulnerability_timer: float = 0.0
var _is_hit_flashing: bool = false
const HIT_FLASH_DURATION: float = 0.1

# Audio manager reference
var _audio_manager = null
var _last_hit_time: float = 0.0
const MIN_HIT_SOUND_INTERVAL: float = 0.2  # Minimum time between hit sounds

func _ready() -> void:
	super._ready()
	
	# Get owner entity
	owner_entity = _find_owner_entity()
	
	# Get audio manager
	_audio_manager = get_node_or_null("/root/AudioManager")
	
	# Find shield component (if exists)
	_shield_component = get_node_or_null("../ShieldComponent")
	if not _shield_component and owner_entity:
		_shield_component = owner_entity.get_node_or_null("ShieldComponent")
	
	# Connect to shield component if found
	if _shield_component and _shield_component.has_signal("shield_depleted"):
		if not _shield_component.is_connected("shield_depleted", _on_shield_depleted):
			_shield_component.connect("shield_depleted", _on_shield_depleted)
	
	# Initialize health
	if current_health <= 0:
		current_health = max_health
	
	# Signal initial health
	health_changed.emit(current_health, max_health)

func _process(delta: float) -> void:
	# Update hit flash effect
	if _is_hit_flashing:
		_hit_flash_timer -= delta
		if _hit_flash_timer <= 0:
			_is_hit_flashing = false
			_reset_hit_flash()
	
	# Update invulnerability timer
	if _invulnerability_timer > 0:
		_invulnerability_timer -= delta
		if _invulnerability_timer <= 0:
			invulnerable = false

# Apply damage to this component
func apply_damage(amount: float, damage_type: String = "", source = null) -> float:
	if not enabled or is_dead or invulnerable:
		return 0.0
	
	# Don't allow negative damage
	if amount <= 0:
		return 0.0
	
	# Check damage immunity
	if damage_type in immune_damage_types:
		return 0.0
	
	# Apply damage type modifier
	var final_amount = amount
	if damage_type in damage_type_modifiers:
		final_amount *= damage_type_modifiers[damage_type]
	
	# Apply shield damage reduction if shield available
	var shield_remaining = 0.0
	if _shield_component and _shield_component.enabled:
		shield_remaining = _shield_component.get_current_shield()
		
		if shield_remaining > 0:
			# Reduce damage based on shield
			var damage_reduction = shield_damage_reduction
			
			# If shield component has a method for damage reduction, use that
			if _shield_component.has_method("get_damage_reduction"):
				damage_reduction = _shield_component.get_damage_reduction()
			
			final_amount *= (1.0 - damage_reduction)
			
			# Apply remaining damage to shield
			_shield_component.apply_damage(amount, damage_type, source)
	
	# Reduce health
	var prev_health = current_health
	current_health -= final_amount
	
	# Ensure health doesn't go below zero
	if current_health < 0:
		current_health = 0
	
	# Emit signals
	health_changed.emit(current_health, max_health)
	damaged.emit(final_amount, damage_type, source)
	
	# Play hit effects
	_play_hit_effects(final_amount, damage_type)
	
	# Check for death
	if current_health <= 0 and not is_dead:
		_die()
	
	# Return actual damage dealt
	return prev_health - current_health

# Heal this component
func heal(amount: float, source = null) -> float:
	if not enabled or amount <= 0:
		return 0.0
	
	# If dead, revive first
	if is_dead:
		revive()
	
	# Apply healing
	var prev_health = current_health
	current_health += amount
	
	# Ensure health doesn't exceed maximum
	if current_health > max_health:
		current_health = max_health
	
	# Emit signals
	health_changed.emit(current_health, max_health)
	healed.emit(amount, source)
	
	# Return actual healing done
	return current_health - prev_health

# Set health to a specific value
func set_health(value: float) -> void:
	if value <= 0:
		if not is_dead:
			current_health = 0
			_die()
	else:
		if is_dead:
			revive()
		
		var prev_health = current_health
		current_health = min(value, max_health)
		
		# Emit signals
		health_changed.emit(current_health, max_health)
		
		# Emit appropriate signals based on health change
		if current_health > prev_health:
			healed.emit(current_health - prev_health, null)
		elif current_health < prev_health:
			damaged.emit(prev_health - current_health, "", null)
	
# Kill the entity
func kill() -> void:
	if is_dead:
		return
	
	current_health = 0
	health_changed.emit(current_health, max_health)
	_die()

# Revive the entity
func revive() -> void:
	if not is_dead:
		return
	
	is_dead = false
	
	# Set minimum health
	if current_health <= 0:
		current_health = max_health * 0.1  # Revive with 10% health
	
	# Emit signals
	revived.emit()
	health_changed.emit(current_health, max_health)

# Make entity temporarily invulnerable
func set_invulnerable(duration: float = 2.0) -> void:
	invulnerable = true
	_invulnerability_timer = max(duration, _invulnerability_timer)

# Check if health is at critical level
func is_critical() -> bool:
	return current_health <= (max_health * critical_health_threshold)

# Get health as a percentage
func get_health_percent() -> float:
	if max_health <= 0:
		return 0.0
	return current_health / max_health

# INTERNAL METHODS

# Find the owner entity (ship or character)
func _find_owner_entity() -> Node:
	var parent = get_parent()
	# Search up the tree for a RigidBody2D, character, or node in the player or ships group
	while parent and not parent is RigidBody2D and not parent.is_in_group("player") and not parent.is_in_group("ships") and not parent.is_in_group("characters"):
		parent = parent.get_parent()
	
	return parent

# Handle death
func _die() -> void:
	if is_dead:
		return
	
	is_dead = true
	
	# Emit died signal
	died.emit()
	
	# Play death effects
	_play_death_effects()
	
	# Destroy owner if option is enabled
	if destroyed_on_death and owner_entity and is_instance_valid(owner_entity):
		# Allow death animation to play first
		get_tree().create_timer(0.1).timeout.connect(func(): owner_entity.queue_free())

# Play hit effects
func _play_hit_effects(amount: float, damage_type: String) -> void:
	# Play hit flash
	_is_hit_flashing = true
	_hit_flash_timer = HIT_FLASH_DURATION
	_apply_hit_flash()
	
	# Play hit sound
	_play_hit_sound(damage_type)
	
	# Create hit particle effect
	_create_hit_particles(amount)

# Apply hit flash effect
func _apply_hit_flash() -> void:
	if not owner_entity:
		return
	
	# Find sprites to flash
	var sprites = []
	
	# Try to get sprite from owner entity
	var sprite = owner_entity.get_node_or_null("Sprite2D")
	if sprite:
		sprites.append(sprite)
	else:
		# Try to find all sprite children
		for child in owner_entity.get_children():
			if child is Sprite2D or child is AnimatedSprite2D:
				sprites.append(child)
	
	# Apply flash effect to all found sprites
	for sprite_node in sprites:
		sprite_node.modulate = Color(1.5, 1.5, 1.5, 1.0)  # White flash

# Reset hit flash effect
func _reset_hit_flash() -> void:
	if not owner_entity:
		return
	
	# Find sprites to reset
	var sprites = []
	
	# Try to get sprite from owner entity
	var sprite = owner_entity.get_node_or_null("Sprite2D")
	if sprite:
		sprites.append(sprite)
	else:
		# Try to find all sprite children
		for child in owner_entity.get_children():
			if child is Sprite2D or child is AnimatedSprite2D:
				sprites.append(child)
	
	# Reset flash effect on all found sprites
	for sprite_node in sprites:
		sprite_node.modulate = Color(1.0, 1.0, 1.0, 1.0)  # Reset to normal

# Play hit sound
func _play_hit_sound(damage_type: String) -> void:
	if not _audio_manager:
		return
	
	# Limit how often hit sounds can play
	var current_time = Time.get_ticks_msec() / 1000.0
	if current_time - _last_hit_time < MIN_HIT_SOUND_INTERVAL:
		return
	
	_last_hit_time = current_time
	
	# Determine sound name based on damage type
	var sound_name = "hit"
	if damage_type == "laser":
		sound_name = "hit_laser"
	elif damage_type == "missile":
		sound_name = "hit_missile"
	elif damage_type == "collision":
		sound_name = "hit_collision"
	
	# Play the sound at owner's position
	if owner_entity and "global_position" in owner_entity:
		_audio_manager.play_sfx(sound_name, owner_entity.global_position)
	else:
		_audio_manager.play_sfx(sound_name)

# Create hit particles
func _create_hit_particles(amount: float) -> void:
	# Skip if no owner or no effect manager
	if not owner_entity or not has_node("/root/EffectPoolManager"):
		return
	
	# Determine effect type and size based on damage amount
	var effect_size = "small"
	if amount > max_health * 0.1:
		effect_size = "medium"
	
	if amount > max_health * 0.25:
		effect_size = "large"
	
	# Get the position
	var effect_position = Vector2.ZERO
	if "global_position" in owner_entity:
		effect_position = owner_entity.global_position
	
	# Create effect
	var effect_manager = get_node("/root/EffectPoolManager")
	effect_manager.play_effect("impact", effect_position, owner_entity.rotation, 1.0)

# Play death effects
func _play_death_effects() -> void:
	if not owner_entity:
		return
	
	# Play death sound
	if _audio_manager:
		var position = Vector2.ZERO
		if "global_position" in owner_entity:
			position = owner_entity.global_position
		
		_audio_manager.play_sfx("explosion", position)
	
	# Create explosion effect
	if has_node("/root/EffectPoolManager") and "global_position" in owner_entity:
		var effect_manager = get_node("/root/EffectPoolManager")
		effect_manager.explosion(owner_entity.global_position, "medium")
	else:
		# Fallback to player's own death effect if available
		if owner_entity.has_method("play_death_effect"):
			owner_entity.play_death_effect()

# Handle shield depletion
func _on_shield_depleted() -> void:
	# Play shield depletion effect
	if _audio_manager:
		var position = Vector2.ZERO
		if owner_entity and "global_position" in owner_entity:
			position = owner_entity.global_position
		
		_audio_manager.play_sfx("shield_down", position)
