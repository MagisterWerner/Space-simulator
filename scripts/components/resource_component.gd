extends Component
class_name ResourceComponent

signal resource_changed(resource_name, current, maximum)
signal resource_depleted(resource_name)
signal resource_restored(resource_name)

# Dictionary to store resource types and their values
# Each resource has current value, max value, and regen rate
var resources = {}

func _initialize():
	pass

func _process(delta):
	# Update resources that regenerate over time
	for resource_name in resources:
		var resource = resources[resource_name]
		if resource.regen_rate > 0 and resource.current < resource.maximum:
			var new_value = min(resource.current + resource.regen_rate * delta, resource.maximum)
			if new_value != resource.current:
				resource.current = new_value
				emit_signal("resource_changed", resource_name, resource.current, resource.maximum)
				
				# Check if resource was depleted and is now restored
				if resource.was_depleted and resource.current > 0:
					resource.was_depleted = false
					emit_signal("resource_restored", resource_name)

func add_resource(name: String, max_value: float, regen_rate: float = 0.0, starting_value: float = -1.0):
	# If starting value is not specified, use max value
	if starting_value < 0:
		starting_value = max_value
	
	resources[name] = {
		"current": starting_value,
		"maximum": max_value,
		"regen_rate": regen_rate,
		"was_depleted": false
	}
	
	# Emit initial signal
	emit_signal("resource_changed", name, starting_value, max_value)

func get_resource(name: String) -> float:
	if resources.has(name):
		return resources[name].current
	return 0.0

func get_resource_max(name: String) -> float:
	if resources.has(name):
		return resources[name].maximum
	return 0.0

func get_resource_percent(name: String) -> float:
	if resources.has(name) and resources[name].maximum > 0:
		return resources[name].current / resources[name].maximum
	return 0.0

func set_resource(name: String, value: float):
	if resources.has(name):
		var old_value = resources[name].current
		var new_value = clamp(value, 0.0, resources[name].maximum)
		resources[name].current = new_value
		
		emit_signal("resource_changed", name, new_value, resources[name].maximum)
		
		# Check if resource was just depleted
		if old_value > 0 and new_value <= 0:
			resources[name].was_depleted = true
			emit_signal("resource_depleted", name)
		
		# Check if resource was restored from depletion
		elif old_value <= 0 and new_value > 0:
			resources[name].was_depleted = false
			emit_signal("resource_restored", name)

func set_resource_max(name: String, max_value: float):
	if resources.has(name):
		resources[name].maximum = max_value
		
		# Clamp current value to new maximum
		if resources[name].current > max_value:
			resources[name].current = max_value
			
		emit_signal("resource_changed", name, resources[name].current, max_value)

func set_resource_regen(name: String, regen_rate: float):
	if resources.has(name):
		resources[name].regen_rate = regen_rate

func use_resource(name: String, amount: float) -> bool:
	if not resources.has(name) or resources[name].current < amount:
		return false
		
	set_resource(name, resources[name].current - amount)
	return true

func add_resource_amount(name: String, amount: float):
	if resources.has(name):
		set_resource(name, resources[name].current + amount)

func has_resource(name: String, amount: float = 0.0) -> bool:
	return resources.has(name) and resources[name].current >= amount
