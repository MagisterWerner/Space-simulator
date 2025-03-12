# scripts/components/weapon_manager_component.gd
extends Component
class_name WeaponManagerComponent

signal weapon_switched(old_weapon, new_weapon, index)
signal weapon_added(weapon, index)
signal weapon_removed(weapon, index)

@export var auto_initialize: bool = true
@export var weapons_path: NodePath = "../Weapons"
@export var primary_input_action: String = "weapon_next"
@export var secondary_input_action: String = "weapon_previous"

var weapons: Array[WeaponComponent] = []
var current_weapon_index: int = -1
var weapons_node: Node = null

func setup() -> void:
	# Find or create the weapons container node
	if not weapons_path.is_empty():
		weapons_node = get_node_or_null(weapons_path)
	
	# Create a weapons container if it doesn't exist
	if not weapons_node:
		weapons_node = Node.new()
		weapons_node.name = "Weapons"
		owner_entity.add_child(weapons_node)
	
	if auto_initialize:
		# Find all existing weapon components in the container
		_find_weapon_components()
		
		# If weapons found, activate the first one
		if not weapons.is_empty():
			switch_to_weapon(0)

func _find_weapon_components() -> void:
	# Clear existing list
	weapons.clear()
	
	# Find all weapon components in the weapons container
	for child in weapons_node.get_children():
		if child is WeaponComponent:
			add_weapon(child)

func _process(_delta: float) -> void:
	if not enabled:
		return
		
	# Handle weapon switching input
	if Input.is_action_just_pressed(primary_input_action):
		next_weapon()
	elif Input.is_action_just_pressed(secondary_input_action):
		previous_weapon()

# Switch to the next weapon in the list
func next_weapon() -> void:
	if weapons.is_empty():
		return
		
	var next_index = (current_weapon_index + 1) % weapons.size()
	switch_to_weapon(next_index)

# Switch to the previous weapon in the list
func previous_weapon() -> void:
	if weapons.is_empty():
		return
		
	var prev_index = (current_weapon_index - 1 + weapons.size()) % weapons.size()
	switch_to_weapon(prev_index)

# Switch to a specific weapon by index
func switch_to_weapon(index: int) -> void:
	if index < 0 or index >= weapons.size() or index == current_weapon_index:
		return
	
	var old_weapon = get_current_weapon()
	var old_index = current_weapon_index
	
	# Disable the current weapon
	if old_weapon:
		old_weapon.disable()
	
	# Set and enable the new weapon
	current_weapon_index = index
	var new_weapon = get_current_weapon()
	
	if new_weapon:
		new_weapon.enable()
	
	# Emit signal about the weapon switch
	weapon_switched.emit(old_weapon, new_weapon, index)
	
	if debug_mode:
		_debug_print("Switched from weapon " + str(old_index) + " to " + str(current_weapon_index))

# Get the currently active weapon
func get_current_weapon() -> WeaponComponent:
	if current_weapon_index >= 0 and current_weapon_index < weapons.size():
		return weapons[current_weapon_index]
	return null

# Add a new weapon component to the system
func add_weapon(weapon: WeaponComponent) -> int:
	if weapon in weapons:
		return weapons.find(weapon)
	
	# Add to array and initially disable it
	weapons.append(weapon)
	weapon.disable()
	
	# Make sure it's in the weapons container node
	if weapon.get_parent() != weapons_node:
		if weapon.get_parent():
			weapon.get_parent().remove_child(weapon)
		weapons_node.add_child(weapon)
	
	var index = weapons.size() - 1
	weapon_added.emit(weapon, index)
	
	if debug_mode:
		_debug_print("Added weapon: " + weapon.name + " at index " + str(index))
	
	# If this is the first weapon, select it automatically
	if weapons.size() == 1:
		switch_to_weapon(0)
	
	return index

# Remove a weapon by index
func remove_weapon(index: int) -> WeaponComponent:
	if index < 0 or index >= weapons.size():
		return null
	
	var weapon = weapons[index]
	weapons.remove_at(index)
	
	# If removing the current weapon, switch to another one
	if index == current_weapon_index:
		if not weapons.is_empty():
			var new_index = min(index, weapons.size() - 1)
			current_weapon_index = -1  # Reset so it will switch even if index is the same
			switch_to_weapon(new_index)
		else:
			current_weapon_index = -1
	elif index < current_weapon_index:
		# Adjust current index if we removed a weapon before it
		current_weapon_index -= 1
	
	weapon_removed.emit(weapon, index)
	
	if debug_mode:
		_debug_print("Removed weapon at index " + str(index))
	
	return weapon

# Fire the current weapon
func fire() -> bool:
	var weapon = get_current_weapon()
	if weapon and weapon.enabled and weapon.has_method("fire"):
		return weapon.fire()
	return false

# Stop firing
func stop_firing() -> void:
	var weapon = get_current_weapon()
	if weapon and weapon.enabled and weapon.has_method("stop_firing"):
		weapon.stop_firing()
