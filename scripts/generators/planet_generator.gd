# These functions should be added to scripts/generators/planet_generator.gd

# Add pregeneration method for common planet types
static func pregenerate_common_textures(seed_base: int) -> void:
	print("Pregenerating common planet textures...")
	var generator = new()
	
	# Pregenerate a lush planet (most important since it's preferred starting planet)
	var lush_seed = seed_base + 1
	var lush_textures = generator.create_planet_texture(lush_seed, PlanetTheme.LUSH)
	planet_texture_cache[lush_seed] = lush_textures
	
	# Pregenerate an ocean planet
	var ocean_seed = seed_base + 2
	var ocean_textures = generator.create_planet_texture(ocean_seed, PlanetTheme.OCEAN)
	planet_texture_cache[ocean_seed] = ocean_textures
	
	# Pregenerate a desert planet
	var desert_seed = seed_base + 3
	var desert_textures = generator.create_planet_texture(desert_seed, PlanetTheme.DESERT)
	planet_texture_cache[desert_seed] = desert_textures
	
	# Pregenerate one gas giant
	var gas_seed = seed_base + 4
	var gas_textures = generator.create_planet_texture(gas_seed, PlanetTheme.GAS_GIANT)
	planet_texture_cache[gas_seed] = gas_textures
	
	print("Texture pregeneration complete")
