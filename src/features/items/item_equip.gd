class_name ItemEquip
extends Node3D

## Class for player-equipped items. Instantiated when player "opens" an item, eg takes crowbar to active inv slot.
## Handles things like triggering attack, interactions, etc. 

const InteractRay := preload("res://src/features/interaction/interact_ray.gd")

@export var idle_animation_override := ""

var interact_ray: InteractRay = null
var player: Player = null


func _ready() -> void:
	assert(interact_ray)
	assert(player)
