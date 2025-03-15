extends WeaponComponent
class_name LaserWeaponComponent

# Additional laser-specific properties
@export var projectile_color: Color = Color(1.0, 0.2, 0.2, 1.0)
@export var muzzle_offset: Vector2 = Vector2(20, 0)

# Projectile scene
var projectile_scene = preload("res://scenes/projectiles/laser_projectile.tscn")

# Muzzle flash and sound effect
var muzzle_flash: Node2D = null
var audio_player: AudioStreamPlayer2D = null

func _ready() -> void:
	# Call parent ready function first
	super._ready()
	
	# Connect signals
	if has_node("/root/EventManager"):
		EventManager.safe_connect("game_paused", _on_game_paused)
	
	# Set up muzzle flash
	_setup_muzzle_flash()
	
	# Set up audio player
	_setup_audio_player()
	
	# Set default laser weapon properties
	weapon_name = "Laser"
	damage = 10.0
	fire_rate = 5.0
	projectile_speed = 800.0

# Override fire method for laser-specific behavior
func fire() -> bool:
	# Call parent method to handle basic firing logic
	if not super.fire():
		return false
	
	# Create projectile
	var projectile = _create_projectile()
	if not projectile:
		return false
	
	# Play effects
	_show_muzzle_flash()
	_play_fire_sound()
	
	# Emit signal
	weapon_fired.emit(projectile)
	
	return true

# Create a projectile
func _create_projectile() -> Node2D:
	if not projectile_scene:
		push_error("LaserWeaponComponent: Projectile scene not set")
		return null
	
	# Check for ProjectilePoolManager first
	if has_node("/root/ProjectilePoolManager"):
		var projectile_manager = get_node("/root/ProjectilePoolManager")
		var direction = Vector2.RIGHT.rotated(global_rotation)
		var spawn_position = global_position + muzzle_offset.rotated(global_rotation)
		
		var projectile = projectile_manager.get_projectile("laser", spawn_position, direction, owner_entity)
		
		if projectile:
			# Configure projectile
			if projectile.has_method("set_damage"):
				projectile.set_damage(damage)
			
			if projectile.has_method("set_speed"):
				projectile.set_speed(projectile_speed)
			
			if projectile.has_method("set_color") and projectile is Node2D:
				projectile.set_color(projectile_color)
			
			# Apply strategy modifications
			for strategy in applied_strategies:
				if strategy.has_method("modify_projectile"):
					strategy.modify_projectile(projectile)
			
			return projectile
	
	# Fallback to direct instantiation if no pool manager
	var projectile = projectile_scene.instantiate()
	
	# Add to the scene
	get_tree().current_scene.add_child(projectile)
	
	# Set properties
	projectile.global_position = global_position + muzzle_offset.rotated(global_rotation)
	
	# Set direction
	var direction = Vector2.RIGHT.rotated(global_rotation)
	if projectile.has_method("fire"):
		projectile.fire(direction, owner_entity)
	else:
		# Basic properties if no fire method
		projectile.rotation = global_rotation
		
		if "speed" in projectile:
			projectile.speed = projectile_speed
		
		if "damage" in projectile:
			projectile.damage = damage
		
		if "shooter" in projectile:
			projectile.shooter = owner_entity
	
	# Set color if applicable
	if "modulate" in projectile:
		projectile.modulate = projectile_color
	
	# Apply strategy modifications
	for strategy in applied_strategies:
		if strategy.has_method("modify_projectile"):
			strategy.modify_projectile(projectile)
	
	return projectile

# Setup muzzle flash
func _setup_muzzle_flash() -> void:
	# Check if we already have a muzzle flash node
	muzzle_flash = get_node_or_null("MuzzleFlash")
	
	if not muzzle_flash:
		# Create a simple muzzle flash
		muzzle_flash = Node2D.new()
		muzzle_flash.name = "MuzzleFlash"
		add_child(muzzle_flash)
		
		# Create a sprite for the flash
		var flash_sprite = Sprite2D.new()
		flash_sprite.name = "FlashSprite"
		
		# Try to load a texture
		var flash_texture = load("res://assets/effects/muzzle_flash.png")
		if flash_texture:
			flash_sprite.texture = flash_texture
		else:
			# Create a simple circle texture
			var image = Image.create(16, 16, false, Image.FORMAT_RGBA8)
			image.fill(Color(1, 1, 1, 1))
			
			# Draw a circle
			for x in range(16):
				for y in range(16):
					var dist = Vector2(x - 8, y - 8).length()
					if dist > 7:
						image.set_pixel(x, y, Color(0, 0, 0, 0))
			
			flash_sprite.texture = ImageTexture.create_from_image(image)
		
		# Set position and initial visibility
		flash_sprite.position = muzzle_offset
		muzzle_flash.add_child(flash_sprite)
		muzzle_flash.visible = false

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
		var fire_sound = load("res://assets/audio/laser.wav")
		if fire_sound:
			audio_player.stream = fire_sound
		
		add_child(audio_player)

# Show muzzle flash
func _show_muzzle_flash() -> void:
	if not muzzle_flash:
		return
	
	muzzle_flash.visible = true
	
	# Hide after a short delay
	get_tree().create_timer(0.05).timeout.connect(func(): muzzle_flash.visible = false)

# Play fire sound
func _play_fire_sound() -> void:
	# Use AudioManager if available
	if has_node("/root/AudioManager"):
		AudioManager.play_sfx("laser", global_position)
	elif audio_player:
		audio_player.play()

# Play reload sound
func _play_reload_sound() -> void:
	if has_node("/root/AudioManager"):
		AudioManager.play_sfx("reload", global_position)

# Event handlers
func _on_game_paused() -> void:
	# Pause processing when game is paused
	set_process(false)
