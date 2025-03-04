extends RigidBody2D

var rng = RandomNumberGenerator.new()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	rng.randomize()
	var asteroids = [Globals.sprite_asteroid_s1, Globals.sprite_asteroid_s2, Globals.sprite_asteroid_s3, Globals.sprite_asteroid_s4, Globals.sprite_asteroid_s5]
	var name = asteroids[rng.randi() % asteroids.size()]
	$Sprite2D.texture = (name)
	$Sprite2D.modulate = Color8(rng.randi() % 32 + 192, rng.randi() % 32 + 192, rng.randi() % 32 + 192, 255)
	for i in range(asteroids.size()):
		if $Sprite2D.texture == asteroids[i]:
			var c_node = get_node("CollisionPolygon" + str(i+1))
			c_node.disabled = false
			self.mass = 1
		else:
			get_node("CollisionPolygon" + str(i+1)).queue_free()


func explode() -> void:
# Instance the explosion scene
	var explosion = Globals.scene_explosion.instantiate()
	explosion.set_position(self.position)
	explosion.emission_sphere_radius = 1
	ObjectRegistry._effects.add_child(explosion)

# Remove the asteroid instance
	queue_free()
