extends Node

## Cloud saves through Supabase (autoload "Cloud"): email/password accounts via Supabase Auth and
## one row per saved game in the `saves` table (server/supabase.sql), so every game follows the
## player to any device. Sync is automatic and game by game: a save uploads a few seconds later;
## on launch and before uploading, the newer of this device and the cloud wins, a game this device
## doesn't have downloads, and if the same game changed on both the player chooses. Deleting a game
## deletes its cloud copy. Offline play just syncs later.

signal status_changed(text: String)
## A cloud save was written to disk; the game should reload it.
signal downloaded
## The player logged out (teams forget the account's team).
signal signed_out
signal _refreshed(ok: bool)
## The player opened a link from a Supabase email: show the account screen (new password, or why it failed).
signal reset_requested

## Every save syncs right away; this tiny wait gathers the saves of one action into one sync.
const SYNC_DELAY := 0.1
const BATTLE_LOG_KEEP := 30
const RETRY_DELAY := 30.0
## The map warns once the game being played has gone this long without reaching the cloud.
const BACKUP_WARN_MINUTES := 30
## Sync trouble reports (server/sync_events.sql) waiting to be sent: the newest this many.
const SYNC_EVENT_KEEP := 50
## The same trouble (kind, game, error code) is reported at most this often.
const EVENT_REPEAT_SECONDS := 600.0

## Supabase project; tests point this at a fake server (and Profile/Campaign.save_path elsewhere).
var state_path := "user://cloud.cfg"
var base_url := CloudConfig.URL
var anon_key := CloudConfig.ANON_KEY

var email := ""
var status := ""
var last_synced_unix := 0.0
var reset_pending := false  # signed in from a reset link; waiting on a new password

var _access := ""
var _refresh := ""
var _expires_at := 0.0
var _user_id := ""
var _synced := {}  # saved game (slot) -> server updated_at of the cloud copy this device last matched
var _dirty := {}  # saved games changed here since they last synced
var _dirty_since := {}  # saved game -> unix time it first changed without reaching the cloud
var _upload_failed := {}  # saved game -> why its last upload failed (gone once one lands)
var _sync_events: Array = []  # trouble reports not yet sent (see _report)
var _event_seen := {}  # "kind:slot:code" -> unix time last reported
var _deleted: Array = []  # saved games deleted here whose cloud copy still has to go
var _busy := false
var _refreshing := false  # a login refresh is on its way; everyone else waits for its answer
var _again := false  # something changed during a sync: go round once more
var _timer := Timer.new()
var _pending := {}  # the cloud save waiting on a conflict decision
var _siege_pending := {}  # siege week (as text) -> damage not yet sent
var _siege_name := ""
var _battle_logs: Array = []  # battle reports not yet sent (see log_battle)
var _dungeon_records := {}  # region -> {wave, name}: a new deepest wave not yet sent
var _last_error := ""  # why the last request failed, shown after "Offline" so problems can be traced
var _conflict_ui: CanvasLayer


func _ready() -> void:
	_timer.one_shot = true
	_timer.timeout.connect(sync)
	add_child(_timer)
	_load_state()
	SaveHooks.on_saved = mark_dirty
	SaveHooks.on_deleted = forget
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


## Called after every local save (of the game being played).
func mark_dirty() -> void:
	mark_slot_dirty(Saves.slot_of(Profile.save_path))


## Saved game `slot` changed here and has to go up (a restored backup, as well as every save).
func mark_slot_dirty(slot: String) -> void:
	if slot == "":
		return
	if not _dirty.get(slot, false) or not _dirty_since.has(slot):
		_dirty_since[slot] = Time.get_unix_time_from_system()
	_dirty[slot] = true
	_store_state()
	if signed_in():
		_timer.start(SYNC_DELAY)


## How long saved game `slot` (default: the one being played) has had changes the cloud hasn't, in
## minutes (0 when it's backed up).
func unsynced_minutes(slot := "") -> int:
	if slot == "":
		slot = Saves.slot_of(Profile.save_path)
	if not _dirty.get(slot, false) or not _dirty_since.has(slot):
		return 0
	return int((Time.get_unix_time_from_system() - float(_dirty_since[slot])) / 60.0)


