extends Node

## Cloud saves through Supabase (autoload "Cloud"): email/password accounts via Supabase Auth and
## one row per player in the `saves` table (server/supabase.sql). Sync is automatic: each local
## save uploads a few seconds later; on launch and before uploading, the newer of this device and
## the cloud wins, and if both changed the player chooses. Offline play just syncs later.

signal status_changed(text: String)
## A cloud save was written to disk; the game should reload it.
signal downloaded

const UPLOAD_DELAY := 3.0
const RETRY_DELAY := 30.0

## Supabase project; tests point this at a fake server (and Profile/Campaign.save_path elsewhere).
var state_path := "user://cloud.cfg"
var base_url := CloudConfig.URL
var anon_key := CloudConfig.ANON_KEY

var email := ""
var status := ""
var last_synced_at := ""  # server updated_at of the cloud save this device last matched
var last_synced_unix := 0.0

var _access := ""
var _refresh := ""
var _expires_at := 0.0
var _user_id := ""
var _dirty := false  # local save changed since the last sync
var _busy := false
var _timer := Timer.new()
var _pending := {}  # the cloud save waiting on a conflict decision
var _conflict_ui: CanvasLayer


func _ready() -> void:
	_timer.one_shot = true
	_timer.timeout.connect(sync)
	add_child(_timer)
	_load_state()
	SaveHooks.on_saved = mark_dirty
	if signed_in():
		sync()


func enabled() -> bool:
	return base_url != "" and anon_key != ""


func signed_in() -> bool:
	return _refresh != ""


## Called after every local save.
func mark_dirty() -> void:
	_dirty = true
	_store_state()
	if signed_in():
		_timer.start(UPLOAD_DELAY)


# --- Accounts -------------------------------------------------------------------------------

## Returns "" on success, "CONFIRM" if Supabase wants the email confirmed first, else an error.
func sign_up(user_email: String, password: String) -> String:
	var r := await _request(HTTPClient.METHOD_POST, "/auth/v1/signup", {"email": user_email, "password": password}, false)
	if not r.ok:
		return _error_text(r)
	if r.data is Dictionary and r.data.has("access_token"):
		_take_session(r.data)
		await sync()
		return ""
	return "CONFIRM"


func log_in(user_email: String, password: String) -> String:
	var r := await _request(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=password", {"email": user_email, "password": password}, false)
	if not r.ok:
		return _error_text(r)
	_take_session(r.data)
	await sync()
	return ""


func log_out() -> void:
	if signed_in() and Time.get_unix_time_from_system() < _expires_at:
		_request(HTTPClient.METHOD_POST, "/auth/v1/logout", {}, true)  # best effort
	_access = ""
	_refresh = ""
	_user_id = ""
	email = ""
	last_synced_at = ""
	_store_state()
	_set_status("Signed out. Your game is still saved on this device.")


func _take_session(d: Dictionary) -> void:
	_access = d.access_token
	_refresh = d.refresh_token
	_expires_at = Time.get_unix_time_from_system() + float(d.get("expires_in", 3600)) - 60.0
	_user_id = d.user.id
	email = d.user.get("email", email)
	_store_state()


func _ensure_token() -> bool:
	if _access != "" and Time.get_unix_time_from_system() < _expires_at:
		return true
	var r := await _request(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": _refresh}, false)
	if r.ok:
		_take_session(r.data)
		return true
	if r.code == 400 or r.code == 401:
		log_out()
		_set_status("Your session expired. Log in again to keep syncing.")
	return false


# --- Sync -----------------------------------------------------------------------------------

func sync() -> void:
	if _busy or not signed_in() or not enabled():
		return
	_busy = true
	await _sync_once()
	_busy = false


func _sync_once() -> void:
	if not await _ensure_token():
		if signed_in():
			_set_status("Offline. Will sync when back online.")
			_timer.start(RETRY_DELAY)
		return
	var r := await _request(HTTPClient.METHOD_GET, "/rest/v1/saves?user_id=eq.%s&select=profile,campaign,updated_at" % _user_id)
	if not r.ok:
		_set_status("Offline. Will sync when back online.")
		_timer.start(RETRY_DELAY)
		return
	var cloud: Dictionary = r.data[0] if r.data is Array and not r.data.is_empty() else {}
	var has_local := FileAccess.file_exists(Profile.save_path)
	if cloud.is_empty():
		if has_local:
			await _upload()
		else:
			_set_status("Signed in. Nothing saved yet.")
	elif cloud.updated_at == last_synced_at:
		if _dirty and has_local:
			await _upload()
		else:
			_set_status("Up to date.")
	elif not has_local or not _dirty:
		_apply(cloud)  # newer save from another device
	else:
		_pending = cloud
		_show_conflict()


func _upload() -> void:
	var body := {
		"user_id": _user_id,
		"profile": FileAccess.get_file_as_string(Profile.save_path),
		"campaign": FileAccess.get_file_as_string(Campaign.save_path) if FileAccess.file_exists(Campaign.save_path) else "",
		"device": OS.get_name(),
	}
	var r := await _request(HTTPClient.METHOD_POST, "/rest/v1/saves?on_conflict=user_id", body, true,
		["Prefer: resolution=merge-duplicates,return=representation"])
	if r.ok and r.data is Array and not r.data.is_empty():
		_mark_synced(r.data[0].updated_at)
		_set_status("Saved to the cloud.")
	else:
		_set_status("Cloud save failed. Will retry.")
		_timer.start(RETRY_DELAY)


func _apply(cloud: Dictionary) -> void:
	_write(Profile.save_path, cloud.profile)
	if String(cloud.get("campaign", "")) != "":
		_write(Campaign.save_path, cloud.campaign)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Campaign.save_path))
	_mark_synced(cloud.updated_at)
	_set_status("Loaded your cloud save.")
	downloaded.emit()


