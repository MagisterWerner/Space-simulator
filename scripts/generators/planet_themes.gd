# scripts/generators/planet_themes.gd
# =========================
# Purpose:
#   Defines constants for planet types and categories
#   Provides a central place for theme definitions to ensure consistency
#   Can be imported by any script that needs these constants

extends RefCounted
class_name PlanetThemes

# Main planet category enum
enum PlanetCategory {
	TERRAN,   # Rocky/solid surface planets (Earth-like, desert, ice, etc.)
	GASEOUS   # Gas planets without solid surface (gas giants, etc.)
}

# Specific planet themes within categories
enum PlanetTheme {
	# Terran planets
	ARID,
	ICE,
	LAVA,
	LUSH,
	DESERT,
	ALPINE,
	OCEAN,
	
	# Gaseous planets
	GAS_GIANT  # Currently the only gaseous type
}

# For API compatibility with old system
static func get_planet_category(theme: int) -> int:
	# Currently only GAS_GIANT is GASEOUS, everything else is TERRAN
	if theme == PlanetTheme.GAS_GIANT:
		return PlanetCategory.GASEOUS
	return PlanetCategory.TERRAN
