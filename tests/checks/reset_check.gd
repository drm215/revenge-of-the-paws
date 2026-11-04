extends SceneTree

## Checks password reset and email-link sign-in against fake_supabase.py on port 8765.

var _fails := 0


func _check(ok: bool, what: String) -> void:
	print(("ok   " if ok else "FAIL ") + what)
	if not ok:
		_fails += 1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	Profile.save_path = "user://reset_profile.cfg"
	Campaign.save_path = "user://reset_campaign.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Profile.save_path))
	var cloud: Node = root.get_node("Cloud")  # the autoload (off in this build), pointed at the fake
	cloud.state_path = "user://reset_cloud.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(cloud.state_path))
	cloud.base_url = OS.get_environment("FAKE_SUPABASE_URL")
	cloud.anon_key = "anon"
	var asked := [0]
	cloud.reset_requested.connect(func() -> void: asked[0] += 1)

	_check(await cloud.send_reset("a@b.co") == "", "reset email requested")
	await cloud.take_fragment("error=access_denied&error_code=otp_expired&error_description=Email+link+is+invalid+or+has+expired")
	_check(not cloud.signed_in() and "invalid or has expired" in cloud.status and asked[0] == 1, "an expired link explains itself: " + cloud.status)
	await cloud.take_fragment("access_token=wrong&refresh_token=r1&expires_in=3600&type=recovery")
	_check(not cloud.signed_in() and asked[0] == 2, "a bad token doesn't sign in")
	await cloud.take_fragment("access_token=tok-recovery&expires_at=1&expires_in=3600&refresh_token=r1&token_type=bearer&type=recovery")
	_check(cloud.signed_in() and cloud.reset_pending and cloud.email == "a@b.co" and asked[0] == 3, "a reset link signs in and asks for a new password")
	_check(await cloud.set_password("newpass1") == "" and not cloud.reset_pending, "new password saved")
	cloud.log_out()
	_check(await cloud.log_in("a@b.co", "oldpass") != "", "old password no longer works")
	_check(await cloud.log_in("a@b.co", "newpass1") == "" and cloud.signed_in(), "new password logs in")
	cloud.log_out()
	await cloud.take_fragment("access_token=tok-recovery&expires_in=3600&refresh_token=r1&type=signup")
	_check(cloud.signed_in() and not cloud.reset_pending and "confirmed" in cloud.status, "a confirm-email link just signs in")

	var screen := AccountScreen.new()
	cloud.reset_pending = true
	root.add_child(screen)
	var texts: PackedStringArray = []
	for b in screen.find_children("*", "Button", true, false):
		texts.append(b.text)
	_check("Save password" in texts, "account screen shows Save password: " + ", ".join(texts))
	screen.queue_free()
	cloud.log_out()
	screen = AccountScreen.new()
	root.add_child(screen)
	texts.clear()
	for b in screen.find_children("*", "Button", true, false):
		texts.append(b.text)
	_check("Forgot password?" in texts, "logged-out screen offers Forgot password?")
	print("%d failure(s)" % _fails)
	quit(1 if _fails > 0 else 0)
