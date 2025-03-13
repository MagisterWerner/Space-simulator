extends Node
class_name CelestialBodyNaming

# Label settings - adjust to your preference
var label_offset: Vector2 = Vector2(0, -40)
var show_label: bool = true
var fade_distance: float = 2000.0
var max_distance: float = 3000.0
var label_id: int = -1
var has_label: bool = false

# Planet/Moon references and properties
var parent_body: Node2D = null
var body_name: String = ""
var body_type: String = "generic" # "planet", "moon", etc.
var _label_manager = null

# Colors for different celestial body types
var label_styles = {
	"planet_terran": {
		"color": Color(0.7, 1.0, 0.7),
		"outline": Color(0.0, 0.3, 0.0, 0.7),
		"offset": Vector2(0, -45)
	},
	"planet_gaseous": {
		"color": Color(0.9, 0.9, 0.6),
		"outline": Color(0.4, 0.3, 0.0, 0.7),
		"offset": Vector2(0, -55)
	},
	"moon_rocky": {
		"color": Color(0.8, 0.8, 0.8),
		"outline": Color(0.2, 0.2, 0.2, 0.7),
		"offset": Vector2(0, -25)
	},
	"moon_icy": {
		"color": Color(0.7, 0.9, 1.0),
		"outline": Color(0.0, 0.2, 0.4, 0.7),
		"offset": Vector2(0, -25)
	},
	"moon_volcanic": {
		"color": Color(1.0, 0.6, 0.4),
		"outline": Color(0.4, 0.1, 0.0, 0.7),
		"offset": Vector2(0, -25)
	}
}

# Add this as a child to your planet/moon
func _ready() -> void:
	# Connect to parent's ready signal
	parent_body = get_parent()
	
	# Get LabelManager
	if has_node("/root/LabelManager"):
		_label_manager = get_node("/root/LabelManager")
	else:
		push_error("CelestialBodyNaming: LabelManager not found!")
		return
	
	# Short delay to ensure all properties are set
	call_deferred("_create_name_label")
	
	# Connect to tree_exiting signal
	parent_body.tree_exiting.connect(_remove_label)

func _create_name_label() -> void:
	if not _label_manager or not parent_body or not show_label:
		return
	
	await get_tree().process_frame
	
	# Generate a name if none exists
	if body_name.is_empty():
		_generate_name()
	
	if body_name.is_empty():
		return
	
	# Get appropriate style based on body type
	var style = "generic"
	if label_styles.has(body_type):
		style = body_type
		label_offset = label_styles[body_type].offset
	
	# Create the label if it doesn't exist
	if not has_label:
		var label = _label_manager.create_entity_label(parent_body, body_name, body_type)
		
		# Try to set label style if supported
		if label and label.has_method("set_style"):
			label.set_style(style)
		
		# Create the label
		has_label = true
	
		# Store for cleanup
		if parent_body.has_meta("label_id"):
			label_id = parent_body.get_meta("label_id")
	
	# Update existing properties
	if has_label and _label_manager:
		# Update label properties if needed
		# No further action needed - LabelManager handles the updates
		pass

# Generate name based on object type
func _generate_name() -> void:
	# For moons
	if body_type.begins_with("moon_"):
		var moon_type = 0  # Default rocky
		if body_type == "moon_icy":
			moon_type = 1
		elif body_type == "moon_volcanic":
			moon_type = 2
		
		# Get parent planet name if exists
		var parent_name = "Planet"
		var moon_index = 0
		
		if parent_body and parent_body.get("parent_planet") != null:
			var parent_planet = parent_body.parent_planet
			if parent_planet and parent_planet.get("planet_name") != null:
				parent_name = parent_planet.planet_name
			
			# Try to determine moon index
			if parent_planet and parent_planet.get("moons") != null:
				moon_index = parent_planet.moons.find(parent_body)
				if moon_index < 0:
					moon_index = 0
		
		# Get seed value
		var seed_value = 0
		if parent_body.get("seed_value") != null:
			seed_value = parent_body.seed_value
		
		# Generate the name
		body_name = PlanetNameGenerator.generate_moon_name(seed_value, parent_name, moon_type, moon_index)
		
		# Apply the name to the parent body if property exists
		if parent_body.get("moon_name") != null:
			parent_body.moon_name = body_name
	
	# For planets
	elif body_type.begins_with("planet_"):
		var is_gaseous = body_type == "planet_gaseous"
		var theme_id = -1
		
		if parent_body.get("theme_id") != null:
			theme_id = parent_body.theme_id
		
		# Get seed value
		var seed_value = 0
		if parent_body.get("seed_value") != null:
			seed_value = parent_body.seed_value
		
		# Generate name
		body_name = PlanetNameGenerator.generate_planet_name(seed_value, is_gaseous, theme_id)
		
		# Apply the name to parent body if property exists
		if parent_body.get("planet_name") != null:
			parent_body.planet_name = body_name

# Remove label when body is removed
func _remove_label() -> void:
	if _label_manager and has_label:
		# Use entity_id for removal if available
		if label_id >= 0:
			_label_manager.remove_entity_label(label_id)
		else:
			# Try to remove by entity ID if available
			var entity_id = -1
			if parent_body and parent_body.has_meta("entity_id"):
				entity_id = parent_body.get_meta("entity_id")
				_label_manager.remove_entity_label(entity_id)
		
		has_label = false

# Set the name explicitly
func set_name(new_name: String) -> void:
	body_name = new_name
	
	# Apply the name to the parent body if property exists
	if parent_body:
		if body_type.begins_with("planet_") and parent_body.get("planet_name") != null:
			parent_body.planet_name = body_name
		elif body_type.begins_with("moon_") and parent_body.get("moon_name") != null:
			parent_body.moon_name = body_name
	
	# Update label if it exists
	if has_label and _label_manager:
		# TODO: Add method to update label text if LabelManager supports it
		pass

# Configure the label
func configure_label(style_name: String, vertical_offset: float = -40) -> void:
	body_type = style_name
	
	if label_styles.has(style_name):
		label_offset = label_styles[style_name].offset
	else:
		label_offset = Vector2(0, vertical_offset)
	
	# Re-create the label with new style
	if has_label:
		_remove_label()
		_create_name_label()
