extends Node

## Cloud saves through Supabase (autoload "Cloud"): email/password accounts via Supabase Auth and
## one row per player in the `saves` table (server/supabase.sql). Sync is automatic: each local
## save uploads a few seconds later; on launch and before uploading, the newer of this device and
## the cloud wins, and if both changed the player chooses. Offline play just syncs later.

signal status_changed(text: String)
## A cloud save was written to disk; the game should reload it.
signal downloaded
## The player logged out (teams forget the account's team).
signal signed_out
## The player opened a link from a Supabase email: show the account screen (new password, or why it failed).
signal reset_requested

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
var reset_pending := false  # signed in from a reset link; waiting on a new password

var _access := ""
var _refresh := ""
var _expires_at := 0.0
var _user_id := ""
var _dirty := false  # local save changed since the last sync
var _busy := false
var _timer := Timer.new()
var _pending := {}  # the cloud save waiting on a conflict decision
var _siege_pending := {}  # siege week (as text) -> damage not yet sent
var _siege_name := ""
var _last_error := ""  # why the last request failed, shown after "Offline" so problems can be traced
var _conflict_ui: CanvasLayer


func _ready() -> void:
	_timer.one_shot = true
	_timer.timeout.connect(sync)
	add_child(_timer)
	_load_state()
	SaveHooks.on_saved = mark_dirty
	if enabled() and await _take_link_session():
		return
	if signed_in():
		sync()


## The signed-in account's id ("" when signed out).
func user_id() -> String:
	return _user_id


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
	reset_pending = false
	_store_state()
	_set_status("Signed out. Your game is still saved on this device.")
	signed_out.emit()


## Emails a link that opens the game ready to choose a new password. "" on success, else an error.
func send_reset(user_email: String) -> String:
	var r := await _request(HTTPClient.METHOD_POST, "/auth/v1/recover?redirect_to=" + _site_url().uri_encode(),
		{"email": user_email}, false)
	return "" if r.ok else _error_text(r)


## Sets a new password for the signed-in player. "" on success, else an error.
func set_password(password: String) -> String:
	if not await _ensure_token():
		return "Can't reach the cloud. Check your connection."
	var r := await _request(HTTPClient.METHOD_PUT, "/auth/v1/user", {"password": password})
	if not r.ok:
		return _error_text(r)
	reset_pending = false
	_set_status("Password changed.")
	return ""


## Links in Supabase emails (confirm account, reset password) open the game with a session in the
## URL fragment: sign in with it and tidy the address bar. True if there was one.
func _take_link_session() -> bool:
	if not OS.has_feature("web"):
		return false
	var fragment := str(JavaScriptBridge.eval("window.location.hash", true)).trim_prefix("#")
	if not ("access_token=" in fragment or "error=" in fragment):
		return false
	JavaScriptBridge.eval("history.replaceState(null, '', window.location.pathname + window.location.search)", true)
	await take_fragment(fragment)
	return true


## Signs in from an email link's URL fragment ("access_token=...&type=recovery"). Public for tests.
func take_fragment(fragment: String) -> void:
	var args := {}
	for pair in fragment.split("&", false):
		var kv := pair.split("=", true, 1)
		args[kv[0].uri_decode()] = kv[1].replace("+", " ").uri_decode() if kv.size() > 1 else ""
	if args.has("error") or not args.has("access_token"):
		_set_status("That email link didn't work (%s). Ask for a new one." % args.get("error_description", args.get("error", "no session")))
		reset_requested.emit()
		return
	_access = args.access_token
	_expires_at = Time.get_unix_time_from_system() + float(args.get("expires_in", 3600)) - 60.0
	var r := await _request(HTTPClient.METHOD_GET, "/auth/v1/user")
	if not r.ok or not r.data is Dictionary:
		_access = ""
		_set_status("That email link didn't work. Ask for a new one.")
		reset_requested.emit()
		return
	_take_session({"access_token": args.access_token, "refresh_token": args.get("refresh_token", ""),
		"expires_in": args.get("expires_in", 3600), "user": r.data})
	reset_pending = args.get("type", "") == "recovery"
	await sync()  # may download a newer save and reload the game; reset_pending survives that
	if reset_pending:
		_set_status("Choose a new password.")
		reset_requested.emit()
	else:
		_set_status("Email confirmed. You're signed in.")


## Where links in emails lead back to: this page on the web, else the public site.
func _site_url() -> String:
	if OS.has_feature("web"):
		return str(JavaScriptBridge.eval("window.location.origin + window.location.pathname", true))
	return CloudConfig.SITE_URL


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
	_note_error("refresh", r)
	return false


# --- Sync -----------------------------------------------------------------------------------

func sync() -> void:
	if _busy or not signed_in() or not enabled():
		return
	_busy = true
	await _sync_once()
	await _send_siege()
	_busy = false


