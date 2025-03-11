# scripts/ui/debug_panel.gd
# ========================
# Purpose:
#   In-game UI panel for toggling different debug options
#   Connects to GameSettings to update debug settings in real-time

extends Control
class_name DebugPanel

# Toggle buttons for each debug option
@onready var master_toggle: CheckBox = $VBoxContainer/MasterToggle
@onready var seed_manager_toggle: CheckBox = $VBoxContainer/SeedManagerToggle
@onready var world_generator_toggle: CheckBox = $VBoxContainer/WorldGeneratorToggle
@onready var entity_generation_toggle: CheckBox = $VBoxContainer/EntityGenerationToggle
@onready var physics_toggle: CheckBox = $VBoxContainer/PhysicsToggle
@onready var ui_toggle: CheckBox = $VBoxContainer/UIToggle
@onready var components_toggle: CheckBox = $VBoxContainer/ComponentsToggle
@onready var logging_toggle: CheckBox = $VBoxContainer/LoggingToggle
@onready var grid_toggle: CheckBox = $VBoxContainer/GridToggle

# Toggle all button
@onready var toggle_all_button: Button = $VBoxContainer/ToggleAllButton

# Game settings reference
var game_settings: GameSettings = null

# Indicates if we're currently updating toggles to prevent feedback loops
var _updating_toggles: bool = false

func _ready() -> void:
	# Find GameSettings
	_find_game_settings()
	
	# Connect button signals
	_connect_signals()
	
	# Initialize toggle states based on current settings
	_initialize_toggle_states()

# Find GameSettings node
func _find_game_settings() -> void:
	var main_scene = get_tree().current_scene
	game_settings = main_scene.get_node_or_null("GameSettings")
	
	if game_settings:
		# Connect to GameSettings debug changes
		if not game_settings.is_connected("debug_settings_changed", _on_debug_settings_changed):
			game_settings.connect("debug_settings_changed", _on_debug_settings_changed)
	else:
		push_error("DebugPanel: GameSettings not found!")

# Connect toggle signals
func _connect_signals() -> void:
	# Connect toggle buttons
	master_toggle.toggled.connect(_on_master_toggle)
	seed_manager_toggle.toggled.connect(_on_seed_manager_toggle)
	world_generator_toggle.toggled.connect(_on_world_generator_toggle)
	entity_generation_toggle.toggled.connect(_on_entity_generation_toggle)
	physics_toggle.toggled.connect(_on_physics_toggle)
	ui_toggle.toggled.connect(_on_ui_toggle)
	components_toggle.toggled.connect(_on_components_toggle)
	logging_toggle.toggled.connect(_on_logging_toggle)
	grid_toggle.toggled.connect(_on_grid_toggle)
	
	# Connect toggle all button
	toggle_all_button.pressed.connect(_on_toggle_all_pressed)

# Initialize toggle states based on GameSettings
func _initialize_toggle_states() -> void:
	if not game_settings:
		return
	
	_updating_toggles = true
	
	# Set toggle states
	master_toggle.button_pressed = game_settings.debug_mode
	seed_manager_toggle.button_pressed = game_settings.debug_seed_manager
	world_generator_toggle.button_pressed = game_settings.debug_world_generator
	entity_generation_toggle.button_pressed = game_settings.debug_entity_generation
	physics_toggle.button_pressed = game_settings.debug_physics
	ui_toggle.button_pressed = game_settings.debug_ui
	components_toggle.button_pressed = game_settings.debug_components
	logging_toggle.button_pressed = game_settings.debug_logging
	grid_toggle.button_pressed = game_settings.draw_debug_grid
	
	# Update toggle enabled states based on master toggle
	_update_toggle_enabled_states()
	
	_updating_toggles = false

# Update which toggles are enabled based on master toggle
func _update_toggle_enabled_states() -> void:
	var master_on = master_toggle.button_pressed
	
	# Child toggles are only enabled if master toggle is on
	seed_manager_toggle.disabled = !master_on
	world_generator_toggle.disabled = !master_on
	entity_generation_toggle.disabled = !master_on
	physics_toggle.disabled = !master_on
	ui_toggle.disabled = !master_on
	components_toggle.disabled = !master_on
	logging_toggle.disabled = !master_on
	grid_toggle.disabled = !master_on

