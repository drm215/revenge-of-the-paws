class_name LegendRecap
extends RefCounted

## Watches a legend fight and keeps its big moments, so the fight can be replayed as a short cut
## scene when it's over (LegendRecapScene), win or lose: the legend's entrance, its phases, its
## Cataclysms and Last Gasp, the biggest blows each way, every animal knocked out, and the end.

const MAX_BEATS := 12  # beats in the replay, besides the entrance and the end
const TOP_HITS := 3  # the pack's biggest hits on the legend that make the cut
const TOP_SMASHES := 2  # the legend's biggest hits on the pack

var battle: Battle
var legend: Combatant  # the first legend seen
var events: Array[Dictionary] = []  # in order: {seq, kind, wave, round, src, dst, amount, crit, skill}
var dealt := {}  # Combatant -> damage it did to the legend
var _seq := 0


func watch(b: Battle) -> void:
	battle = b
	b.damaged.connect(_on_damaged)
	b.died.connect(_on_died)
	b.legend_phase.connect(func(l: Combatant, phase: int) -> void: _add("phase%d" % phase, l, null))
	b.last_gasp.connect(func(l: Combatant, left: int) -> void:
		if left <= 0:
			_add("gasp", l, null))
	b.acting.connect(func(actor: Combatant) -> void:
		if actor.is_boss and actor.winding == "cataclysm":
			_add("cataclysm", actor, null))
	b.log_message.connect(func(text: String) -> void:
		if legend and "Cataclysm is interrupted" in text:
			_add("interrupt", legend, null))


## Whether this fight had a legend in it (and so a replay).
func has_legend() -> bool:
	if legend == null and battle:
		_fighting_legend()
	return legend != null


func _fighting_legend() -> bool:
	if legend == null:
		for z in battle.enemies:
			if z.is_boss:
				legend = z
	return legend != null and legend in battle.enemies


func _add(kind: String, src: Combatant, dst: Combatant, amount := 0, crit := false) -> Dictionary:
	_seq += 1
	var e := {"seq": _seq, "kind": kind, "wave": battle.wave_index, "round": battle.round_number,
		"src": src, "dst": dst, "amount": amount, "crit": crit, "skill": battle.last_skill}
	events.append(e)
	return e


func _on_damaged(target: Combatant, amount: int, crit: bool) -> void:
	if not _fighting_legend():
		return
	var src := battle.current
	if target.is_boss and src and src.is_player:
		dealt[src] = int(dealt.get(src, 0)) + amount
		_add("hit", src, target, amount, crit)
	elif target.is_player and src and src.is_boss:
		_add("smash", src, target, amount, crit)


func _on_died(c: Combatant) -> void:
	if not _fighting_legend():
		return
	if c.is_player:
		_add("ko", battle.current, c)
	elif c.is_boss:
		_add("final", battle.current, c)


## The animal that did the most to the legend: {who, damage} ({} if nobody hit it).
func mvp() -> Dictionary:
	var best: Combatant = null
	for c: Combatant in dealt:
		if best == null or int(dealt[c]) > int(dealt[best]):
			best = c
	return {} if best == null else {"who": best, "damage": int(dealt[best])}


## The moments worth replaying, in order: every turn of the story, plus the biggest blows.
func beats() -> Array[Dictionary]:
	var keep: Array[Dictionary] = []
	var hits: Array[Dictionary] = []
	var smashes: Array[Dictionary] = []
	for e in events:
		match e.kind:
			"hit":
				hits.append(e)
			"smash":
				smashes.append(e)
			_:
				keep.append(e)
	hits.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.amount > b.amount)
	smashes.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.amount > b.amount)
	keep.append_array(hits.slice(0, TOP_HITS))
	keep.append_array(smashes.slice(0, TOP_SMASHES))
	# Too many: drop the smaller blows first, then the earliest knockouts.
	while keep.size() > MAX_BEATS:
		var drop := -1
		for k in range(keep.size() - 1, -1, -1):
			if keep[k].kind in ["hit", "smash"]:
				drop = k
				break
		if drop < 0:
			for k in keep.size():
				if keep[k].kind == "ko":
					drop = k
					break
		if drop < 0:
			drop = 0
		keep.remove_at(drop)
	keep.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.seq < b.seq)
	return keep
