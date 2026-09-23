class_name CharacterPortrait
extends Node3D
## The 3D portrait arrangement: a dressed [Humanoid], its lighting, and the two framing
## cameras. Deliberately viewport-free so the setup can be opened and tuned in the
## editor. [CharacterImage] renders it offscreen through a [SubViewport].

## Portrait framings available.
enum View { FULL_BODY, BUST }

@onready var _model: Humanoid = %Humanoid
@onready var _full_body_camera: Camera3D = %FullBodyCamera
@onready var _bust_camera: Camera3D = %BustCamera


func _ready() -> void:
	# The portrait model is not spawned through a MultiplayerSpawner, so its
	# synchronizer would try to replicate a node no other peer knows about.
	for child in _model.get_children():
		if child is MultiplayerSynchronizer:
			child.queue_free()


## Dresses the model in [param worn_item_ids] (indexed by [enum PropSystem.PropSlot]).
func set_worn(worn_item_ids: Array[int]) -> void:
	var slots: Array[int] = []
	slots.assign(worn_item_ids)
	_model.prop_system.worn_slots = slots


## Makes the framing camera for [param view] current.
func set_view(view: View) -> void:
	_camera_for(view).current = true


func _camera_for(view: View) -> Camera3D:
	return _bust_camera if view == View.BUST else _full_body_camera
