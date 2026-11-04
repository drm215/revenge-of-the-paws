extends Node

## Legend raids (autoload "Raid", server/raids.sql): up to 4 teammates fight a legend live, each
## controlling the 3 critters they bring. Every device runs the same battle from the raid's seed and
## config; only moves travel, numbered in order (the first posted for a number stands). The team's
## raid comes with Pulse's check-ins, and is checked every FAST_POLL seconds while a raid screen is
## open.

## The team's raid (lobby, members, status) changed.
signal changed
## A result that couldn't be sent at the end of the fight (finish_later) got through. `late`:
## {id, outcome, brought, raiders, team}; `stored`: {result, mine}.
signal late_finish(late: Dictionary, stored: Dictionary)
signal _idle

const LATE_RETRY := 15.0  # how often a result that couldn't be sent tries again
const FAST_POLL := 1.5
var turn_timeout := 45.0  # a player who doesn't move in time has that turn played by the AI
var state_path := "user://raid.cfg"
var listening := false  # the game is ready to take a late result (Main, once a map is up)

var info := {}  # team_raid(): {id, host, territory, legend, seed, config, status, result, members}
var fast := false  # a raid screen is open: check often
var holding := false  # a raid battle is on screen: it plays on even if the raid gets called off

var _busy := false
var _waited := 0.0
var _late := {}  # see late_finish; kept on disk until it's sent
var _sending_late := false
var _timer := Timer.new()


func _ready() -> void:
	_timer.wait_time = 0.5
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	var team := get_node_or_null("/root/Team")
	if team:
		team.changed.connect(refresh)
	var cfg := ConfigFile.new()
	if cfg.load(state_path) == OK:
		_late = cfg.get_value("raid", "late", {})
	refresh()


func _tick() -> void:
	_waited += _timer.wait_time
	if _waited >= (FAST_POLL if fast else LATE_RETRY):
		_waited = 0.0
		send_late()
		if fast and not _busy:  # a slow connection doesn't pile up checks
			refresh()


func _cloud() -> Node:
	return get_node_or_null("/root/Cloud")


func _on_team() -> bool:
	var team := get_node_or_null("/root/Team")
	var cloud := _cloud()
	return team != null and team.on_team() and cloud != null and cloud.signed_in()


func my_id() -> String:
	var cloud := _cloud()
	return cloud.user_id() if cloud else ""


## Team-level calls name the team of the game being played.
func _api(fn: String, body: Dictionary) -> Dictionary:
	if fn in ["team_raid", "open_raid", "join_raid", "leave_raid", "start_raid"]:
		body["p_team"] = get_node("/root/Team").team_id
	return await _cloud().api(HTTPClient.METHOD_POST, "/rest/v1/rpc/" + fn, body)


func _error(r: Dictionary) -> String:
	return _cloud().error_text(r)


# --- The team's raid --------------------------------------------------------------------------

## A call while a check is on its way waits for it, then asks again.
func refresh() -> void:
	while _busy:
		await _idle
	if not _on_team():
		_take(null)
		return
	_busy = true
	var asked: String = get_node("/root/Team").team_id
	var r := await _api("team_raid", {})
	if r.ok and asked == get_node("/root/Team").team_id:
		_take(r.data)
	_busy = false
	_idle.emit()


## The team's raid from a check-in (Pulse). False if a check of its own is under way.
func take_pulse(row: Variant) -> bool:
	if _busy:
		return false
	_take(row)
	return true


func _take(row: Variant) -> void:
	var fresh: Dictionary = row if row is Dictionary else {}
	if fresh == info or (holding and fresh.is_empty()):
		return
	info = fresh
	changed.emit()


func status() -> String:
	return String(info.get("status", ""))


func members() -> Array:
	return info.get("members", [])


func is_member(id := "") -> bool:
	var who := id if id != "" else my_id()
	return members().any(func(m: Dictionary) -> bool: return String(m.user_id) == who)


func is_host() -> bool:
	return String(info.get("host", "")) == my_id()


func config() -> Dictionary:
	var c: Variant = JSON.parse_string(String(info.get("config", "")))
	return c if c is Dictionary else {}


func result() -> Dictionary:
	var r: Variant = JSON.parse_string(String(info.get("result", "")))
	return r if r is Dictionary else {}


# --- Lobby ------------------------------------------------------------------------------------

