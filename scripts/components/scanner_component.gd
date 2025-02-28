extends Component
class_name ScannerComponent

signal object_detected(object, distance, direction)
signal object_lost(object)
signal scan_pulse_sent(radius)

@export var scan_radius: float = 500.0
@export var scan_interval: float = 1.0
@export var automatic_scanning: bool = true
@export var scan_layers: Array[String] = ["enemies", "asteroids", "planets", "items"]

var scan_timer: float = 0.0
var detected_objects = {}  # Dictionary of detected objects and their properties
var detection_visual: Node2D = null
var scan_pulse_visual: Node2D = null
var scan_pulse_radius: float = 0.0
var is_pulse_active: bool = false

func _initialize():
	# Create scanner visuals
	create_scan_visuals()
	
	# Start with a scan if automatic
	if automatic_scanning:
		scan_timer = 0.0

func _process(delta):
	# Handle automatic scanning
	if automatic_scanning:
		scan_timer -= delta
		if scan_timer <= 0:
			perform_scan()
			scan_timer = scan_interval
	
	# Animate the scan pulse if active
	if is_pulse_active:
		scan_pulse_radius += 200.0 * delta  # Speed of pulse animation
		if scan_pulse_radius > scan_radius:
			is_pulse_active = false
		update_scan_pulse()

func perform_scan():
	# Reset the scan pulse
	scan_pulse_radius = 0.0
	is_pulse_active = true
	emit_signal("scan_pulse_sent", scan_radius)
	
	# Keep track of previously detected objects to check what was lost
	var previously_detected = detected_objects.duplicate()
	detected_objects.clear()
	
	# Scan for objects in each layer
	for layer in scan_layers:
		var objects = get_tree().get_nodes_in_group(layer)
		for obj in objects:
			if obj == entity:  # Skip self
				continue
				
			var distance = entity.global_position.distance_to(obj.global_position)
			if distance <= scan_radius:
				var direction = (obj.global_position - entity.global_position).normalized()
				
				# Add to detected objects
				detected_objects[obj] = {
					"distance": distance,
					"direction": direction,
					"type": layer
				}
				
				# Emit signal for newly detected objects
				if not previously_detected.has(obj):
					emit_signal("object_detected", obj, distance, direction)
	
	# Check for objects that are no longer detected
	for obj in previously_detected:
		if not detected_objects.has(obj):
			emit_signal("object_lost", obj)
	
	# Update detection visual
	update_detection_visual()

func is_object_detected(obj) -> bool:
	return detected_objects.has(obj)

func get_detected_objects() -> Dictionary:
	return detected_objects

func get_nearest_object_of_type(type: String):
	var nearest = null
	var nearest_distance = INF
	
	for obj in detected_objects:
		if detected_objects[obj].type == type:
			var distance = detected_objects[obj].distance
			if distance < nearest_distance:
				nearest = obj
				nearest_distance = distance
	
	return nearest

func create_scan_visuals():
	# Create detection visual node
	detection_visual = Node2D.new()
	detection_visual.name = "DetectionVisual"
	detection_visual.z_index = -1  # Draw behind entity
	entity.add_child(detection_visual)
	
	# Create scan pulse visual node
	scan_pulse_visual = Node2D.new()
	scan_pulse_visual.name = "ScanPulseVisual"
	scan_pulse_visual.z_index = -2  # Draw behind detection visual
	entity.add_child(scan_pulse_visual)

func update_detection_visual():
	# This would be implemented to show detected objects
	detection_visual.queue_redraw()

func update_scan_pulse():
	# This would be implemented to animate the scan pulse
	scan_pulse_visual.queue_redraw()
