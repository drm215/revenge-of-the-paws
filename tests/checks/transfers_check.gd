extends SceneTree

## Critter transfers between teammates (Transfers, server/transfers.sql, mirrored by
## fake_supabase.py). Two players on one team, played in turn by logging in as each: a loan goes
## out, fights for the borrower, comes home stronger with its owner's tree and trinket; a gift
## needs a yes and then is gone for good (a home animal doesn't come back on load); declining or
## taking back an offer returns the critter; one of each kind per pack; leaving the team ends loans.

var _fails := 0
var cloud: Node
var team: Node
var transfers: Node
var pa: Profile  # Ann (u1), Appalachia, with a pet
var pb: Profile  # Bo (u2), Florida
var _url := ""


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _server(path: String) -> Variant:
	var http := HTTPRequest.new()
	root.add_child(http)
	http.request(_url + path)
	var res: Array = await http.request_completed
	http.queue_free()
	return JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())


## Plays as Ann ("a") or Bo ("b"): their login, their save, their view of the transfers.
func _as(who: String) -> Profile:
	cloud.log_out()
	await cloud.log_in("a@b.co" if who == "a" else "b@b.co", "oldpass" if who == "a" else "bpass")
	Profile.save_path = "user://tr_%s_profile.cfg" % who
	var p := pa if who == "a" else pb
	team.use(p.team_id)  # (logging out made the game forget the team)
	transfers.rows = []
	await transfers.refresh()
	transfers.reconcile(p)
	return p


func _settle() -> void:
	for k in 20:
		await process_frame


