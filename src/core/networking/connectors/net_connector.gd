extends RefCounted
class_name NetConnector

var _net: Node

func _init(net: Node) -> void:
	_net = net

func start_server(_id: String, _max_clients: int) -> Error:
	return ERR_UNAVAILABLE

func start_joining_game(_id: String) -> Error:
	return ERR_UNAVAILABLE

func stop() -> void:
	pass
