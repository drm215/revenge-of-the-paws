class_name AutoBattle
extends RefCounted

## Plays a whole battle instantly with a "decent player" AI: heal the hurt, taunt when someone's
## low, AoE crowds, focus the weakest. Used by auto mode on the map and by the balance simulator.


## Fights every wave of `cfg` (a Campaign battle/patrol config). Returns {won, xp, downed}.
static func play(profile: Profile, cfg: Dictionary, seed_value := -1) -> Dictionary:
	var battle := Battle.new(profile, cfg.waves, cfg.zombie_mult, cfg.party_mult, cfg.place, seed_value,
		cfg.get("condition", ""), cfg.get("region", ""))
	battle.xp_mult = cfg.get("xp_mult", cfg.zombie_mult)
	battle.start_next_wave()
	var turns := 0
	while turns < 5000:
		var actor := battle.next_turn()
		if actor == null:
			if battle.outcome() == Battle.Outcome.WAVE_CLEARED:
				battle.start_next_wave()
				continue
			break
		var plan := pick_action(battle, actor) if actor.is_player else battle.plan_enemy_action(actor)
		battle.use_skill(actor, plan.skill, plan.target)
		turns += 1
	var fought: Array[String] = []
	for c in battle.party:
		fought.append(c.id)
	return {"won": battle.outcome() == Battle.Outcome.VICTORY, "xp": battle.xp_earned, "downed": battle.downed,
		"fought": fought}


static func pick_action(battle: Battle, actor: Combatant) -> Dictionary:
	var allies := Battle.living(battle.party)
	var foes := Battle.living(battle.enemies)
	var weakest_ally := allies[0]
	for c in allies:
		if c.hp_ratio() < weakest_ally.hp_ratio():
			weakest_ally = c
	var weakest_foe := foes[0]
	for c in foes:
		if c.hp < weakest_foe.hp:
			weakest_foe = c
	var hurt := weakest_ally.hp_ratio() < 0.55 or weakest_ally.has_status("infected")

	var ready: Array[String] = []
	for id in actor.skills:
		if actor.can_use(id):
			ready.append(id)
	for id in ready:
		var s := GameData.skill(id)
		var taunts: bool = s.get("apply", []).any(func(e: Dictionary) -> bool: return e.status == "taunt")
		if s.get("heal", 0.0) > 0.0 and s.target == "ally" and hurt:
			return {"skill": id, "target": weakest_ally}
		if s.get("heal", 0.0) > 0.0 and s.target == "all_allies" and hurt:
			return {"skill": id, "target": actor}
		if s.get("heal", 0.0) > 0.0 and s.target == "self" and actor.hp_ratio() < 0.5:
			return {"skill": id, "target": actor}
		if taunts and weakest_ally != actor and weakest_ally.hp_ratio() < 0.6:
			return {"skill": id, "target": actor}
	for id in ready:
		if GameData.skill(id).target == "all_enemies" and foes.size() >= 2:
			return {"skill": id, "target": weakest_foe}
	var best := actor.skills[0]
	for id in ready:
		var s := GameData.skill(id)
		if s.target == "enemy" and s.get("power", 0.0) > GameData.skill(best).get("power", 0.0):
			best = id
	return {"skill": best, "target": weakest_foe}