## What the map should warn about the game being played ("" when it's safely backed up, or when
## nobody is logged in to back it up to).
func backup_trouble() -> String:
	var slot := Saves.slot_of(Profile.save_path)
	if not signed_in() or slot == "":
		return ""
	if String(_upload_failed.get(slot, "")) != "":
		return "Your game isn't backed up: %s. Tap to try again." % String(_upload_failed[slot]).trim_suffix(".")
	var minutes := unsynced_minutes(slot)
	if minutes >= BACKUP_WARN_MINUTES:
		return "Your game hasn't backed up for %s. Tap to try again." % (("%d minutes" % minutes) if minutes < 120 else ("%d hours" % (minutes / 60)))
	return ""


## Tries to back up again now (the map's warning).
func retry() -> void:
	_timer.stop()
	sync()


## A saved game was deleted here: delete its cloud copy too (now, or once back online).
func forget(slot: String) -> void:
	_dirty.erase(slot)
	_dirty_since.erase(slot)
	_upload_failed.erase(slot)
	_synced.erase(slot)
	if slot not in _deleted:
		_deleted.append(slot)
	_store_state()
	if signed_in():
		_timer.start(SYNC_DELAY)


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
	_synced.clear()
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
	if _refreshing:
		return await _refreshed  # each refresh replaces the token, so only one may run at a time
	_refreshing = true
	var ok := await _refresh_login()
	_refreshing = false
	_refreshed.emit(ok)
	return ok


func _refresh_login() -> bool:
	var token := _refresh
	var r := await _request(HTTPClient.METHOD_POST, "/auth/v1/token?grant_type=refresh_token", {"refresh_token": token}, false)
	if _refresh != token:
		return _access != ""  # logged out or in meanwhile: this answer is about the old login
	if r.ok:
		_take_session(r.data)
		return true
	if r.code == 400 or r.code == 401:
		_report("session_expired", Saves.slot_of(Profile.save_path), r)
		log_out()
		_set_status("Your session expired. Log in again to keep syncing.")
	_note_error("refresh", r)
	return false


# --- Sync -----------------------------------------------------------------------------------

func sync() -> void:
	if not signed_in() or not enabled() or not _pending.is_empty():
		return  # (a waiting conflict syncs again once it's answered)
	if _busy:
		_again = true
		while _busy:
			await get_tree().process_frame
		return
	_busy = true
	_again = true
	while _again and _pending.is_empty():
		_again = false
		await _sync_once()
		await _send_siege()
		await _send_battle_logs()
		await _send_sync_events()
	await _send_dungeon_records()
	_busy = false


## `retried`: this pass follows an upload that lost a race with another device (never loops twice).
func _sync_once(retried := false) -> void:
	if not await _ensure_token():
		if signed_in():
			_set_status("Offline. Will sync when back online." + _last_error)
			_timer.start(RETRY_DELAY)
		return
	var path := "/rest/v1/saves?user_id=eq.%s&select=slot,updated_at" % _user_id
	var r := await _request(HTTPClient.METHOD_GET, path)
	if r.code == 401 or r.code == 403:
		_access = ""  # the database turned the login down: refresh it and try once more
		if await _ensure_token():
			r = await _request(HTTPClient.METHOD_GET, path)
	if not r.ok or not r.data is Array:
		if signed_in():
			_note_error("read", r)
			_report("read", "", r)
			_set_status("Offline. Will sync when back online." + _last_error)
			_timer.start(RETRY_DELAY)
		return
	var cloud := {}  # slot -> updated_at
	for row: Dictionary in r.data:
		cloud[String(row.slot)] = String(row.updated_at)
	# Games deleted here go from the cloud too.
	for slot: String in _deleted.duplicate():
		var d := await _request(HTTPClient.METHOD_DELETE, "/rest/v1/saves?user_id=eq.%s&slot=eq.%s" % [_user_id, slot.uri_encode()])
		if d.ok:
			_deleted.erase(slot)
			cloud.erase(slot)
	_store_state()
	var changed := 0
	for slot: String in cloud:
		if slot in _deleted:
			continue
		var here := FileAccess.file_exists(Saves.path(slot, Saves.PROFILE))
		if here and _synced.get(slot, "") == cloud[slot]:
			if _dirty.get(slot, false):
				await _upload(slot, cloud[slot], retried)
				changed += 1
		elif not here or (not _dirty.get(slot, false) and _synced.has(slot)):
			await _download(slot)  # newer from another device, or a game this device doesn't have yet
			changed += 1
		else:
			# Changed here and in the cloud (or never compared): the same text is no conflict.
			var row := await _fetch(slot)
			if row.is_empty():
				continue
			if String(row.profile) == FileAccess.get_file_as_string(Saves.path(slot, Saves.PROFILE)) \
					and String(row.get("campaign", "")) == _local_campaign(slot):
				_mark_synced(slot, String(row.updated_at))
				continue
			_pending = row
			_report("conflict", slot, {}, {"device": summary(FileAccess.get_file_as_string(Saves.path(slot, Saves.PROFILE)), _local_campaign(slot)),
				"cloud": summary(String(row.profile), String(row.get("campaign", ""))), "cloud_saved": String(row.updated_at)})
			_show_conflict()
			return  # one question at a time; the rest syncs after it's answered
	# Games the cloud doesn't have yet.
	for info: Dictionary in Saves.list():
		var slot := String(info.id)
		if not cloud.has(slot) and (_dirty.get(slot, false) or not _synced.has(slot)):
			await _upload(slot, "", retried)
			changed += 1
	if changed == 0:
		_set_status("Up to date.")