## Opens a raid on a legend's lair, with this player's pack, and tells the team in chat.
func open(territory: String, legend: String, place: String, player_name: String, pack: String) -> String:
	var r := await _api("open_raid", {"p_territory": territory, "p_legend": legend,
		"p_seed": randi(), "p_name": player_name, "p_pack": pack})
	if not r.ok:
		return _error(r)
	_take(r.data)
	var chat := get_node_or_null("/root/Chat")
	if chat:
		chat.send("opened a raid on the %s at %s! Join it from the map." % [GameData.LEGENDS[legend].name, place],
			territory + "@open")
	return ""


## Joins the lobby, or changes the pack brought and whether this player is ready.
func join(player_name: String, pack: String, ready: bool) -> String:
	var r := await _api("join_raid", {"p_name": player_name, "p_pack": pack, "p_ready": ready})
	if not r.ok:
		return _error(r)
	_take(r.data)
	return ""


## Leaves the lobby (the opener leaving calls the raid off).
func leave() -> String:
	var r := await _api("leave_raid", {})
	if not r.ok:
		return _error(r)
	await refresh()
	return ""


## Calls off the team's raid: nobody can finish it (everyone left, or the legend has fallen).
func cancel() -> String:
	if not info.has("id"):
		return ""
	var r := await _api("cancel_raid", {"p_raid": info.id})
	if not r.ok:
		return _error(r)
	await refresh()
	return ""


## The opener starts the fight with everyone ready, fixing the battle `cfg` for all devices.
func start(cfg: Dictionary) -> String:
	var r := await _api("start_raid", {"p_config": JSON.stringify(cfg)})
	if not r.ok:
		return _error(r)
	_take(r.data)
	return ""


# --- The fight --------------------------------------------------------------------------------

## Posts move number `seq`. Returns the move that stands for it ({user_id, action}), which is
## someone else's if they posted first (a timeout takeover); {} if the server can't be reached.
func post(seq: int, action: Dictionary) -> Dictionary:
	var r := await _api("post_raid_action", {"p_raid": info.id, "p_seq": seq, "p_action": JSON.stringify(action)})
	if not r.ok or not r.data is Dictionary:
		return {}
	return _move(r.data)


## Moves numbered after `seq`, in order.
func moves_after(seq: int) -> Array:
	var r := await _api("raid_actions_after", {"p_raid": info.id, "p_after": seq})
	if not r.ok or not r.data is Array:
		return []
	return (r.data as Array).map(_move)


static func _move(row: Dictionary) -> Dictionary:
	var a: Variant = JSON.parse_string(String(row.get("action", "")))
	return {"seq": int(row.get("seq", -1)), "user_id": String(row.get("user_id", "")), "action": a if a is Dictionary else {}}


## Records the end of the fight; the first result posted stands. Returns {result, mine}.
func finish(outcome: Dictionary) -> Dictionary:
	var r := await _api("finish_raid", {"p_raid": info.id, "p_result": JSON.stringify(outcome)})
	if not r.ok or not r.data is Dictionary:
		return {}
	await refresh()
	return _stored(r.data, outcome)


static func _stored(row: Dictionary, outcome: Dictionary) -> Dictionary:
	var stored: Variant = JSON.parse_string(String(row.get("result", "")))
	return {"result": stored if stored is Dictionary else outcome, "mine": bool(row.get("mine", false))}


## The fight is over but the result can't be sent right now: keep it, and send it once back online.
func finish_later(outcome: Dictionary, brought: Array) -> void:
	_late = {"id": String(info.id), "outcome": outcome, "brought": brought, "team": get_node("/root/Team").team_id,
		"raiders": members().map(func(m: Dictionary) -> String: return String(m.user_id))}
	_store_late()


func has_late() -> bool:
	return not _late.is_empty()


## Tries to send a kept result, on the team it belongs to. The server turning it down (rather than
## not answering) means it can never go, so it's dropped.
func send_late() -> void:
	if _late.is_empty() or not listening or _sending_late or not _on_team() or get_node("/root/Team").team_id != String(_late.team):
		return
	_sending_late = true
	var late := _late
	var r := await _api("finish_raid", {"p_raid": late.id, "p_result": JSON.stringify(late.outcome)})
	_sending_late = false
	if r.code == 0:
		return
	_late = {}
	_store_late()
	if r.ok and r.data is Dictionary:
		await refresh()
		late_finish.emit(late, _stored(r.data, late.outcome))


func _store_late() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("raid", "late", _late)
	cfg.save(state_path)
