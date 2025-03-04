# explode_fire_component.gd
extends Component
class_name ExplodeFireComponent

@export var explosion_scale: float = 1.0
@export var explosion_duration_multiplier: float = 1.0
@export var explosion_radius: float = 60.0
@export var damage: float = 0.0
@export var damage_falloff: bool = true
@export var damage_groups: Array[String] = []
@export var screen_shake: bool = true
@export var screen_shake_intensity: float = 5.0
@export var screen_shake_duration: float = 0.2

var sound_system = null
var explosion_scene = preload("res://scenes/explosion_fire.tscn")

func _initialize():
	sound_system = entity.get_node_or_null("/root/SoundSystem")
	
	if entity.is_in_group("player"):
		damage_groups = ["enemies", "asteroids"]
	elif entity.is_in_group("enemies"):
		damage_groups = ["player"]
	elif entity.is_in_group("missiles"):
		var is_player_missile = "is_player_missile" in entity and entity.is_player_missile
		damage_groups = ["enemies", "asteroids"] if is_player_missile else ["player"]

func explode():
	var explosion_position = entity.global_position
	
	_create_explosion_effect(explosion_position)
	
	if sound_system:
		sound_system.play_explosion(explosion_position)
	
	if damage > 0:
		_apply_explosion_damage(explosion_position)
	
	if screen_shake:
		_apply_screen_shake()

func _create_explosion_effect(position: Vector2):
	if explosion_scene == null:
		var explosion_scene_path = "res://scenes/explosion_fire.tscn"
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

func _create_fallback_explosion(position: Vector2):
	var explosion = Node2D.new()
	explosion.position = position
	entity.get_tree().current_scene.add_child(explosion)
	
	var fire_particles = CPUParticles2D.new()
	fire_particles.z_index = 10
	fire_particles.amount = 40
	fire_particles.lifetime = 0.6 * explosion_duration_multiplier
	fire_particles.explosiveness = 1.0
	fire_particles.one_shot = true
	fire_particles.emitting = true
	fire_particles.direction = Vector2.ZERO
	fire_particles.spread = 180.0
	fire_particles.gravity = Vector2(0, -20)
	fire_particles.initial_velocity_min = 100.0 * explosion_scale
	fire_particles.initial_velocity_max = 200.0 * explosion_scale
	fire_particles.scale_amount_min = 3.0 * explosion_scale
	fire_particles.scale_amount_max = 6.0 * explosion_scale
	fire_particles.color = Color(1.0, 0.5, 0.2, 0.8)
	explosion.add_child(fire_particles)
	
	var smoke_particles = CPUParticles2D.new()
	smoke_particles.z_index = 9
	smoke_particles.amount = 30
	smoke_particles.lifetime = 0.8 * explosion_duration_multiplier
	smoke_particles.explosiveness = 0.8
	smoke_particles.one_shot = true
	smoke_particles.emitting = true
	smoke_particles.direction = Vector2(0, -1)
	smoke_particles.spread = 90.0
	smoke_particles.gravity = Vector2(0, -10)
	smoke_particles.initial_velocity_min = 50.0 * explosion_scale
	smoke_particles.initial_velocity_max = 100.0 * explosion_scale
	smoke_particles.scale_amount_min = 4.0 * explosion_scale
	smoke_particles.scale_amount_max = 8.0 * explosion_scale
	smoke_particles.color = Color(0.2, 0.2, 0.2, 0.6)
	explosion.add_child(smoke_particles)
	
	var timer = Timer.new()
	timer.wait_time = 1.0 * explosion_duration_multiplier
	timer.one_shot = true
	timer.autostart = true
	timer.timeout.connect(func(): explosion.queue_free())
	explosion.add_child(timer)
