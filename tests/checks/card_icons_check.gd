extends SceneTree

## Battle cards show statuses, perks and the rest as little icons (with a number or a word where it
## matters) instead of a line of words, and the Guide shows each icon beside its meaning.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = Retro.make_theme()
	var bad: PackedStringArray = []
	for id: String in CardIcons.ART:
		var rows: Array = CardIcons.ART[id]
		if rows.size() != CardIcons.SIZE or not rows.all(func(r: String) -> bool:
				return r.length() == CardIcons.SIZE and Array(r.split("")).all(func(ch: String) -> bool: return ch == "." or CardIcons.PALETTE.has(ch))):
			bad.append(id)
	_check(bad.is_empty(), "every icon is 12x12 in the palette %s" % ", ".join(bad))
	_check(GameData.STATUSES.keys().all(func(s: String) -> bool: return CardIcons.texture(s) != null), "every status has an icon")

	var cat := Combatant.from_data("cat", GameData.PETS["cat"], true)
	cat.statuses["taunt"] = 2
	cat.statuses["guard"] = 2
	cat.notes.append_array(["Forest +15%", "Bond +10%", "Night +15%"])
	var card := UnitCard.new()
	root.add_child(card)
	card.setup(cat, 96)
	card.size = Vector2(330, 200)
	await process_frame
	var words: Array = card.find_children("*", "Label", true, false).map(func(l: Label) -> String: return l.text)
	var icons: Array = card.find_children("*", "TextureRect", true, false).filter(func(t: TextureRect) -> bool: return t.texture is ImageTexture)
	_check(icons.size() == 3, "taunt, guard and perks are icons (%d)" % icons.size())
	_check(not words.any(func(w: String) -> bool: return "Taunt" in w or "Guard" in w or "perk" in w), "and not words: %s" % [words])
	_check(words.has("2") and words.has("3"), "with their turns and the perk count")
	_check(card.status_text() == "+3 perks · Taunt 2 · Guard 2", "the words are still there for the record: " + card.status_text())

	var guide := Glossary.new()
	guide.size = Vector2(720, 1280)
	root.add_child(guide)
	await process_frame
	var guard_line: Array = guide.find_children("*", "RichTextLabel", true, false).filter(func(r: RichTextLabel) -> bool: return r.get_parsed_text().contains("Guard  Braced"))
	_check(guard_line.size() == 1 and guard_line[0].get_parsed_text().length() > 0, "the Guide lists Guard with its icon")
	print("%d failure(s)" % _fails)
	quit()