## `retried`: this pass follows an upload that lost a race with another device (never loops twice).
func _sync_once(retried := false) -> void:
	if not await _ensure_token():
		if signed_in():
			_set_status("Offline. Will sync when back online." + _last_error)
			_timer.start(RETRY_DELAY)
		return
	var path := "/rest/v1/saves?user_id=eq.%s&select=profile,campaign,updated_at" % _user_id
	var r := await _request(HTTPClient.METHOD_GET, path)
	if r.code == 401 or r.code == 403:
		_access = ""  # the database turned the login down: refresh it and try once more
		if await _ensure_token():
			r = await _request(HTTPClient.METHOD_GET, path)
	if not r.ok:
		if signed_in():
			_note_error("read", r)
			_set_status("Offline. Will sync when back online." + _last_error)
			_timer.start(RETRY_DELAY)
		return
	var cloud: Dictionary = r.data[0] if r.data is Array and not r.data.is_empty() else {}
	var has_local := FileAccess.file_exists(Profile.save_path)
	if cloud.is_empty():
		if has_local:
			await _upload("", retried)
		else:
			_set_status("Signed in. Nothing saved yet.")
	elif cloud.updated_at == last_synced_at:
		if _dirty and has_local:
			await _upload(cloud.updated_at, retried)
		else:
			_set_status("Up to date.")
	elif not has_local or not _dirty:
		_apply(cloud)  # newer save from another device
	else:
		_pending = cloud
		_show_conflict()


## Uploads this device's save over cloud version `expected` ("" = the cloud has none yet). The write
## only lands if the cloud still holds exactly that version, so a save another device uploaded a
## moment ago is never overwritten: sync looks again instead and offers the conflict prompt.
func _upload(expected: String, retried := false) -> void:
	var body := {
		"profile": FileAccess.get_file_as_string(Profile.save_path),
		"campaign": FileAccess.get_file_as_string(Campaign.save_path) if FileAccess.file_exists(Campaign.save_path) else "",
		"device": OS.get_name(),
	}
	var r: Dictionary
	if expected == "":
		body.user_id = _user_id
		r = await _request(HTTPClient.METHOD_POST, "/rest/v1/saves", body, true, ["Prefer: return=representation"])
	else:
		r = await _request(HTTPClient.METHOD_PATCH, "/rest/v1/saves?user_id=eq.%s&updated_at=eq.%s" % [_user_id, expected.uri_encode()],
			body, true, ["Prefer: return=representation"])
	if r.ok and r.data is Array and not r.data.is_empty():
		_mark_synced(r.data[0].updated_at)
		_set_status("Saved to the cloud.")
	elif not retried and (r.code == 409 or (r.ok and r.data is Array)):
		await _sync_once(true)  # another device saved first (insert clashed, or the update matched nothing)
	else:
		_note_error("upload", r)
		_set_status("Cloud save failed. Will retry." + _last_error)
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
		_busy = true
		await _upload(cloud.updated_at)  # replace exactly the cloud save the player was shown
		_busy = false


# --- Plumbing -------------------------------------------------------------------------------

func _request(method: int, path: String, body: Variant = null, auth := true, extra: PackedStringArray = []) -> Dictionary:
	var http := HTTPRequest.new()
	http.timeout = 20.0
	http.accept_gzip = false  # browsers already unpack compressed replies; Godot unpacking again fails
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


func _note_error(what: String, r: Dictionary) -> void:
	_last_error = " (%s: %s)" % [what, "no connection" if r.code == 0 else "%d %s" % [r.code, _error_text(r)]]


## A signed-in request for other server features (teams): {ok, code, data}.
func api(method: int, path: String, body: Variant = null) -> Dictionary:
	if not enabled() or not signed_in() or not await _ensure_token():
		return {"ok": false, "code": 0, "data": null}
	return await _request(method, path, body)


## A failed request's reason, for people.
func error_text(r: Dictionary) -> String:
	return _error_text(r)


# --- Weekly siege -----------------------------------------------------------------------------

## Queues siege damage from a battle; it's sent with the next sync (kept until you log in).
func siege_add(points: int, pack_name: String) -> void:
	if points <= 0:
		return
	var week := str(GameData.siege_week(Time.get_unix_time_from_system()))
	_siege_pending[week] = int(_siege_pending.get(week, 0)) + points
	_siege_name = pack_name
	_store_state()
	if signed_in():
		_timer.start(UPLOAD_DELAY)


## Damage waiting to be sent for `week`.
func siege_pending(week: int) -> int:
	return int(_siege_pending.get(str(week), 0))


func _send_siege() -> void:
	if _siege_pending.is_empty() or _siege_name == "" or not await _ensure_token():
		return
	for week in _siege_pending.keys():
		var left: int = _siege_pending[week]
		while left > 0:
			var points := mini(left, 2000)
			var r := await _request(HTTPClient.METHOD_POST, "/rest/v1/siege_hits",
				{"week": int(week), "name": _siege_name, "points": points}, true, ["Prefer: return=minimal"])
			if not r.ok:
				_note_error("siege", r)
				_siege_pending[week] = left
				_store_state()
				return
			left -= points
		_siege_pending.erase(week)
		_store_state()


## The week's totals: {"total", "players", "mine", "top": [{"name", "points"}]}, or {} offline.
func siege_board(week: int) -> Dictionary:
	if signed_in() and not await _ensure_token():
		return {}
	var r := await _request(HTTPClient.METHOD_POST, "/rest/v1/rpc/siege_board", {"p_week": week}, signed_in())
	if not r.ok or not r.data is Dictionary:
		_note_error("siege", r)
		return {}
	return r.data


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
	cfg.set_value("cloud", "siege_pending", _siege_pending)
	cfg.set_value("cloud", "siege_name", _siege_name)
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
	_siege_pending = cfg.get_value("cloud", "siege_pending", {})
	_siege_name = cfg.get_value("cloud", "siege_name", "")