func _mark_synced(updated_at: String) -> void:
	last_synced_at = updated_at
	last_synced_unix = Time.get_unix_time_from_system()
	_dirty = false
	_store_state()


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)


## "Abingdon · Pepper · 13 territories · turn 17" for a pair of save texts.
static func summary(profile_text: String, campaign_text: String) -> String:
	var parts: PackedStringArray = []
	var p := ConfigFile.new()
	if p.parse(profile_text) == OK:
		parts.append(String(p.get_value("profile", "town", "")))
		if String(p.get_value("profile", "pet_name", "")) != "":
			parts.append(String(p.get_value("profile", "pet_name")))
	var c := ConfigFile.new()
	if campaign_text != "" and c.parse(campaign_text) == OK:
		parts.append("%d territories" % (c.get_value("campaign", "owned", []) as Array).size())
		parts.append("turn %d" % c.get_value("campaign", "turn", 0))
	return " · ".join(parts)


# --- Conflict prompt ------------------------------------------------------------------------

func _show_conflict() -> void:
	if _conflict_ui:
		_conflict_ui.queue_free()
	_conflict_ui = CanvasLayer.new()
	_conflict_ui.layer = 100
	add_child(_conflict_ui)
	var root := Control.new()
	root.theme = Retro.make_theme()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_conflict_ui.add_child(root)
	var bg := ColorRect.new()
	bg.color = Color(Retro.INK, 0.95)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(center)
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(600, 0)
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	var title := Retro.title(Label.new(), 16)
	title.text = "Two different saves"
	col.add_child(title)
	var body := Retro.text(Label.new(), 21)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var local := summary(FileAccess.get_file_as_string(Profile.save_path),
		FileAccess.get_file_as_string(Campaign.save_path) if FileAccess.file_exists(Campaign.save_path) else "")
	body.text = "This device and your cloud save both changed since they last synced.\n\nThis device: %s\nCloud: %s\n\nWhich one do you want to keep? The other is replaced." % [
		local, summary(_pending.profile, _pending.get("campaign", ""))]
	col.add_child(body)
	for choice in [["Keep this device", false], ["Use the cloud save", true]]:
		var b := Button.new()
		b.text = choice[0]
		b.custom_minimum_size = Vector2(0, 80)
		b.pressed.connect(_resolve_conflict.bind(choice[1]))
		col.add_child(b)


func _resolve_conflict(use_cloud: bool) -> void:
	_conflict_ui.queue_free()
	_conflict_ui = null
	var cloud := _pending
	_pending = {}
	if use_cloud:
		_apply(cloud)
	else:
		last_synced_at = cloud.updated_at  # overwrite it on purpose
		_busy = true
		await _upload()
		_busy = false


# --- Plumbing -------------------------------------------------------------------------------

func _request(method: int, path: String, body: Variant = null, auth := true, extra: PackedStringArray = []) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	add_child(http)
	var headers := PackedStringArray(["apikey: " + anon_key, "Content-Type: application/json"])
	if auth:
		headers.append("Authorization: Bearer " + _access)
	headers.append_array(extra)
	var err := http.request(base_url + path, headers, method, JSON.stringify(body) if body != null else "")
	if err != OK:
		http.queue_free()
		return {"ok": false, "code": 0, "data": null}
	var res: Array = await http.request_completed
	http.queue_free()
	var code: int = res[1]
	var text: String = (res[3] as PackedByteArray).get_string_from_utf8()
	return {"ok": res[0] == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300, "code": code,
		"data": JSON.parse_string(text) if text != "" else null}


func _error_text(r: Dictionary) -> String:
	if r.code == 0:
		return "Can't reach the cloud. Check your connection."
	if r.data is Dictionary:
		for key in ["msg", "error_description", "message", "error"]:
			if r.data.has(key):
				return String(r.data[key])
	return "Something went wrong (%d)." % r.code


func _set_status(text: String) -> void:
	status = text
	status_changed.emit(text)


func _store_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("cloud", "email", email)
	cfg.set_value("cloud", "user_id", _user_id)
	cfg.set_value("cloud", "refresh", _refresh)
	cfg.set_value("cloud", "last_synced_at", last_synced_at)
	cfg.set_value("cloud", "last_synced_unix", last_synced_unix)
	cfg.set_value("cloud", "dirty", _dirty)
	cfg.save(state_path)


func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(state_path) != OK:
		return
	email = cfg.get_value("cloud", "email", "")
	_user_id = cfg.get_value("cloud", "user_id", "")
	_refresh = cfg.get_value("cloud", "refresh", "")
	last_synced_at = cfg.get_value("cloud", "last_synced_at", "")
	last_synced_unix = cfg.get_value("cloud", "last_synced_unix", 0.0)
	_dirty = cfg.get_value("cloud", "dirty", false)
