# scripts/entities/missile_explosion.gd
extends Node2D
class_name MissileExplosion

var explosion_radius: float = 100.0
var explosion_damage: float = 30.0
var shooter: Node = null
var hit_targets: Array = []

func _ready() -> void:
	# Create explosion visuals
	_create_explosion_visual()
	
	# Play explosion sounds
	if Engine.has_singleton("AudioManager"):
		AudioManager.play_sfx("explosion_fire", global_position)
		AudioManager.play_sfx("explosion_debris", global_position)
	
	# Apply damage to nearby entities
	_apply_explosion_damage()
	
	# Remove after animation finishes
	get_tree().create_timer(1.2).timeout.connect(func(): queue_free())

func _create_explosion_visual() -> void:
	# Create solid orange circle for explosion radius
	var circle_sprite = Sprite2D.new()
	circle_sprite.name = "ExplosionCircle"
	add_child(circle_sprite)
	
	# Create a texture with solid orange color
	var img = Image.create(100, 100, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))  # Start transparent
	
	# Fill with solid color
	var orange_color = Color(1.0, 0.5, 0.0, 0.3)  # Semi-transparent orange
	for x in range(100):
		for y in range(100):
			var dx = x - 50
			var dy = y - 50
			var dist_squared = dx*dx + dy*dy
			
			if dist_squared <= 2500:  # 50^2 = 2500
				img.set_pixel(x, y, orange_color)
	
	# Create texture and apply to sprite
	var texture = ImageTexture.create_from_image(img)
	circle_sprite.texture = texture
	
	# Scale to match explosion radius
	circle_sprite.scale = Vector2(explosion_radius / 50.0, explosion_radius / 50.0)
	
	# Add fade-out animation
	var tween = create_tween()
	tween.tween_property(circle_sprite, "modulate:a", 0.0, 1.0)

func _apply_explosion_damage() -> void:
	# Find all potential targets
	var targets = []
	
	# Try to get all nodes in damageable group first
	targets = get_tree().get_nodes_in_group("damageable")
	
	# If no damageable group, try to find other common groups
	if targets.is_empty():
		targets = get_tree().get_nodes_in_group("enemies")
		targets.append_array(get_tree().get_nodes_in_group("asteroids"))
		targets.append_array(get_tree().get_nodes_in_group("player"))
	
	# If still empty, try to find anything with a health component in the current scene
	if targets.is_empty():
		var scene_nodes = get_tree().current_scene.get_children()
		for node in scene_nodes:
			if node.get_node_or_null("HealthComponent"):
				targets.append(node)
	
	# Apply damage to all valid targets within explosion radius
	for target in targets:
		# Skip invalid targets
		if not is_instance_valid(target) or target == shooter or hit_targets.has(target):
			continue
		
		# Check if within explosion radius
		var distance = global_position.distance_to(target.global_position)
		if distance <= explosion_radius:
			# Get health component
			var health = target.get_node_or_null("HealthComponent")
			if health and health.has_method("apply_damage"):
				# Calculate damage with distance falloff
				var falloff = 1.0 - (distance / explosion_radius)
				falloff = max(0.1, falloff)  # Minimum 10% damage at edge
				var damage = explosion_damage * falloff
				
				# Apply damage
				health.apply_damage(damage, "explosion", shooter)
				hit_targets.append(target)
