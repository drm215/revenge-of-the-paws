extends SceneTree

## "Lairs in sight" on the map lists unbeaten legends only.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _line(n: Node) -> String:
	for l in n.find_children("*", "Label", true, false):
		if "Lairs in sight" in l.text:
			return l.text
	return ""


func _map(c: Campaign, p: Profile) -> MapScreen:
	var map := MapScreen.new()
	map.campaign = c
	map.profile = p
	root.add_child(map)
	return map


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = Retro.make_theme()
	Profile.save_path = "user://lairs_profile.cfg"
	Campaign.save_path = "user://lairs_campaign.cfg"
	var p := Profile.new()
	p.region = "us_appalachia"
	p.zip = "24210"
	p.town = "Abingdon"
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(["black_bear", "horned_owl"])
	var c := Campaign.create(p)
	for t in c.territories:
		t.boss = ""
	var lair: Territory = c.territories[c.territories[c.home].neighbors[0]]
	lair.boss = "woodbooger"
	lair.owned = false
	var map := _map(c, p)
	await process_frame
	_check("Woodbooger" in _line(map), "unbeaten: " + _line(map))
	map.free()
	lair.owned = true
	map = _map(c, p)
	await process_frame
	_check(_line(map) == "", "beaten: the line is gone")
	map.free()
	lair.owned = false
	map = _map(c, p)
	await process_frame
	_check("Woodbooger" in _line(map), "retaken by the horde: back again")
	map.free()
	print("%d failure(s)" % _fails)
	quit()