# Handle GameSettings debug changes
func _on_debug_settings_changed(debug_settings: Dictionary) -> void:
	# Only update UI if we're not the ones making the change
	if _updating_toggles:
		return
	
	_updating_toggles = true
	
	# Update toggle states based on the settings
	master_toggle.button_pressed = debug_settings.get("master", false)
	seed_manager_toggle.button_pressed = debug_settings.get("seed_manager", false)
	world_generator_toggle.button_pressed = debug_settings.get("world_generator", false)
	entity_generation_toggle.button_pressed = debug_settings.get("entity_generation", false)
	physics_toggle.button_pressed = debug_settings.get("physics", false)
	ui_toggle.button_pressed = debug_settings.get("ui", false)
	components_toggle.button_pressed = debug_settings.get("components", false)
	logging_toggle.button_pressed = debug_settings.get("logging", false)
	grid_toggle.button_pressed = debug_settings.get("grid", false)
	
	# Update which toggles are enabled
	_update_toggle_enabled_states()
	
	_updating_toggles = false

# Toggle handlers
func _on_master_toggle(toggled: bool) -> void:
	if _updating_toggles or not game_settings:
		return
	
	_updating_toggles = true
	
	# Update master debug toggle
	game_settings.debug_mode = toggled
	
	# Update enabled states
	_update_toggle_enabled_states()
	
	_updating_toggles = false

func _on_seed_manager_toggle(toggled: bool) -> void:
	if _updating_toggles or not game_settings:
		return
	
	game_settings.debug_seed_manager = toggled

func _on_world_generator_toggle(toggled: bool) -> void:
	if _updating_toggles or not game_settings:
		return
	
	game_settings.debug_world_generator = toggled

func _on_entity_generation_toggle(toggled: bool) -> void:
	if _updating_toggles or not game_settings:
		return
	
	game_settings.debug_entity_generation = toggled

func _on_physics_toggle(toggled: bool) -> void:
	if _updating_toggles or not game_settings:
		return
	
	game_settings.debug_physics = toggled

func _on_ui_toggle(toggled: bool) -> void:
	if _updating_toggles or not game_settings:
		return
	
	game_settings.debug_ui = toggled

func _on_components_toggle(toggled: bool) -> void:
	if _updating_toggles or not game_settings:
		return
	
	game_settings.debug_components = toggled

func _on_logging_toggle(toggled: bool) -> void:
	if _updating_toggles or not game_settings:
		return
	
	game_settings.debug_logging = toggled

func _on_grid_toggle(toggled: bool) -> void:
	if _updating_toggles or not game_settings:
		return
	
	game_settings.draw_debug_grid = toggled

# Toggle all button handler
func _on_toggle_all_pressed() -> void:
	if not game_settings:
		return
	
	_updating_toggles = true
	
	# Find the current state - if any are on, turn all off, otherwise turn all on
	var any_on = (
		game_settings.debug_seed_manager or
		game_settings.debug_world_generator or
		game_settings.debug_entity_generation or
		game_settings.debug_physics or
		game_settings.debug_ui or
		game_settings.debug_components or
		game_settings.debug_logging or
		game_settings.draw_debug_grid
	)
	
	var new_state = not any_on
	
	# Set master toggle first
	master_toggle.button_pressed = new_state
	game_settings.debug_mode = new_state
	
	# Set all individual toggles
	seed_manager_toggle.button_pressed = new_state
	world_generator_toggle.button_pressed = new_state
	entity_generation_toggle.button_pressed = new_state
	physics_toggle.button_pressed = new_state
	ui_toggle.button_pressed = new_state
	components_toggle.button_pressed = new_state
	logging_toggle.button_pressed = new_state
	grid_toggle.button_pressed = new_state
	
	# Update GameSettings
	game_settings.debug_seed_manager = new_state
	game_settings.debug_world_generator = new_state
	game_settings.debug_entity_generation = new_state
	game_settings.debug_physics = new_state
	game_settings.debug_ui = new_state
	game_settings.debug_components = new_state
	game_settings.debug_logging = new_state
	game_settings.draw_debug_grid = new_state
	
	# Update enabled states
	_update_toggle_enabled_states()
	
	_updating_toggles = false
