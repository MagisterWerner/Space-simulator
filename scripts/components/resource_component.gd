# resource_component.gd
extends Component
class_name ResourceComponent

signal resource_changed(resource_name, current, maximum)
signal resource_depleted(resource_name)
signal resource_restored(resource_name)

var resources = {}

func _process(delta):
	for resource_name in resources:
		var resource = resources[resource_name]
		if resource.regen_rate <= 0 or resource.current >= resource.maximum:
			continue
			
		var new_value = min(resource.current + resource.regen_rate * delta, resource.maximum)
		if new_value != resource.current:
			resource.current = new_value
			emit_signal("resource_changed", resource_name, resource.current, resource.maximum)
			
			if resource.was_depleted and resource.current > 0:
				resource.was_depleted = false
				emit_signal("resource_restored", resource_name)

func add_resource(name: String, max_value: float, regen_rate: float = 0.0, starting_value: float = -1.0):
	if starting_value < 0:
		starting_value = max_value
	
	resources[name] = {
		"current": starting_value,
		"maximum": max_value,
		"regen_rate": regen_rate,
		"was_depleted": false
	}
	
	emit_signal("resource_changed", name, starting_value, max_value)

func get_resource(name: String) -> float:
	return resources.get(name, {"current": 0.0}).current

func get_resource_max(name: String) -> float:
	return resources.get(name, {"maximum": 0.0}).maximum

func get_resource_percent(name: String) -> float:
	if not resources.has(name) or resources[name].maximum <= 0:
		return 0.0
	return resources[name].current / resources[name].maximum

func set_resource(name: String, value: float):
	if not resources.has(name):
		return
		
	var old_value = resources[name].current
	var new_value = clamp(value, 0.0, resources[name].maximum)
	resources[name].current = new_value
	
	emit_signal("resource_changed", name, new_value, resources[name].maximum)
	
	if old_value > 0 and new_value <= 0:
		resources[name].was_depleted = true
		emit_signal("resource_depleted", name)
	elif old_value <= 0 and new_value > 0:
		resources[name].was_depleted = false
		emit_signal("resource_restored", name)

func set_resource_max(name: String, max_value: float):
	if not resources.has(name):
		return
		
	resources[name].maximum = max_value
	
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
