# explode_debris_component.gd
extends Component
class_name ExplodeDebrisComponent

@export var explosion_scale: float = 1.0
@export var explosion_duration_multiplier: float = 1.0
@export var explosion_radius: float = 60.0
@export var damage: float = 0.0
@export var damage_falloff: bool = true
@export var damage_groups: Array[String] = ["player", "enemies"]
@export var screen_shake: bool = true
@export var screen_shake_intensity: float = 5.0
@export var screen_shake_duration: float = 0.2
@export var spawn_fragments: bool = true
@export var fragment_count: int = 2

var sound_system = null
var explosion_scene = preload("res://scenes/explosion_debris.tscn")

var size_categories = {
	"large": { "next": "medium", "count": 2 },
	"medium": { "next": "small", "count": 2 },
	"small": { "next": "", "count": 0 }
}

func _initialize():
	sound_system = entity.get_node_or_null("/root/SoundSystem")

func explode():
	var explosion_position = entity.global_position
	
	_create_explosion_effect(explosion_position)
	
	if sound_system:
		sound_system.play_explosion(explosion_position)
	
	if damage > 0:
		_apply_explosion_damage(explosion_position)
	
	if screen_shake:
		_apply_screen_shake()
		
	if spawn_fragments and "size_category" in entity:
		_spawn_fragments(explosion_position, entity.size_category)

func _create_explosion_effect(position: Vector2):
	if explosion_scene == null:
		var explosion_scene_path = "res://scenes/explosion_debris.tscn"
		if ResourceLoader.exists(explosion_scene_path):
			explosion_scene = load(explosion_scene_path)
	
	if explosion_scene:
		var explosion = explosion_scene.instantiate()
		explosion.global_position = position
		explosion.scale = Vector2(explosion_scale, explosion_scale)
		
		if explosion.has_method("set") and "explosion_duration" in explosion:
			explosion.explosion_duration *= explosion_duration_multiplier
		
		entity.get_tree().current_scene.add_child(explosion)
	else:
		_create_fallback_explosion(position)

func _apply_explosion_damage(position: Vector2):
	var targets = []
	for group in damage_groups:
		targets.append_array(entity.get_tree().get_nodes_in_group(group))
	
	for target in targets:
		if not is_instance_valid(target) or not target.visible:
			continue
			
		var distance = position.distance_to(target.global_position)
		if distance <= explosion_radius:
			var damage_amount = damage
			
			if damage_falloff:
				var damage_factor = 1.0 - (distance / explosion_radius)
				damage_amount *= damage_factor
			
			if target.has_method("take_damage"):
				target.take_damage(damage_amount)

func _apply_screen_shake():
	var camera = null
	var player = entity.get_tree().get_first_node_in_group("player")
	
	if player and player.has_node("Camera2D"):
		camera = player.get_node("Camera2D")
	
	if camera and camera.has_method("apply_shake"):
		camera.apply_shake(screen_shake_intensity, screen_shake_duration)
	elif camera:
		var original_position = camera.position
		var tween = entity.create_tween()
		var shake_count = 5
		
		for i in range(shake_count):
			var intensity = screen_shake_intensity * (1.0 - float(i) / shake_count)
			var random_offset = Vector2(
				randf_range(-intensity, intensity),
				randf_range(-intensity, intensity)
			)
			
			tween.tween_property(
				camera, 
				"position",
				original_position + random_offset,
				screen_shake_duration / shake_count
			)
		
		tween.tween_property(camera, "position", original_position, screen_shake_duration / shake_count)

func _spawn_fragments(position: Vector2, current_size: String):
	if not size_categories.has(current_size) or size_categories[current_size].next.is_empty():
		return
	
	var next_size = size_categories[current_size].next
	var count = size_categories[current_size].count
	
	var asteroid_spawner = entity.get_node_or_null("/root/Main/AsteroidSpawner")
	if asteroid_spawner and asteroid_spawner.has_method("_spawn_fragments"):
		var base_scale = 1.0
		if "base_scale" in entity:
			base_scale = entity.base_scale
			
		asteroid_spawner._spawn_fragments(
			position,
			current_size,
			count,
			base_scale
		)

func _create_fallback_explosion(position: Vector2):
	var explosion = Node2D.new()
	explosion.position = position
	entity.get_tree().current_scene.add_child(explosion)
	
	var debris_particles = CPUParticles2D.new()
	debris_particles.z_index = 10
	debris_particles.amount = 50
	debris_particles.lifetime = 0.7 * explosion_duration_multiplier
	debris_particles.explosiveness = 1.0
	debris_particles.one_shot = true
	debris_particles.emitting = true
	debris_particles.direction = Vector2.ZERO
	debris_particles.spread = 180.0
	debris_particles.gravity = Vector2(0, 150)
	debris_particles.initial_velocity_min = 150.0 * explosion_scale
	debris_particles.initial_velocity_max = 250.0 * explosion_scale
	debris_particles.scale_amount_min = 2.0 * explosion_scale
	debris_particles.scale_amount_max = 4.0 * explosion_scale
	debris_particles.color = Color(0.5, 0.45, 0.4, 0.8)
	explosion.add_child(debris_particles)
	
	var dust_particles = CPUParticles2D.new()
	dust_particles.z_index = 9
	dust_particles.amount = 40
	dust_particles.lifetime = 0.9 * explosion_duration_multiplier
	dust_particles.explosiveness = 0.8
	dust_particles.one_shot = true
	dust_particles.emitting = true
	dust_particles.direction = Vector2.ZERO
	dust_particles.spread = 180.0
	dust_particles.gravity = Vector2(0, 10)
	dust_particles.initial_velocity_min = 40.0 * explosion_scale
	dust_particles.initial_velocity_max = 80.0 * explosion_scale
	dust_particles.scale_amount_min = 3.0 * explosion_scale
	dust_particles.scale_amount_max = 6.0 * explosion_scale
	dust_particles.color = Color(0.6, 0.55, 0.5, 0.6)
	explosion.add_child(dust_particles)
	
	var timer = Timer.new()
	timer.wait_time = 1.2 * explosion_duration_multiplier
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): explosion.queue_free())
	explosion.add_child(timer)
