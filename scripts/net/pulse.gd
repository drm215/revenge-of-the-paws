extends Node

## The game's one regular check-in while on a team (autoload "Pulse", server/pulse.sql): teammates'
## moves, chat and the team's raid in a single request, every ACTIVE_DELAY seconds. It slows down
## when nobody has touched the screen for a while and stops while the page is hidden, then checks
## at once when the player comes back.

const ACTIVE_DELAY := 12
const IDLE_DELAY := 60
const IDLE_AFTER := 120  # seconds without a touch before slowing down

var pretend_hidden := false  # tests

var _waited := 0  # seconds since the last check-in
var _quiet := 0  # seconds since the last touch
var _away := false  # the page was hidden
var _busy := false
var _old_server := false  # team_pulse isn't on the server yet: ask the old way
var _tags_for := ""  # the team these tags are about
var _team_tag := ""
var _raid_tag := ""
var _timer := Timer.new()


func _ready() -> void:
	_timer.wait_time = 1.0
	_timer.timeout.connect(_tick)
	add_child(_timer)
	_timer.start()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton or event is InputEventKey:
		_quiet = 0


func _hidden() -> bool:
	if pretend_hidden:
		return true
	return OS.has_feature("web") and bool(JavaScriptBridge.eval("document.hidden", true))


func _tick() -> void:
	if _hidden():
		_away = true
		return
	_quiet += 1
	_waited += 1
	if _away:
		_away = false
		_quiet = 0
		check()
	elif _waited >= (IDLE_DELAY if _quiet >= IDLE_AFTER else ACTIVE_DELAY):
		check()


## Checks in now.
func check() -> void:
	_waited = 0
	var cloud := get_node("/root/Cloud")
	var team := get_node("/root/Team")
	var chat := get_node("/root/Chat")
	var raid := get_node("/root/Raid")
	if _busy or team.team_id == "" or not cloud.enabled() or not cloud.signed_in():
		return
	if _old_server:
		team.refresh()
		chat.poll()
		raid.refresh()
		return
	if not team.pending.is_empty():
		team.flush()
	var asked: String = team.team_id
	if asked != _tags_for:
		_tags_for = asked
		_team_tag = ""
		_raid_tag = ""
	_busy = true
	var r: Dictionary = await cloud.api(HTTPClient.METHOD_POST, "/rest/v1/rpc/team_pulse", {"p_team": asked,
		"p_team_tag": _team_tag if not team.info.is_empty() else "",
		"p_raid_tag": _raid_tag if not raid.info.is_empty() else "",
		"p_after": chat.last_id()})
	_busy = false
	if r.code == 404:
		_old_server = true
		return
	if not r.ok or asked != team.team_id:
		return
	if not r.data is Dictionary:
		team.take_pulse(null)  # no longer on this team
		return
	var d: Dictionary = r.data
	# Something that's mid-update ignores this answer; a blank tag asks again next time.
	_team_tag = String(d.team_tag) if d.team == null or team.take_pulse(d.team) else ""
	_raid_tag = String(d.raid_tag) if not d.raid_changed or raid.take_pulse(d.raid) else ""
	chat.take_pulse(d.messages)
