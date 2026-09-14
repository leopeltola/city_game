class_name HandAnchor
extends Node3D
## Marks a child of an equip scene as attached to a specific hand. At mount time
## ItemEquip creates a RemoteTransform3D under the matching player hand slot that
## pushes the slot's (hand bone) transform onto this anchor each frame - the anchor
## is NOT reparented, it stays a child of the static equip root.
##
## Authoring: leave the anchor's own transform at identity (it is driven); put the
## authored offset from the hand bone on the anchor's children (visuals, hit shapes).
## Convention: at most one HandAnchor per side per item.

enum HandSide { RIGHT, LEFT }

@export var hand: HandSide = HandSide.RIGHT
