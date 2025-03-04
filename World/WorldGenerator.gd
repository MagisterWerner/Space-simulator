## Abstract base class for worlds.
##
## Splits the world into `sectors` of a fixed size in pixels. You can think of
## the world as a grid of square sectors.
## Exposes functions for extended classes to use, though the central part is the
## `_generate_sector()` virtual method. This is where you should generate the
## content of individual sectors.
class_name WorldGenerator
extends Node2D
#

## Size of a sector in pixels.
@export var sector_size := 1000.0
## Number of sectors to generate around the player on a given axis.
@export var sector_axis_count := 10
## Seed to generate the world. We will use a hash function to convert it to a unique number for each sector. See the `make_seed_for()` function below.
## This makes the world generation deterministic.
@export var start_seed := "world_generation"

## This dictionary can store important data about any generated sector, or even custom data for persistent worlds.
var _sectors := {}
## Coordinates of the sector the player currently is in. We use it to generate _sectors around the player.
var _current_sector := Vector2.ZERO
## There are some built-in functions in GDScript to generate random numbers, but the random number generator allows us to use a specific seed and provides more methods, which is useful for procedural generation.
var _rng := RandomNumberGenerator.new()

## We will reuse the three values below several times so we pre-calculate them.
## Half of `sector_size`.
@onready var _half_sector_size := sector_size / 2.0
## Total number of sectors to generate around the player.
@onready var _total_sector_count := sector_size * sector_size
## And this is half of `_total_sector_count`.
@onready var _half_sector_count := int(sector_axis_count / 2.0)


## Calls `_generate_sector()` for each sector in a grid around the player.
func generate() -> void:
	for x in range(-_half_sector_count, _half_sector_count):
		for y in range(-_half_sector_count, _half_sector_count):
			_generate_sector(x, y)


## Creates a text string for the seed with the format "seed_x_y" and uses the hash method to turn it into an integer.
## This allows us to use it with the `RandomNumberGenerator.seed` property.
func make_seed_for(_x_id: int, _y_id: int, custom_data := "") -> int:
	var new_seed := "%s_%s_%s" % [start_seed, _x_id, _y_id]
	if not custom_data.is_empty():
		new_seed = "%s_%s" % [new_seed, custom_data]
	return new_seed.hash()


## Virtual function that governs how we should generate a given sector based
## on its position in the infinite grid.
func _generate_sector(_x_id: int, _y_id: int) -> void:
	pass