## Uploads saved game `slot` over its cloud copy `expected` ("" = the cloud has none yet). The
## write only lands if the cloud still holds exactly that version, so a copy another device
## uploaded a moment ago is never overwritten: sync looks again instead and offers the choice.
func _upload(slot: String, expected: String, retried := false) -> void:
	var body := {
		"profile": FileAccess.get_file_as_string(Saves.path(slot, Saves.PROFILE)),
		"campaign": _local_campaign(slot),
		"device": OS.get_name(),
	}
	var r: Dictionary
	if expected == "":
		body.user_id = _user_id
		body.slot = slot
		r = await _request(HTTPClient.METHOD_POST, "/rest/v1/saves", body, true, ["Prefer: return=representation"])
	else:
		r = await _request(HTTPClient.METHOD_PATCH, "/rest/v1/saves?user_id=eq.%s&slot=eq.%s&updated_at=eq.%s" % [
			_user_id, slot.uri_encode(), expected.uri_encode()], body, true, ["Prefer: return=representation"])
	if r.ok and r.data is Array and not r.data.is_empty():
		_mark_synced(slot, String(r.data[0].updated_at))
		_set_status("Saved to the cloud.")
		if body.profile != FileAccess.get_file_as_string(Saves.path(slot, Saves.PROFILE)) or body.campaign != _local_campaign(slot):
			mark_slot_dirty(slot)  # saved again while this was on its way
	elif not retried and (r.code == 409 or (r.ok and r.data is Array)):
		_report("upload_race", slot, r, {"expected": expected})
		await _sync_once(true)  # another device saved first (insert clashed, or the update matched nothing)
	else:
		_note_error("upload", r)
		_upload_failed[slot] = "no connection." if r.code == 0 else "%s (%d)" % [_error_text(r), r.code]
		_report("upload", slot, r, {"expected": expected, "retried": retried, "bytes": String(body.profile).length() + String(body.campaign).length()})
		_store_state()
		_set_status("Cloud save failed. Will retry." + _last_error)
		_timer.start(RETRY_DELAY)


## The whole cloud copy of saved game `slot` ({} if it can't be read).
func _fetch(slot: String) -> Dictionary:
	var r := await _request(HTTPClient.METHOD_GET, "/rest/v1/saves?user_id=eq.%s&slot=eq.%s&select=slot,profile,campaign,updated_at" % [
		_user_id, slot.uri_encode()])
	return r.data[0] if r.ok and r.data is Array and not r.data.is_empty() else {}


func _download(slot: String) -> void:
	var row := await _fetch(slot)
	if not row.is_empty():
		_apply(row)


func _local_campaign(slot: String) -> String:
	var file := Saves.path(slot, Saves.CAMPAIGN)
	return FileAccess.get_file_as_string(file) if FileAccess.file_exists(file) else ""


## Writes a cloud copy into its saved game. The game restarts (to the save picker) only if that's
## the game being played, or none is yet.
func _apply(cloud: Dictionary) -> void:
	var slot := String(cloud.get("slot", "")) if String(cloud.get("slot", "")) != "" else _slot_in(String(cloud.profile))
	var active := Saves.slot_of(Profile.save_path)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(Saves.DIR + "/" + slot))
	# Replacing a different copy of this game here: keep that copy first, so it can be put back.
	var local_path := Saves.path(slot, Saves.PROFILE)
	if FileAccess.file_exists(local_path):
		var before := FileAccess.get_file_as_string(local_path)
		if before != String(cloud.profile) or _local_campaign(slot) != String(cloud.get("campaign", "")):
			Saves.back_up(slot)
			_report("download_over", slot, {}, {"before": summary(before, _local_campaign(slot)),
				"after": summary(String(cloud.profile), String(cloud.get("campaign", ""))), "cloud_saved": String(cloud.get("updated_at", ""))})
	_write(Saves.path(slot, Saves.PROFILE), cloud.profile)
	if String(cloud.get("campaign", "")) != "":
		_write(Saves.path(slot, Saves.CAMPAIGN), cloud.campaign)
	else:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(Saves.path(slot, Saves.CAMPAIGN)))
	_mark_synced(slot, String(cloud.updated_at))
	_set_status("Loaded your cloud save.")
	if active == "" or active == slot:
		downloaded.emit()


