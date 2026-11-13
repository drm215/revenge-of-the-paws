class_name Glossary
extends Control

## The guide: what every stat, status and map term means, in plain words, with the real numbers
## (read from GameData, so it stays true when they change). Opens over whatever screen is showing;
## the zombie guide is one tap away.


var legends: Array[String] = []  # legends found on this map, for the zombie guide


## Shows the guide over `screen`; `found` lists the legends discovered on this map.
static func open(screen: Control, found: Array[String] = []) -> void:
	var guide := Glossary.new()
	guide.legends = found
	guide.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.add_child(guide)


## Sections of [term, meaning], in the order a new player meets them.
static func sections() -> Array:
	var pct := func(x: float) -> String: return "%d%%" % roundi(x * 100)
	return [
		["Stats", [
			["HP", "Health. At 0 an animal is down for the rest of the fight, and after a win it's injured for %d battles (%s less HP and ATK while it heals)." % [GameData.INJURY_BATTLES, pct.call(GameData.INJURY_PENALTY)]],
			["ATK (attack)", "How hard it hits. A move's damage is ATK times the move's Power, cut down by the target's DEF."],
			["DEF (defense)", "Soaks damage: DEF %d halves a hit, and every bit more helps a little less." % roundi(Battle.DEF_SCALE)],
			["SPD (speed)", "Who acts first. Each round goes fastest to slowest; ties go to your pack."],
			["Crit", "The chance a hit lands a critical for x%s damage. Some moves add to it." % str(Battle.CRIT_MULT)],
			["Level", "Every level raises its stats and gives a point for its tech tree. XP comes from zombies you destroy; a retreat keeps %s of it, auto battles %s." % [pct.call(GameData.DEFEAT_XP_SHARE), pct.call(GameData.AUTO_XP_SHARE)]],
		]],
		["Moves", [
			["Power", "How big a move hits compared with a plain attack: Power 140% is 1.4x ATK."],
			["One foe / All foes", "Single-target moves hit one zombie (and can't reach a covered back row); area moves hit every zombie."],
			["Cooldown", "Turns to wait before the move can be used again."],
			["Signature move", "Each animal's own big move, bought in its tech tree."],
			["Hone", "Training with no cap, for points once the tech tree and Training are full: each point is +%s Max HP, Attack and Defense." % pct.call(GameData.HONE_STEP)],
			["+N on a move", "Upgrades bought for it in the tech tree."],
		]],
		["Rows", [
			["Front row", "Takes the hits. While %d or more stand in front, single-target attacks can't reach the back row." % GameData.SCREEN_SIZE],
			["Back row", "Safe from single-target attacks while it's covered, but its own single-target hits are %s softer (birds hit at full strength)." % pct.call(1.0 - GameData.BACK_ROW_DAMAGE), "back_row"],
			["Exposed", "A back-row animal or zombie with fewer than %d in front: anyone can hit it." % GameData.SCREEN_SIZE, "exposed"],
			["Reach", "Runners, birds and flying legends hit the back row anyway; area attacks always do.", "reach"],
		]],
		["Statuses", [
			["Guard", "Braced: a wound-up attack does half damage to it.", "guard"],
			["Taunt", "Draws the zombies' single-target attacks to this animal.", "taunt"],
			["Stunned", "Loses its next turn, and any attack it was winding up is cancelled.", "stunned"],
			["Last Gasp", "At %s HP a legend starts counting down %d of its turns, then hits every animal for %s of their HP. Stuns and Guard don't stop it: kill it first." % [pct.call(GameData.LEGEND_LAST_GASP_AT), GameData.LEGEND_LAST_GASP_TURNS, pct.call(GameData.LEGEND_LAST_GASP_DAMAGE)]],
			["Stun-proof", "A legend that's just been stunned shakes it off: it can't be stunned again on its next %s." % ("turn" if GameData.LEGEND_STUN_PROOF == 1 else "%d turns" % GameData.LEGEND_STUN_PROOF), "stun_proof"],
			["Weakened", "Hits for %s of its usual damage." % pct.call(GameData.WEAKENED_ATK_MULT), "weakened"],
			["Infected", "Loses %s of its max HP at the start of each of its turns. Moves that cure clear it." % pct.call(Battle.INFECTION_DAMAGE), "infected"],
			["Frenzied", "A Screamer's rally: zombies hit %s harder." % pct.call(GameData.FRENZIED_ATK_MULT - 1.0), "frenzied"],
			["Target", "A Brute or a warlord picks its next victim ahead of time (the hurt animal it can reach) and shows it on that animal's card. It follows through unless a Taunt pulls it away.", "target"],
			["Winding up", "A zombie charging a big attack: it lands next turn at x%s. Stun it to cancel, or Guard to halve it." % str(Battle.WINDUP_POWER), "winding"],
			["Enraged", "Past round %d of a wave, zombies gain %s ATK every round." % [Battle.ENRAGE_ROUND, pct.call(Battle.ENRAGE_STEP)]],
		]],
		["Combos", [
			["Opening", "Any crit-boosting move on a stunned zombie is a sure crit."],
			["Follow-up", "+%s damage on the zombie another animal just hit." % pct.call(GameData.FOLLOW_UP_BONUS)],
			["Knockdown", "A heavy hit (Power %s or more) on a weakened zombie stuns it." % pct.call(GameData.KNOCKDOWN_POWER)],
			["Weak spot", "Each zombie type has one: the right kind of animal deals x%s damage to it (see the Zombie guide)." % str(GameData.ZOMBIE_WEAK_MULT), "weak"],
			["Perfect wave", "Clear a wave in %d rounds or fewer and have every animal back at full HP after the rest between waves: the whole pack gets +%s ATK, stacking to +%s, until any animal takes damage." % [GameData.PERFECT_MAX_ROUNDS, pct.call(GameData.PERFECT_ATK_STEP), pct.call(GameData.PERFECT_ATK_STEP * GameData.PERFECT_MAX_STACKS)]],
		]],
		["Your pack", [
			["Leader", "Your own pet leads: allies get +%s ATK and DEF while it stands." % pct.call(GameData.LEADER_AURA)],
			["Roles", "Tank: tough, holds the front. Striker: big damage. Support: heals and helps. Disruptor: stuns and weakens. Bruiser: tough and hits hard."],
			["Bonds", "Animals that fight well together, like 2+ canines or 2+ night animals: each of them gets +%s ATK and DEF." % pct.call(GameData.BOND_BONUS)],
			["Terrain", "Fighting on its own kind of ground (forest, riverside, streets...) gives an animal +%s ATK and DEF. Fighting at home in its own region adds +%s." % [pct.call(GameData.CONDITION_BONUS), pct.call(GameData.HOME_TURF_BONUS)]],
			["Perks", "Bonuses from terrain, bonds, trinkets and the tech tree; the battle log spells them out.", "perks"],
			["Tired", "Each fight in a row costs %s (up to %s) until it sits one out or rests at home." % [pct.call(GameData.FATIGUE_STEP), pct.call(GameData.MAX_FATIGUE)], "tired"],
			["Injured", "Knocked out in a fight: for %d battles it has %s less HP and ATK while it heals." % [GameData.INJURY_BATTLES, pct.call(GameData.INJURY_PENALTY)], "injured"],
			["Bench & duties", "Animals not fighting get %s of the XP and can take a duty: Scout shows every territory's waves, Forage finds the odd bit of XP or a trinket, Guard slows counterattacks." % pct.call(GameData.BENCH_XP_SHARE)],
			["Well rested", "An animal that sits out %d battles in a row comes back well rested for %d fights: +%s ATK and DEF and +%s XP." % [GameData.RESTED_AFTER, GameData.RESTED_BATTLES, pct.call(GameData.RESTED_STATS), pct.call(GameData.RESTED_XP - 1.0)]],
			["Catch-up", "On a team, a pack below the team's strongest earns +%s XP per level behind, up to +%s, from its own fights and sweeps. It fades as the gap closes." % [pct.call(GameData.CATCH_UP_PER_LEVEL), pct.call(GameData.CATCH_UP_MAX)]],
			["Underdog", "On a team, a pack below the team's strongest fights land a stronger teammate opened up as if it had found it itself: zombies matched to its own pack, never the strongest one's."],
			["New animals","Survivors you rescue join at %s of your strongest animal's level, so they need some training." % pct.call(GameData.RECRUIT_LEVEL_SHARE)],
			["Trinkets", "Gear for one animal each: from caches, legends, sieges and dungeons. Equip from Pack."],
			["Upgrade", "Two copies of a trinket make one a tier better, up to +%d: each tier gives +%s more of its bonuses and %s less of its drawbacks. Upgraded trinkets can still be fused." % [GameData.MAX_TRINKET_TIER, pct.call(GameData.TIER_GAIN), pct.call(GameData.TIER_EASE)]],
			["Titles", "Past Lv 50 an animal earns a title every %d levels, from Lv %d: Veteran, Elite, Champion, Legendary, then Mythic. Its name takes the title's color in battle." % [GameData.TITLE_EVERY, GameData.TITLE_FROM]],
		]],
		["The map", [
			["Level", "How strong a territory's zombies are, fixed when you discover it. Only the horde spreading or a lost counter defense raises it."],
			["Threat", "How many waves a territory sends and how nasty the mix. Darker orange is tougher."],
			["Pack strength", "Your pack starts at +%s HP and ATK, and land you hold that's linked to home adds +1%% for every %d territories, up to +%s." % [pct.call(GameData.HELD_BASE_BONUS), GameData.HELD_PER_PERCENT, pct.call(GameData.MAX_HELD_BONUS)]],
			["Rematch", "A legend you've beaten can be fought again from its lair, just for fun: no XP or trinkets, no injuries, and no map turn. On a team you can rematch it as a raid, together."],
			["Counterattack", "Every few turns (the top of the map says how often) the horde tries to retake a territory. Lose the defense and it falls."],
			["Cut off", "Held land no longer linked to home: no strength bonus, no attacks from it, and it falls to the horde in a few turns unless you relink it."],
			["Patrol", "An easier fight in land you hold, for XP."],
			["Sweep all", "Land %d or more levels below your fighting pack falls without a fight, all of it in one tap (and land that opens up as it goes): 1 turn each, no injuries, %s of the XP. It stops if the horde counterattacks. Lairs, warlords and counterattacks are always fought." % [GameData.SWEEP_LEVEL_GAP, pct.call(GameData.SWEEP_XP_SHARE)]],
			["Horde nest", "Where the horde spreads from (a pulsing red blot). Free it to stop the spread."],
			["Warlord", "A named zombie marching from a nest toward your land. Hunt it down for its treasure."],
			["Legend lair", "A cryptid boss in purple. Raid-hard, matched to your pack, with its own trinket."],
			["Dungeon", "Each region's endless waves (a dark doorway on the map). Hold its land to Enter: free, no injuries, treasure for new depths."],
			["Mutation", "Each week (from Monday) changes every territory fight: tougher, slower, swarming zombies, or a boost for some kinds of animals. The top of the map says which."],
			["Week goal", "A goal shared by your team (or just you), bigger for bigger teams. Finish it for a trinket and half a level of XP for every animal in the pack."],
			["Siege", "The weekly fight against a giant swarm: every zombie you destroy wears it down, with rewards at each stage."],
			["Cleared", "Free every ZIP area in a state (or a whole region) for a permanent bonus for one of your animals."],
		]],
	]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP  # nothing underneath reacts while it's open
	var bg := ColorRect.new()
	bg.color = Retro.INK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	margin.add_theme_constant_override("margin_top", 44)
	add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)
	col.add_child(_label("Guide", 20, Retro.GOLD, true))

	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Retro.touch_scroll(scroll)
	col.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 12)
	scroll.add_child(list)
	for section: Array in sections():
		list.add_child(_section(section[0], section[1]))

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	col.add_child(buttons)
	var zombies := Button.new()
	zombies.text = "Zombie guide"
	zombies.custom_minimum_size = Vector2(0, 80)
	zombies.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	zombies.pressed.connect(func() -> void: ZombieGuide.open(self, legends))
	buttons.add_child(zombies)
	var story := Button.new()
	story.text = "Story"
	story.custom_minimum_size = Vector2(0, 80)
	story.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story.pressed.connect(func() -> void: Prologue.play(self))
	buttons.add_child(story)
	var close := Button.new()
	close.text = "Close"
	close.custom_minimum_size = Vector2(0, 80)
	close.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	close.pressed.connect(queue_free)
	buttons.add_child(close)


func _section(title: String, entries: Array) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Retro.box(Retro.NIGHT, Retro.STEEL, Retro.BORDER, 0, 12))
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	box.add_child(_label(title, 15, Retro.GOLD, true))
	for entry: Array in entries:
		var text := RichTextLabel.new()
		text.bbcode_enabled = true
		text.fit_content = true
		text.scroll_active = false
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.mouse_filter = Control.MOUSE_FILTER_IGNORE  # drags scroll the list
		text.add_theme_font_size_override("normal_font_size", Retro.px(18))
		text.add_theme_font_size_override("bold_font_size", Retro.px(18))
		text.add_theme_color_override("default_color", Retro.MIST)
		var icon := CardIcons.texture(entry[2]) if entry.size() > 2 else null
		if icon:
			# The icon a battle card shows for it.
			text.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			text.add_image(icon, 24, 24)
			text.append_text(" ")
		text.append_text("[b][color=#%s]%s[/color][/b]  %s" % [Retro.CYAN.to_html(false), entry[0], entry[1]])
		box.add_child(text)
	return panel


func _label(text: String, font_size: int, color: Color, is_title := false) -> Label:
	var label := Retro.title(Label.new(), font_size, color) if is_title else Retro.text(Label.new(), font_size, color)
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label
