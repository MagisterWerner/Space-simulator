extends Control
class_name GenerationQueueUI

# References to UI elements
@onready var pending_label = $PendingLabel
@onready var active_label = $ActiveLabel
@onready var progress_bar = $ProgressBar
@onready var pause_button = $PauseButton
@onready var clear_button = $ClearButton

# State
var is_paused = false
var total_completed = 0
var total_requested = 0
var update_timer = 0.0
var update_interval = 0.2

func _ready():
	# Connect to GenerationManager signals
	if has_node("/root/GenerationManager"):
		GenerationManager.generation_completed.connect(_on_generation_completed)
		GenerationManager.generation_failed.connect(_on_generation_failed)
		GenerationManager.queue_size_changed.connect(_on_queue_size_changed)
	
	# Connect UI elements
	pause_button.pressed.connect(_on_pause_button_pressed)
	clear_button.pressed.connect(_on_clear_button_pressed)
	
	# Initial update
	_update_ui()

func _process(delta):
	# Update UI periodically instead of every frame
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		_update_ui()

func _update_ui():
	if not has_node("/root/GenerationManager"):
		return
	
	var pending_count = GenerationManager.get_pending_count()
	var active_count = GenerationManager.get_active_count()
	
	pending_label.text = "Pending: " + str(pending_count)
	active_label.text = "Active: " + str(active_count)
	
	# Calculate progress
	if total_requested > 0:
		var progress = float(total_completed) / float(total_requested)
		progress_bar.value = int(progress * 100)
	else:
		progress_bar.value = 0
	
	# Show/hide based on activity
	visible = pending_count > 0 or active_count > 0 or progress_bar.value < 100
	
	# Update pause button text
	pause_button.text = "Resume" if is_paused else "Pause"

func _on_generation_completed(_request_id, _result):
	total_completed += 1
	call_deferred("_update_ui")

func _on_generation_failed(_request_id, _error):
	total_completed += 1
	call_deferred("_update_ui")

func _on_queue_size_changed(pending_count):
	# Update total requested count
	total_requested = total_completed + pending_count + GenerationManager.get_active_count()
	call_deferred("_update_ui")

func _on_pause_button_pressed():
	is_paused = !is_paused
	
	# Implementation depends on how pausing is handled in GenerationManager
	# For now, we'll just stop new requests from being processed
	# A real implementation would need a pause mechanism in the GenerationManager
	
	call_deferred("_update_ui")

func _on_clear_button_pressed():
	if has_node("/root/GenerationManager"):
		GenerationManager.clear_queue()
		
	# Reset counters
	total_completed = 0
	total_requested = 0
	call_deferred("_update_ui")

# Set UI visibility manually
func set_visible(should_show):
	visible = should_show

# Reset the counters
func reset_counters():
	total_completed = 0
	total_requested = 0
	call_deferred("_update_ui")