## The save a cloud copy belongs to, from its profile text ("save_cloud" if it doesn't say).
static func _slot_in(profile_text: String) -> String:
	var cfg := ConfigFile.new()
	if cfg.parse(profile_text) == OK:
		var slot := String(cfg.get_value("profile", "slot", ""))
		if slot != "":
			return slot
	return "save_cloud"


func _mark_synced(slot: String, updated_at: String) -> void:
	_synced[slot] = updated_at
	_dirty.erase(slot)
	_dirty_since.erase(slot)
	_upload_failed.erase(slot)
	last_synced_unix = Time.get_unix_time_from_system()
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
		var top := 0
		for xp in (p.get_value("profile", "xp", {}) as Dictionary).values():
			top = maxi(top, GameData.level_for_xp(int(xp)))
		if top > 0:
			parts.append("best Lv %d" % top)
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
	var slot := String(_pending.slot)
	var local := summary(FileAccess.get_file_as_string(Saves.path(slot, Saves.PROFILE)), _local_campaign(slot))
	body.text = "This game changed on this device and in your cloud save since they last synced.\n\nThis device: %s\nCloud: %s\n\nWhich one do you want to keep? The other is replaced." % [
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
	_report("conflict_choice", String(cloud.slot), {}, {"kept": "cloud" if use_cloud else "device"})
	if use_cloud:
		_apply(cloud)
	else:
		_busy = true
		await _upload(String(cloud.slot), String(cloud.updated_at))  # replace exactly the copy the player was shown
		_busy = false
	sync()  # the other games


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
		_timer.start(SYNC_DELAY)


## Queues a battle report (Battle.report() plus the fight's setup) for the battle log; it goes with
## the sync after the fight is saved, so no download can reload the game on the results screen.
## Only the newest BATTLE_LOG_KEEP wait offline.
func log_battle(report: Dictionary) -> void:
	report["at"] = Time.get_datetime_string_from_system(true)
	var slot := Saves.slot_of(Profile.save_path)
	report["slot"] = slot
	report["signed_in"] = signed_in()
	report["unsynced_minutes"] = unsynced_minutes(slot)
	report["sync_error"] = String(_upload_failed.get(slot, ""))
	_battle_logs.append(report)
	if _battle_logs.size() > BATTLE_LOG_KEEP:
		_battle_logs = _battle_logs.slice(-BATTLE_LOG_KEEP)
	_store_state()


func _send_battle_logs() -> void:
	if _battle_logs.is_empty() or not await _ensure_token():
		return
	while not _battle_logs.is_empty():
		var report: Dictionary = _battle_logs[0]
		var r := await _request(HTTPClient.METHOD_POST, "/rest/v1/battle_logs",
			{"legend": String(report.get("legend", "")), "outcome": String(report.get("outcome", "")),
			"players": int(report.get("players", 1)), "report": report}, true, ["Prefer: return=minimal"])
		if not r.ok:
			_note_error("battle log", r)
			# Too many for now, signed out or no answer: try later. Anything else, the server will
			# never take this one, and it mustn't hold up the rest.
			if r.code == 0 or r.code == 401 or r.code == 403 or r.code == 429 or r.code >= 500:
				return
		_battle_logs.pop_front()
		_store_state()


## Notes sync trouble for the server's sync_events table (sent with the next sync, kept while
## offline): `kind` (read, upload, upload_race, conflict, conflict_choice, download_over,
## session_expired), the saved game, the failed request `r` if any, and what else helps trace it.
func _report(kind: String, slot: String, r := {}, detail := {}) -> void:
	var code := int(r.get("code", 0))
	var key := "%s:%s:%d" % [kind, slot, code]
	var now := Time.get_unix_time_from_system()
	if now - float(_event_seen.get(key, -EVENT_REPEAT_SECONDS)) < EVENT_REPEAT_SECONDS:
		return
	_event_seen[key] = now
	_sync_events.append({"slot": slot, "kind": kind, "code": code,
		"message": (_error_text(r) if not r.is_empty() else "").left(300),
		"detail": detail.merged({"at": Time.get_datetime_string_from_system(true), "device": OS.get_name(),
			"unsynced_minutes": unsynced_minutes(slot) if slot != "" else 0, "signed_in": signed_in()})})
	if _sync_events.size() > SYNC_EVENT_KEEP:
		_sync_events = _sync_events.slice(-SYNC_EVENT_KEEP)
	_store_state()


func _send_sync_events() -> void:
	if _sync_events.is_empty() or not await _ensure_token():
		return
	while not _sync_events.is_empty():
		var r := await _request(HTTPClient.METHOD_POST, "/rest/v1/sync_events", _sync_events[0], true, ["Prefer: return=minimal"])
		if not r.ok:
			# Not now (offline, signed out, too many): later. Anything else won't ever go: drop it.
			if r.code == 0 or r.code == 401 or r.code == 403 or r.code == 429 or r.code >= 500:
				return
		_sync_events.pop_front()
		_store_state()


## A new deepest dungeon wave for the leaderboard; sent with the next sync (kept while offline).
func dungeon_record(region: String, wave: int, pack_name: String) -> void:
	if wave <= int(_dungeon_records.get(region, {}).get("wave", 0)):
		return
	_dungeon_records[region] = {"wave": wave, "name": pack_name}
	_store_state()
	if signed_in():
		_timer.start(SYNC_DELAY)


func _send_dungeon_records() -> void:
	if _dungeon_records.is_empty() or not await _ensure_token():
		return
	for region: String in _dungeon_records.keys():
		var record: Dictionary = _dungeon_records[region]
		var r := await _request(HTTPClient.METHOD_POST, "/rest/v1/rpc/record_dungeon",
			{"p_region": region, "p_wave": int(record.wave), "p_name": String(record.name)})
		if r.ok:
			_dungeon_records.erase(region)
			_store_state()
		else:
			_note_error("dungeon", r)


## The deepest packs in `region`'s dungeon: {"top": [{name, best}], "mine"}, or {} offline.
func dungeon_board(region: String) -> Dictionary:
	if signed_in() and not await _ensure_token():
		return {}
	var r := await _request(HTTPClient.METHOD_POST, "/rest/v1/rpc/dungeon_board", {"p_region": region}, signed_in())
	return r.data if r.ok and r.data is Dictionary else {}


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
	cfg.set_value("cloud", "synced", _synced)
	cfg.set_value("cloud", "last_synced_unix", last_synced_unix)
	cfg.set_value("cloud", "dirty_games", _dirty)
	cfg.set_value("cloud", "dirty_since", _dirty_since)
	cfg.set_value("cloud", "upload_failed", _upload_failed)
	cfg.set_value("cloud", "sync_events", _sync_events)
	cfg.set_value("cloud", "deleted", _deleted)
	cfg.set_value("cloud", "siege_pending", _siege_pending)
	cfg.set_value("cloud", "siege_name", _siege_name)
	cfg.set_value("cloud", "battle_logs", _battle_logs)
	cfg.set_value("cloud", "dungeon_records", _dungeon_records)
	cfg.save(state_path)


func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(state_path) != OK:
		return
	email = cfg.get_value("cloud", "email", "")
	_user_id = cfg.get_value("cloud", "user_id", "")
	_refresh = cfg.get_value("cloud", "refresh", "")
	_synced = cfg.get_value("cloud", "synced", {})  # (games sync one by one now; older state is dropped)
	last_synced_unix = cfg.get_value("cloud", "last_synced_unix", 0.0)
	_dirty = cfg.get_value("cloud", "dirty_games", {})
	_dirty_since = cfg.get_value("cloud", "dirty_since", {})
	_upload_failed = cfg.get_value("cloud", "upload_failed", {})
	_sync_events = cfg.get_value("cloud", "sync_events", [])
	for slot: String in _dirty:  # changed before this was tracked: count from now
		if _dirty[slot] and not _dirty_since.has(slot):
			_dirty_since[slot] = Time.get_unix_time_from_system()
	_deleted = cfg.get_value("cloud", "deleted", [])
	_siege_pending = cfg.get_value("cloud", "siege_pending", {})
	_siege_name = cfg.get_value("cloud", "siege_name", "")
	_battle_logs = cfg.get_value("cloud", "battle_logs", [])
	_dungeon_records = cfg.get_value("cloud", "dungeon_records", {})
