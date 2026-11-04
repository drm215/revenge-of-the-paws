extends SceneTree

## Conditional uploads against fake_supabase.py: a save another device uploaded a moment ago must
## never be overwritten silently.

const SLOT := "save_race"

var _fails := 0
var _cloud: Node


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _post(path: String, data: Variant) -> void:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + path, ["Content-Type: application/json"], HTTPClient.METHOD_POST, JSON.stringify(data))
	await http.request_completed
	http.queue_free()


func _cloud_profile() -> String:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(OS.get_environment("FAKE_SUPABASE_URL") + "/_state")
	var res: Array = await http.request_completed
	http.queue_free()
	var st: Dictionary = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	for row: Dictionary in st.saves:
		if row.slot == SLOT:
			return row.profile
	return ""


## A local save with no sync on its way, so each test decides when one happens.
func _save_local(town: String) -> void:
	var p := Profile.new()
	p.region = "us_appalachia"
	p.town = town
	p.pet_species = "dog"
	p.pet_name = "Jack"
	p.team.assign(["black_bear", "horned_owl"])
	p.unlocked.assign(p.team)
	p.save()
	_cloud.get("_timer").stop()


func _run() -> void:
	Saves.use(SLOT)
	_cloud = root.get_node("Cloud")
	_cloud.state_path = "user://race_cloud.cfg"
	_cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	_cloud.anon_key = "anon"
	_cloud.log_out()

	_save_local("Alpha")
	_check(await _cloud.log_in("a@b.co", "oldpass") == "", "log in")  # (logging in syncs)
	_check(_cloud.status == "Saved to the cloud." and "Alpha" in await _cloud_profile(), "first upload creates the cloud save")
	var first: String = _cloud.get("_synced")[SLOT]
	_check("+" in first, "server version has a '+' in it: " + first)

	_save_local("Bravo")
	await _cloud.sync()
	var second: String = _cloud.get("_synced")[SLOT]
	_check("Bravo" in await _cloud_profile() and second != first, "a normal update lands (version %s)" % second)

	# The race: this device checked the cloud, then another device uploaded before this upload landed.
	_save_local("Charlie")
	await _post("/_bump", {"slot": SLOT, "profile": "[profile]\ntown=\"Other device\"\n"})
	_cloud.set("_busy", true)
	await _cloud.call("_upload", SLOT, second)
	_cloud.set("_busy", false)
	_check("Other device" in await _cloud_profile(), "the other device's save was NOT overwritten")
	_check(_cloud.get("_conflict_ui") != null, "the conflict prompt came up instead")
	var body := ""
	for l in (_cloud.get("_conflict_ui") as Node).find_children("*", "Label", true, false):
		body += l.text
	_check("Charlie" in body and "Other device" in body, "prompt shows both saves")
	await _cloud.call("_resolve_conflict", false)
	_check("Charlie" in await _cloud_profile() and _cloud.get("_conflict_ui") == null, "Keep this device: then it replaces the cloud save")

	# A first upload when the cloud already has a copy (e.g. an old version of this device's state).
	await _cloud.sync()
	_save_local("Delta")
	_cloud.set("_busy", true)
	await _cloud.call("_upload", SLOT, "")
	_cloud.set("_busy", false)
	_check("Delta" in await _cloud_profile() and _cloud.get("_conflict_ui") == null and _cloud.status == "Saved to the cloud.",
		"an insert that clashes re-checks, sees its own last version, and updates it (status: %s)" % _cloud.status)
	print("%d failure(s)" % _fails)
	quit()
