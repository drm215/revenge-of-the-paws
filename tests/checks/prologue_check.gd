extends SceneTree

## The backstory: four short cards that play over setup the first time a new game is started on this
## device (never again after), tap through to the title, and can be replayed from the Guide.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _frames(n: int) -> void:
	for k in n:
		await process_frame


func _run() -> void:
	root.theme = Retro.make_theme()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Prologue.SEEN_PATH))
	_check(not Prologue.seen(), "a new device hasn't seen the story")

	# New game on a new device: the story plays over setup.
	var main: Control = load("res://scripts/ui/main.gd").new()
	main.size = Vector2(720, 1280)
	root.add_child(main)
	await _frames(2)
	var picker: Array = main.find_children("*", "SaveScreen", true, false)
	picker[0].new_game.emit()
	await _frames(2)
	var setup: Array = main.find_children("*", "Onboarding", true, false)
	var story: Array = main.find_children("*", "Prologue", true, false)
	_check(setup.size() == 1 and story.size() == 1 and story[0].get_parent() == setup[0], "a first new game opens with the story, over setup")
	var p: Prologue = story[0]
	_check(Prologue.seen(), "and it's marked seen")
	_check(p.index == 0 and "legends were real" in p.card_text(), "card 1: " + p.card_text())
	var texts: Array[String] = [p.card_text()]
	for k in 7:
		p.tap()  # first tap finishes the typing, the second moves on
		await _frames(1)
		if p.card_text() != texts[-1]:
			texts.append(p.card_text())
	_check(texts.size() == 4 and p.index == 3, "four cards, a tap or two each (%d)" % texts.size())
	_check("pact" in texts[1] and "dog on the porch" in texts[2] and "REVENGE OF THE PAWS" in texts[3], "pact, the animals they never watched, the title")
	_check(texts.all(func(t: String) -> bool: return t.length() < 200), "every card is short")
	p.tap()
	p.tap()
	await create_timer(0.8).timeout
	_check(not is_instance_valid(p) and main.find_children("*", "Onboarding", true, false).size() == 1, "the last tap ends it, and setup is there")

	# Never again on this device.
	main.find_children("*", "Onboarding", true, false)[0].cancelled.emit()
	await _frames(2)
	main.find_children("*", "SaveScreen", true, false)[0].new_game.emit()
	await _frames(2)
	_check(main.find_children("*", "Prologue", true, false).is_empty(), "the next new game skips it")

	# Skip ends it at once.
	var q := Prologue.play(main)
	await _frames(2)
	var skip: Array = q.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Skip")
	skip[0].pressed.emit()
	await create_timer(0.8).timeout
	_check(not is_instance_valid(q), "Skip ends it")

	# The Guide replays it.
	var guide := Glossary.new()
	main.add_child(guide)
	await _frames(2)
	var replay: Array = guide.find_children("*", "Button", true, false).filter(func(b: Button) -> bool: return b.text == "Story")
	replay[0].pressed.emit()
	await _frames(2)
	_check(guide.find_children("*", "Prologue", true, false).size() == 1, "the Guide's Story button plays it again")
	print("%d failure(s)" % _fails)
	quit()
