extends Node

class LoadingData:
	extends RefCounted

	signal finished(succesful: bool)

	var path: String
	var progress_callback: Callable = func(_val: float): pass
	var loaded := false


	func _init(_path: String) -> void:
		path = _path


	func call_callback(value: float):
		progress_callback.call(value)


## { Path: [LoadingData] }
var _loading: Dictionary[String, LoadingData] = { }


func _process(_delta: float) -> void:
	for loading_item in _loading:
		var progress = []
		var data := _loading[loading_item]
		if data.loaded:
			continue
		match ResourceLoader.load_threaded_get_status(loading_item, progress):
			ResourceLoader.ThreadLoadStatus.THREAD_LOAD_IN_PROGRESS:
				data.call_callback(progress[0] if progress else 0.0)
			ResourceLoader.ThreadLoadStatus.THREAD_LOAD_FAILED:
				data.call_callback(progress[0] if progress else 0.0)
				data.finished.emit(false)
			ResourceLoader.ThreadLoadStatus.THREAD_LOAD_LOADED:
				data.call_callback(progress[0] if progress else 0.0)
				data.loaded = true
				data.finished.emit(true)
			ResourceLoader.ThreadLoadStatus.THREAD_LOAD_INVALID_RESOURCE:
				data.call_callback(progress[0] if progress else 0.0)
				data.finished.emit(false)


## Loads the resource on a background thread. Can be awaited.
##
## Returns: null | Resource.
func load_resource(
		path: String,
		progress_callback: Callable = func(_progress: float): pass,
) -> Resource:
	var err := ResourceLoader.load_threaded_request(path)
	if err != OK:
		return null
	_loading[path] = LoadingData.new(path)
	_loading[path].progress_callback = progress_callback
	var success: bool = await _loading[path].finished
	if not success:
		return null
	progress_callback.call(1.0) # just in case
	return ResourceLoader.load_threaded_get(path)
