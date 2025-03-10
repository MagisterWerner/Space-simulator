# scripts/entities/moons/moon_volcanic.gd
# Volcanic (lava) moon implementation
extends "res://scripts/entities/moons/moon_base.gd"
class_name MoonVolcanic

func _generate_moon_texture() -> void:
	# Create a unique cache key
	var cache_key = seed_value * 10 + 2  # +2 for volcanic moon type
	
	# Get texture - either from cache or generate new
	if use_texture_cache and PlanetSpawnerBase.texture_cache != null:
		if PlanetSpawnerBase.texture_cache.moons.has(cache_key):
			# Use cached texture
			moon_texture = PlanetSpawnerBase.texture_cache.moons[cache_key]
			var moon_generator = MoonGenerator.new()
			pixel_size = moon_generator.get_moon_size(seed_value, is_gaseous)
		else:
			# Generate and cache texture
			var moon_generator = MoonGenerator.new()
			moon_texture = moon_generator.create_moon_texture(seed_value, MoonGenerator.MoonType.VOLCANIC, is_gaseous)
			pixel_size = moon_generator.get_moon_size(seed_value, is_gaseous)
			PlanetSpawnerBase.texture_cache.moons[cache_key] = moon_texture
	else:
		# Generate without caching
		var moon_generator = MoonGenerator.new()
		moon_texture = moon_generator.create_moon_texture(seed_value, MoonGenerator.MoonType.VOLCANIC, is_gaseous)
		pixel_size = moon_generator.get_moon_size(seed_value, is_gaseous)

func _get_moon_type_prefix() -> String:
	return "Volcanic"
