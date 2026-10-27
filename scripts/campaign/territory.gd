class_name Territory
extends RefCounted

## One area on the campaign map: a real ZIP code area (or a generated district outside the US).

var id: String
var name: String
var label: String  # short text drawn on the map
var site: Vector2  # label point, projected to km, north up
var lonlat := Vector2.ZERO  # real-world label point, for real maps
var parts: Array[PackedVector2Array] = []  # outline rings (islands add more), km
var area := 0.0
var neighbors: Array[int] = []
var threat := 1
var owned := false
var boss := ""  # legend id if this is a lair
var failed_attacks := 0
var region := ""  # animal region this area belongs to
var condition := "forest"  # GameData.CONDITIONS key
var recruit := ""  # wild animal waiting to be rescued here, if any
var cache := ""  # trinket hidden here (lairs drop their legend's instead)


func _init(territory_id: String, territory_name: String, position: Vector2) -> void:
	id = territory_id
	name = territory_name
	label = territory_name
	site = position


## How much of the horde is left after the pack's failed attacks (1.0 = untouched).
func horde_strength() -> float:
	return maxf(GameData.MIN_ATTRITION, 1.0 - failed_attacks * GameData.ATTRITION_PER_LOSS)


## Name for messages: adds the ZIP when the map labels this territory by ZIP.
func full_name() -> String:
	return name if label == name else "%s %s" % [name, id]
