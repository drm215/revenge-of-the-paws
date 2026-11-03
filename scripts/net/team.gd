extends Node

## Teams (autoload "Team", server/teams.sql): up to 4 players share one campaign map built from all
## their homes, each with their own critters. A team belongs to one saved game (Profile.team_id),
## and use() points this at the team of the game being played; a new game starts solo. This
## device's map moves apply locally at once and are queued; flush() replays the queue on the newest
## shared map and saves it only if no teammate saved in between (else it retries on theirs).

## The team or its shared map changed: the map should rebuild.
signal changed
## A server exchange finished (callers waiting their turn go next).
signal _idle

const MAX_MEMBERS := 4
const POLL_DELAY := 20.0
const RETRIES := 4

## Tests point this elsewhere.
var state_path := "user://team.cfg"
var team_id := ""  # the team of the game being played ("" = solo)
var info := {}  # team_info(): {id, code, state, version, members: [{user_id, name, zip}]}; {} = solo
var pending: Array = []  # this device's moves on team_id's map not yet on the server

var _busy := false
var _timer := Timer.new()
var _cache := {}  # team id -> {info, pending}, so switching games keeps unsent moves


func _ready() -> void:
	_load_state()
	_timer.wait_time = POLL_DELAY
	_timer.timeout.connect(func() -> void:
		if on_team() or not pending.is_empty():
			refresh())
	add_child(_timer)
	_timer.start()
	var cloud := _cloud()
	if cloud:
		cloud.signed_out.connect(_forget)


func on_team() -> bool:
	return team_id != "" and not info.is_empty()


## The name teammates see for this player (and on the map at their home).
static func name_for(profile: Profile) -> String:
	return profile.siege_name()


## This player's name on the team, by account (the profile's if the roster doesn't have it).
func my_name(profile: Profile) -> String:
	var cloud := _cloud()
	for m: Dictionary in info.get("members", []):
		if cloud and String(m.get("user_id", "")) == cloud.user_id():
			return String(m.name)
	return name_for(profile)


## Plays the team `id` (a saved game's Profile.team_id; "" for a solo game).
func use(id: String) -> void:
	if id == team_id:
		return
	_stash()
	team_id = id
	var kept: Dictionary = _cache.get(id, {})
	info = kept.get("info", {}) if id != "" else {}
	pending = kept.get("pending", [])
	_store_state()
	changed.emit()
	refresh()


# --- Joining ----------------------------------------------------------------------------------

## Starts a team for the game being played (profile.team_id is set and saved). "" on success.
func create(profile: Profile) -> String:
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/create_team",
		{"p_name": name_for(profile), "p_zip": profile.zip})
	if not r.ok:
		return _cloud().error_text(r)
	_attach(profile, r.data)
	return ""


## Joins a teammate's team by code, for the game being played. "" on success.
func join(code: String, profile: Profile) -> String:
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/join_team",
		{"p_code": code.strip_edges().to_upper(), "p_name": name_for(profile), "p_zip": profile.zip})
	if not r.ok:
		return _cloud().error_text(r)
	_attach(profile, r.data)
	return ""


## Plays one of this account's existing teams (my_teams()) in the game being played.
func bring_back(team: Dictionary, profile: Profile) -> String:
	return await join(String(team.code), profile)


## Leaves the team of the game being played; that game goes back to its solo map.
func leave(profile: Profile) -> String:
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/leave_team", {"p_team": team_id})
	if not r.ok:
		return _cloud().error_text(r)
	_cache.erase(team_id)
	profile.team_id = ""
	profile.save()
	use("")
	return ""


## Every team this account is on: [{id, code, members}] ([] offline).
func my_teams() -> Array:
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/my_teams", {})
	return r.data if r.ok and r.data is Array else []


func _attach(profile: Profile, row: Variant) -> void:
	if not row is Dictionary:
		return
	profile.team_id = String(row.id)
	profile.save()
	use(profile.team_id)
	_take(row)


# --- Sharing the map --------------------------------------------------------------------------

## One of this player's map moves (Campaign._act): queue it and send it.
func record(action: Dictionary) -> void:
	pending.append(action)
	_store_state()
	flush()


## Picks up teammates' moves, or sends ours first if any are waiting.
func refresh() -> void:
	if not _online() or team_id == "":
		return
	if not pending.is_empty():
		await flush()
		return
	while _busy:
		await _idle
	_busy = true
	var asked := team_id
	var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/team_info", {"p_team": asked})
	_done()
	if r.ok and asked == team_id:
		_take(r.data)


## Replays the queued moves on the newest shared map and saves it if nobody saved in between.
## A call while another is sending waits for it, then sends whatever is still queued.
func flush() -> void:
	while _busy:
		await _idle
	if pending.is_empty() or not _online() or team_id == "":
		return
	_busy = true
	var profile := Profile.load_saved()
	var asked := team_id
	for attempt in RETRIES:
		var r: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/team_info", {"p_team": asked})
		if not r.ok or profile == null or asked != team_id:
			break  # offline, or the player switched games: the moves wait for the next try
		if not r.data is Dictionary:
			pending.clear()  # no longer on this team
			_take(null)
			break
		var row: Dictionary = r.data
		var c := Campaign.create(profile, row)
		c.me = my_name(profile)
		c.my_id = _cloud().user_id()
		for action: Dictionary in pending:
			c.apply(action)
		var text := c.to_text()
		var w: Dictionary = await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/save_team_state",
			{"p_team": asked, "p_state": text, "p_version": int(row.version)})
		if w.ok and w.data != null and int(w.data) >= 0:
			row.state = text
			row.version = float(w.data)
			pending.clear()
			info = {}  # so _take sees the change
			_take(row)
			break
		# -1: a teammate saved first; replay on their map
	_done()


func _done() -> void:
	_busy = false
	_idle.emit()


func _take(row: Variant) -> void:
	var fresh: Dictionary = row if row is Dictionary else {}
	if fresh.get("id") == info.get("id") and fresh.get("version") == info.get("version") \
			and fresh.get("members") == info.get("members"):
		return
	info = fresh
	_store_state()
	changed.emit()


func _forget() -> void:
	pending.clear()
	_cache.clear()
	info = {}
	team_id = ""
	_store_state()
	changed.emit()


func _stash() -> void:
	if team_id != "":
		_cache[team_id] = {"info": info, "pending": pending}


func _cloud() -> Node:
	return get_node_or_null("/root/Cloud")


func _online() -> bool:
	var cloud := _cloud()
	return cloud != null and cloud.enabled() and cloud.signed_in()


func _store_state() -> void:
	_stash()
	var cfg := ConfigFile.new()
	cfg.set_value("team", "teams", JSON.stringify(_cache))
	cfg.save(state_path)


func _load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(state_path) != OK:
		return
	var parsed: Variant = JSON.parse_string(cfg.get_value("team", "teams", "{}"))
	_cache = parsed if parsed is Dictionary else {}
