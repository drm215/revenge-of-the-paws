class_name SaveHooks
extends RefCounted

## Lets cloud sync hear about local saves without the save code depending on it.

static var on_saved := Callable()


static func saved() -> void:
	if on_saved.is_valid():
		on_saved.call()
