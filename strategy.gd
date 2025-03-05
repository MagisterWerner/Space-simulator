# strategy.gd
extends Resource
class_name Strategy

# Base class for all strategies that can be applied to components
# Each strategy modifies specific properties of a component

@export var strategy_name: String = "Base Strategy"
@export var description: String = "Base strategy class"
@export var icon_texture: Texture2D
@export var rarity: String = "Common"  # Common, Uncommon, Rare, Epic, Legendary
@export var price: int = 100

# Strategy-specific properties
var owner_component: Component = null

func apply_to_component(component: Component) -> void:
	owner_component = component

func remove_from_component() -> void:
	owner_component = null
