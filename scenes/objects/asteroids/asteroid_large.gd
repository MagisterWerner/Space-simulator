extends RigidBody2D

var rng = RandomNumberGenerator.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	rng.randomize()
	var asteroids = [Globals.sprite_asteroid_l1, Globals.sprite_asteroid_l2, Globals.sprite_asteroid_l3, Globals.sprite_asteroid_l4, Globals.sprite_asteroid_l5]
	var _name = asteroids[rng.randi() % asteroids.size()]
	$Sprite2D.texture = (_name)
	$Sprite2D.modulate = Color8(rng.randi() % 32 + 192, rng.randi() % 32 + 192, rng.randi() % 32 + 192, 255)
	for i in range(asteroids.size()):
		if $Sprite2D.texture == asteroids[i]:
			var c_node = get_node("CollisionPolygon" + str(i+1))
			c_node.disabled = false
			self.mass = 50
		else:
			get_node("CollisionPolygon" + str(i+1)).queue_free()


func _spawn_asteroids(num: int):
	_spawn_asteroid_medium()
	for _i in range(num-1):
		_spawn_asteroid_small()


func _spawn_asteroid_small():
	var asteroid_small = Globals.scene_asteroid_small.instantiate()
	asteroid_small.position = self.position
	ObjectRegistry._asteroids.add_child(asteroid_small)
	_randomize_trajectory(asteroid_small)

func _spawn_asteroid_medium():
	var asteroid_medium = Globals.scene_asteroid_medium.instantiate()
	asteroid_medium.position = self.position
	ObjectRegistry._asteroids.add_child(asteroid_medium)
	_randomize_trajectory(asteroid_medium)	

func _randomize_trajectory(asteroid):
	# randomly choose -1 or 1
	var nums = [-1 , 1]
	var random = nums[randi()% nums.size()]

	# random spin
	asteroid.angular_velocity = random * 10
	asteroid.angular_damp = 0.75

	# random direction
	asteroid.linear_velocity = Vector2(random * 100, random * 100)
	asteroid.linear_damp = 0.75


func explode() -> void:
# Instance the explosion scene
	#var explosion = Globals.scene_explosion.instantiate()
	#explosion.set_position(self.position)
	#explosion.emission_sphere_radius = 1
	#ObjectRegistry._effects.add_child(explosion)

# When destroyed, instance smaller asteroids
	_spawn_asteroids(randi_range(1, 3))

# Remove the asteroid instance
	queue_free()