func _run() -> void:
	_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud = root.get_node("Cloud")
	team = root.get_node("Team")
	transfers = root.get_node("Transfers")
	cloud.state_path = "user://tr_cloud.cfg"
	team.state_path = "user://tr_team.cfg"
	transfers.state_path = "user://tr_transfers.cfg"
	cloud.base_url = _url
	cloud.anon_key = "anon"
	Campaign.save_path = "user://tr_campaign.cfg"

	pa = Profile.new()
	pa.region = "us_appalachia"
	pa.zip = "24210"
	pa.town = "Abingdon"
	pa.pet_species = "dog"
	pa.pet_name = "Peeper"
	pa.team.assign(["black_bear", "horned_owl"])
	pa.unlock(["black_bear", "bobcat", "horned_owl", "whitetail_deer"])
	pa.xp["black_bear"] = GameData.xp_to_reach(20)
	_check(pa.buy_node("black_bear", GameData.tech_tree("black_bear")[0].id), "(Ann's bear has a tech tree node)")
	pa.trinkets.assign(["gator_tooth"])
	pa.equip("black_bear", "gator_tooth")
	pb = Profile.new()
	pb.region = "us_florida"
	pb.zip = "33101"
	pb.town = "Miami"
	pb.team.assign(["alligator", "florida_panther", "blue_heron"])
	pb.unlock(["alligator", "florida_panther", "blue_heron", "armadillo"])

	await _as("a")
	pa.save()
	_check(await team.create(pa) == "", "Ann starts a team")
	var code := String(team.info.code)
	await _as("b")
	pb.save()
	_check(await team.join(code, pb) == "", "Bo joins it")
	var bo_id: String = cloud.user_id()

	# --- A loan ----------------------------------------------------------------------------------
	await _as("a")
	_check(pa.transfer_block("dog") != "", "the pet can't be traded: " + pa.transfer_block("dog"))
	var said: String = await transfers.offer(pa, "black_bear", bo_id, "loan")
	_check(said == "", "Ann offers her bear to Bo on loan " + said)
	_check("black_bear" not in pa.unlocked and "black_bear" not in pa.team and pa.lent.has("black_bear"), "it leaves her pack at once")
	_check(pa.team.size() == pa.locals_needed() and pa.is_complete(), "and her lineup fills the gap: %s" % [pa.team])
	_check(pa.trinkets.is_empty() and not pa.equipped.has("black_bear"), "its trinket goes with it")
	var ann := Profile.load_saved()
	_check(ann != null and "black_bear" not in ann.unlocked, "a home animal that's away doesn't come back on load")
	_check(await transfers.offer(pa, "black_bear", bo_id, "loan") != "", "it can't be offered twice")

	await _as("b")
	var offers: Array = transfers.incoming()
	_check(offers.size() == 1 and offers[0].critter == "black_bear" and transfers.level_in(offers[0]) == 20, "Bo sees the offer (Lv 20)")
	_check("black_bear" not in pb.unlocked, "nothing joins before he answers")
	var screen := TransferScreen.new()
	screen.profile = pb
	screen.size = Vector2(720, 1280)
	root.add_child(screen)
	await process_frame
	var labels := screen.find_children("*", "Button", true, false).map(func(x: Button) -> String: return x.text)
	_check("Accept" in labels and "Decline" in labels, "the Trades screen offers Accept and Decline: %s" % [labels])
	screen.queue_free()
	_check(await transfers.answer(pb, offers[0], true) == "", "Bo accepts")
	_check("black_bear" in pb.unlocked and pb.level_of("black_bear") == 20 and pb.borrowed.has("black_bear"), "the bear joins his pack on loan, Lv 20")
	_check(pb.equipped.get("black_bear", "") == "gator_tooth" and pb.trinkets.is_empty(), "wearing its trinket, which isn't his to use")
	pb.equip("black_bear", "")
	pb.reset_tree("black_bear")
	_check(pb.equipped.get("black_bear", "") == "gator_tooth" and not pb.tree.get("black_bear", []).is_empty(), "he can't change its trinket or tree")
	_check(pb.tree_block("black_bear", GameData.HONE_ID) != "", "or spend its points")
	pb.add_xp("black_bear", GameData.xp_to_reach(26) - int(pb.xp["black_bear"]))
	transfers.reconcile(pb)  # sends its progress
	await _settle()
	var rows: Array = await _server("/_transfers")
	_check(GameData.level_for_xp(int(JSON.parse_string(String(rows[0].data)).xp)) == 26, "its progress reaches the server (Lv 26)")

	await _as("a")
	var news: PackedStringArray = transfers.take_news()
	_check(" ".join(news).contains("took your Black Bear on loan"), "Ann hears Bo took it: %s" % [news])
	var loan: Dictionary = transfers.open_for("black_bear")
	_check(transfers.level_in(loan) == 26, "she sees it's Lv 26 now")

	# The owner still picks its tech tree and trinket while it's away.
	_check(transfers.loan_points(pa, loan) == 24, "its points wait for Ann (%d)" % transfers.loan_points(pa, loan))
	var view: Profile = transfers.loan_view(pa, loan)
	_check(view.level_of("black_bear") == 26 and view.equipped.get("black_bear", "") == "gator_tooth", "she sees it as it is now, Lv 26 with its trinket")
	var second: String = GameData.tech_tree("black_bear")[1].id
	_check(view.buy_node("black_bear", second), "she spends a point on it")
	pa.trinkets.append("miners_lamp")
	_check(await transfers.set_gear(pa, transfers.open_for("black_bear"), view.tree["black_bear"], "miners_lamp") == "", "and swaps its trinket for her spare Miner's Lamp")
	_check(pa.trinkets == ["gator_tooth"], "the Gator Tooth comes back to her, the lamp goes with the bear: %s" % [pa.trinkets])
	_check(await transfers.set_gear(pa, transfers.open_for("black_bear"), view.tree["black_bear"], "cypress_knee_charm") != "",
		"a trinket she has no spare of can't go on it")

	await _as("b")
	news = transfers.take_news()
	_check(" ".join(news).contains("changed their Black Bear"), "Bo's game hears: %s" % [news])
	_check(pb.tree.get("black_bear", []).size() == 2 and pb.equipped.get("black_bear", "") == "miners_lamp" and pb.trinkets.is_empty(),
		"and the bear fights with her picks: %s, %s" % [pb.tree.get("black_bear", []), pb.equipped.get("black_bear", "")])
	pb.add_xp("black_bear", 50)
	transfers.reconcile(pb)  # his progress goes up, and doesn't undo her picks
	await _settle()
	transfers.reconcile(pb)
	_check(pb.tree.get("black_bear", []).size() == 2 and pb.equipped.get("black_bear", "") == "miners_lamp", "his own updates don't undo them")

	await _as("a")
	loan = transfers.open_for("black_bear")
	_check(await transfers.end_loan(pa, loan) == "", "Ann calls it home")
	_check("black_bear" in pa.unlocked and pa.level_of("black_bear") == 26 and not pa.lent.has("black_bear"), "it's back, with the levels it earned (Lv %d)" % pa.level_of("black_bear"))
	_check(pa.equipped.get("black_bear", "") == "miners_lamp" and pa.tree.get("black_bear", []).size() == 2 and pa.trinkets.size() == 2
		and pa.trinkets_free("gator_tooth") == 1, "with the tree and trinket she picked, and her Gator Tooth spare: %s" % [pa.trinkets])

	await _as("b")
	_check("black_bear" not in pb.unlocked and pb.borrowed.is_empty() and not pb.equipped.has("black_bear"), "and gone from Bo's pack")
	_check(pb.is_complete() and pb.trinkets.is_empty(), "his lineup is whole, and the trinket didn't stay")

	# --- A gift ----------------------------------------------------------------------------------
	await _as("a")
	_check(await transfers.offer(pa, "bobcat", bo_id, "gift") == "", "Ann offers her bobcat to keep")
	await _as("b")
	_check(await transfers.answer(pb, transfers.incoming()[0], false) == "", "Bo declines")
	await _as("a")
	_check("bobcat" in pa.unlocked and pa.lent.is_empty(), "the bobcat is back with Ann")
	_check(await transfers.offer(pa, "bobcat", bo_id, "gift") == "", "she offers it again")
	await _as("b")
	_check(await transfers.answer(pb, transfers.incoming()[0], true) == "", "Bo accepts this time")
	_check("bobcat" in pb.unlocked and not pb.borrowed.has("bobcat"), "the bobcat is his for good")
	_check(pb.receive_block("bobcat") != "", "one of each kind: another bobcat can't join: " + pb.receive_block("bobcat"))
	await _as("a")
	_check("bobcat" not in pa.unlocked and "bobcat" in pa.given, "Ann's bobcat is gone")
	pa.save()
	ann = Profile.load_saved()
	_check(ann != null and "bobcat" not in ann.unlocked, "and doesn't come back when her game loads")

	# --- Taking back an offer, and the last animals ------------------------------------------------
	_check(await transfers.offer(pa, "horned_owl", bo_id, "loan") == "", "Ann offers her owl")
	var waiting: Dictionary = transfers.open_for("horned_owl")
	_check(await transfers.cancel(pa, waiting) == "", "and takes it back before Bo answers")
	_check("horned_owl" in pa.unlocked, "the owl stays")
	_check(await transfers.offer(pa, "whitetail_deer", bo_id, "gift") == "", "she gives away her deer")
	_check(pa.transfer_block("horned_owl") != "", "now her lineup needs every animal left: " + pa.transfer_block("horned_owl"))

	# --- Leaving the team ends loans ---------------------------------------------------------------
	await _as("b")
	_check(await transfers.answer(pb, transfers.incoming()[0], false) == "", "(Bo turns the deer down)")
	_check(await transfers.offer(pb, "armadillo", "u1", "loan") == "", "Bo lends Ann his armadillo")
	await _as("a")
	_check(await transfers.answer(pa, transfers.incoming()[0], true) == "", "she takes it")
	_check("armadillo" in pa.unlocked and "whitetail_deer" in pa.unlocked, "it's in her pack (and her deer came home)")
	_check(await team.leave(pa) == "", "Ann leaves the team")
	_check("armadillo" not in pa.unlocked and pa.borrowed.is_empty(), "the armadillo goes home as she leaves")
	await _as("b")
	_check("armadillo" in pb.unlocked and pb.lent.is_empty(), "and it's back with Bo")

	print("%d failure(s)" % _fails)
	quit(1 if _fails else 0)
