class_name SaveHooks
extends RefCounted

## Lets cloud sync hear about local saves without the save code depending on it.

static var on_saved := Callable()


static func saved() -> void:
	if on_saved.is_valid():
		on_saved.call()


static var on_deleted := Callable()


## A saved game was deleted (its cloud copy should go too).
static func deleted(slot: String) -> void:
	if on_deleted.is_valid():
		on_deleted.call(slot)
