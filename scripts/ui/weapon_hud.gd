extends CanvasLayer
class_name WeaponHUD

var player = null
var combat_component = null
var resource_component = null

# UI elements
var weapon_panel: Panel
var weapon_label: Label
var cooldown_bar: ProgressBar
var energy_bar: ProgressBar
var weapon_icon: TextureRect
var weapon_list: VBoxContainer

# Weapon icons (placeholders)
var weapon_icons = {}

func _ready():
	# Find player
	player = get_node_or_null("/root/Main/Player")
	if not player:
		return
	
	# Get player components
	combat_component = player.get_node_or_null("CombatComponent")
	resource_component = player.get_node_or_null("ResourceComponent")
	
	# Connect signals
	if combat_component:
		combat_component.connect("weapon_changed", _on_weapon_changed)
		combat_component.connect("weapon_fired", _on_weapon_fired)
	
	if resource_component:
		resource_component.connect("resource_changed", _on_resource_changed)
	
	# Create UI elements
	_create_ui()
	
	# Load placeholder weapon icons
	_load_weapon_icons()
	
	# Update UI
	_update_ui()

func _process(delta):
	# Update cooldown bar
	if combat_component and cooldown_bar:
		var cooldown = combat_component.current_cooldown
		var max_cooldown = 0.0
		
		if combat_component.current_weapon_strategy:
			max_cooldown = combat_component.current_weapon_strategy.cooldown
		
		if max_cooldown > 0:
			cooldown_bar.value = (1.0 - (cooldown / max_cooldown)) * 100
		else:
			cooldown_bar.value = 100
	
	# Update charge indication if player is charging a weapon
	if player.is_charging_weapon and player.current_charge > 0:
		cooldown_bar.modulate = Color(1.0, 0.5, 0.0)  # Orange for charging
		cooldown_bar.value = player.current_charge * 100
	elif cooldown_bar.modulate != Color.GREEN:
		cooldown_bar.modulate = Color.GREEN

func _create_ui():
	# Create the main panel
	weapon_panel = Panel.new()
	weapon_panel.anchor_right = 1.0
	weapon_panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	weapon_panel.offset_left = 20
	weapon_panel.offset_top = 20
	weapon_panel.offset_right = -20
	weapon_panel.offset_bottom = 80
	add_child(weapon_panel)
	
	# Create HBoxContainer for layout
	var h_box = HBoxContainer.new()
	h_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	h_box.offset_left = 10
	h_box.offset_top = 10
	h_box.offset_right = -10
	h_box.offset_bottom = -10
	weapon_panel.add_child(h_box)
	
	# Create weapon icon
	weapon_icon = TextureRect.new()
	weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon_icon.custom_minimum_size = Vector2(50, 50)
	h_box.add_child(weapon_icon)
	
	# Create VBox for weapon info
	var v_box = VBoxContainer.new()
	v_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h_box.add_child(v_box)
	
	# Create weapon label
	weapon_label = Label.new()
	weapon_label.text = "Weapon: Standard Laser"
	v_box.add_child(weapon_label)
	
	# Create cooldown bar
	cooldown_bar = ProgressBar.new()
	cooldown_bar.value = 100
	cooldown_bar.modulate = Color.GREEN
	v_box.add_child(cooldown_bar)
	
	# Create energy bar if resource component available
	if resource_component:
		energy_bar = ProgressBar.new()
		energy_bar.value = 100
		energy_bar.modulate = Color.BLUE
		
		var energy_label = Label.new()
		energy_label.text = "Energy"
		
		var energy_box = HBoxContainer.new()
		energy_box.add_child(energy_label)
		energy_box.add_child(energy_bar)
		energy_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		v_box.add_child(energy_box)
	
	# Create weapon list on right side
	weapon_list = VBoxContainer.new()
	weapon_list.custom_minimum_size = Vector2(150, 0)
	h_box.add_child(weapon_list)

func _load_weapon_icons():
	# Create default placeholder icons
	var icons = {
		"StandardLaser": _create_color_icon(Color(0.2, 0.5, 1.0)),
		"SpreadShot": _create_color_icon(Color(0.2, 0.8, 1.0)),
		"ChargeBeam": _create_color_icon(Color(1.0, 0.5, 0.0)),
		"MissileLauncher": _create_color_icon(Color(1.0, 0.3, 0.2))
	}
	
	# Try to load actual icons
	for weapon_name in icons.keys():
		var path = "res://sprites/weapons/" + weapon_name.to_lower() + "_icon.png"
		if ResourceLoader.exists(path):
			icons[weapon_name] = load(path)
	
	weapon_icons = icons

func _create_color_icon(color: Color) -> ImageTexture:
	# Create a simple colored rectangle as placeholder
	var image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(color)
	
	# Draw border
	for x in range(32):
		for y in range(32):
			if x == 0 or y == 0 or x == 31 or y == 31:
				image.set_pixel(x, y, Color.WHITE)
	
	return ImageTexture.create_from_image(image)

func _update_ui():
	if not combat_component:
		return
	
	# Update weapon label
	var current_weapon_name = combat_component.get_current_weapon_name()
	weapon_label.text = "Weapon: " + current_weapon_name
	
	# Update weapon icon
	if weapon_icons.has(current_weapon_name):
		weapon_icon.texture = weapon_icons[current_weapon_name]
	
	# Update weapon list
	_update_weapon_list()
	
	# Update energy bar if available
	if resource_component and energy_bar:
		var energy = resource_component.get_resource("energy")
		var max_energy = resource_component.get_resource_max("energy")
		
		if max_energy > 0:
			energy_bar.value = (energy / max_energy) * 100

func _update_weapon_list():
	# Clear existing list
	for child in weapon_list.get_children():
		weapon_list.remove_child(child)
		child.queue_free()
	
	# Add each available weapon
	var available_weapons = combat_component.get_available_weapons()
	var current_weapon = combat_component.get_current_weapon_name()
	
	for i in range(available_weapons.size()):
		var weapon_name = available_weapons[i]
		var h_box = HBoxContainer.new()
		
		# Create number label
		var num_label = Label.new()
		num_label.text = str(i + 1) + ":"
		num_label.custom_minimum_size = Vector2(20, 0)
		h_box.add_child(num_label)
		
		# Create small icon
		var icon = TextureRect.new()
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(20, 20)
		
		if weapon_icons.has(weapon_name):
			icon.texture = weapon_icons[weapon_name]
			
		h_box.add_child(icon)
		
		# Create weapon name label
		var name_label = Label.new()
		name_label.text = weapon_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h_box.add_child(name_label)
		
		# Highlight current weapon
		if weapon_name == current_weapon:
			h_box.modulate = Color(1.2, 1.2, 0.8)  # Slight highlight
			var font = name_label.get_theme_font("font")
			if font:
				var font_bold = font.duplicate()
				name_label.add_theme_font_override("font", font_bold)
		
		weapon_list.add_child(h_box)

# Signal handlers
func _on_weapon_changed(new_weapon):
	_update_ui()

func _on_weapon_fired(_position, _direction):
	# Update cooldown bar
	if cooldown_bar:
		cooldown_bar.value = 0
		cooldown_bar.modulate = Color.RED

func _on_resource_changed(resource_name, current, maximum):
	if resource_name == "energy" and energy_bar:
		energy_bar.value = (current / maximum) * 100
