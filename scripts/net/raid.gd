extends Node

## Legend raids (autoload "Raid", server/raids.sql): up to 4 teammates fight a legend live, each
## controlling the 3 critters they bring. Every device runs the same battle from the raid's seed and
## config; only moves travel, numbered in order (the first posted for a number stands). Checks the
## team's raid every IDLE_POLL seconds on a team, and every FAST_POLL while a raid screen is open.

## The team's raid (lobby, members, status) changed.
signal changed

const IDLE_POLL := 15.0
const FAST_POLL := 1.5
var turn_timeout := 45.0  # a player who doesn't move in time has that turn played by the AI

var info := {}  # team_raid(): {id, host, territory, legend, seed, config, status, result, members}
var fast := false  # a raid screen is open: check often

var _busy := false
var _waited := 0.0
var _timer := Timer.new()


func _ready() -> void:
	_timer.wait_time = 0.5
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()
	var team := get_node_or_null("/root/Team")
	if team:
		team.changed.connect(refresh)
	refresh()


func _tick() -> void:
	_waited += _timer.wait_time
	if _waited >= (FAST_POLL if fast else IDLE_POLL):
		_waited = 0.0
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

func refresh() -> void:
	if _busy:
		return
	if not _on_team():
		_take(null)
		return
	_busy = true
	var r := await _api("team_raid", {})
	_busy = false
	if r.ok:
		_take(r.data)


func _take(row: Variant) -> void:
	var fresh: Dictionary = row if row is Dictionary else {}
	if fresh == info:
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
	var stored: Variant = JSON.parse_string(String(r.data.get("result", "")))
	await refresh()
	return {"result": stored if stored is Dictionary else outcome, "mine": bool(r.data.get("mine", false))}
