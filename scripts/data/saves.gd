class_name Saves
extends RefCounted

## Save slots: each game lives in its own folder (DIR/<id>/profile.cfg and campaign.cfg). Choosing
## one points Profile.save_path and Campaign.save_path at it; the save picker lists them.

const DIR := "user://saves"
const PROFILE := "profile.cfg"
const CAMPAIGN := "campaign.cfg"
## A copy of a game kept before a cloud copy replaced it on this device (see back_up).
const BACKUP_PROFILE := "profile.before_download.cfg"
const BACKUP_CAMPAIGN := "campaign.before_download.cfg"


## The one save from before slots becomes the first slot (once).
static func migrate() -> void:
	if not FileAccess.file_exists(Profile.SAVE_PATH):
		return
	var id := new_slot()
	DirAccess.rename_absolute(_abs(Profile.SAVE_PATH), _abs(path(id, PROFILE)))
	if FileAccess.file_exists(Campaign.SAVE_PATH):
		DirAccess.rename_absolute(_abs(Campaign.SAVE_PATH), _abs(path(id, CAMPAIGN)))


## A fresh, empty slot; returns its id.
static func new_slot() -> String:
	var id := "save_%d" % int(Time.get_unix_time_from_system() * 1000.0)
	while DirAccess.dir_exists_absolute(_abs(DIR + "/" + id)):
		id += "x"
	DirAccess.make_dir_recursive_absolute(_abs(DIR + "/" + id))
	return id


## Plays slot `id` from now on (it's created if it doesn't exist yet).
static func use(id: String) -> void:
	DirAccess.make_dir_recursive_absolute(_abs(DIR + "/" + id))
	Profile.save_path = path(id, PROFILE)
	Campaign.save_path = path(id, CAMPAIGN)


static func path(id: String, file: String) -> String:
	return "%s/%s/%s" % [DIR, id, file]


## True if `save_path` is a real slot (tests save elsewhere and must not touch the cloud).
static func is_slot(save_path: String) -> bool:
	return save_path.begins_with(DIR + "/")


## The slot a save path belongs to ("" if it isn't one).
static func slot_of(save_path: String) -> String:
	return save_path.get_base_dir().get_file() if is_slot(save_path) else ""


## Every saved game, most recently played first: [{id, title, detail, played}].
static func list() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dir := DirAccess.open(DIR)
	if dir == null:
		return out
	for id in dir.get_directories():
		var info := describe(id)
		if not info.is_empty():
			out.append(info)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.played > b.played)
	return out


## A slot for the picker: "Jack's pack · Abingdon", "Lv 9 · 12 territories held · turn 41".
static func describe(id: String) -> Dictionary:
	var p := ConfigFile.new()
	if p.load(path(id, PROFILE)) != OK:
		return {}
	var pet := String(p.get_value("profile", "pet_name", ""))
	var town := String(p.get_value("profile", "town", ""))
	var top := 1
	for xp in (p.get_value("profile", "xp", {}) as Dictionary).values():
		top = maxi(top, GameData.level_for_xp(int(xp)))
	var bits: PackedStringArray = ["Lv %d" % top]
	var played := FileAccess.get_modified_time(path(id, PROFILE))
	var c := ConfigFile.new()
	if c.load(path(id, CAMPAIGN)) == OK:
		bits.append("%d territories held" % (c.get_value("campaign", "owned", []) as Array).size())
		bits.append("turn %d" % int(c.get_value("campaign", "turn", 0)))
		played = maxi(played, FileAccess.get_modified_time(path(id, CAMPAIGN)))
	return {"id": id, "title": ("%s's pack" % pet if pet != "" else "Your pack") + (" · " + town if town != "" else ""),
		"detail": " · ".join(bits), "played": played}


## Keeps a copy of slot `id` as it is now, before a cloud copy replaces it (one copy: the latest).
static func back_up(id: String) -> void:
	for pair in [[PROFILE, BACKUP_PROFILE], [CAMPAIGN, BACKUP_CAMPAIGN]]:
		DirAccess.remove_absolute(_abs(path(id, pair[1])))
		if FileAccess.file_exists(path(id, pair[0])):
			DirAccess.copy_absolute(_abs(path(id, pair[0])), _abs(path(id, pair[1])))


## The copy kept before the last download: {"detail", "when"} (unix time), or {} if there isn't one.
static func backup_info(id: String) -> Dictionary:
	var p := ConfigFile.new()
	if p.load(path(id, BACKUP_PROFILE)) != OK:
		return {}
	var top := 1
	for xp in (p.get_value("profile", "xp", {}) as Dictionary).values():
		top = maxi(top, GameData.level_for_xp(int(xp)))
	return {"detail": "best Lv %d" % top, "when": FileAccess.get_modified_time(path(id, BACKUP_PROFILE))}


## Puts back the copy kept before the last download (the caller sends it to the cloud).
static func restore_backup(id: String) -> bool:
	if not FileAccess.file_exists(path(id, BACKUP_PROFILE)):
		return false
	for pair in [[BACKUP_PROFILE, PROFILE], [BACKUP_CAMPAIGN, CAMPAIGN]]:
		if FileAccess.file_exists(path(id, pair[0])):
			DirAccess.remove_absolute(_abs(path(id, pair[1])))
			DirAccess.rename_absolute(_abs(path(id, pair[0])), _abs(path(id, pair[1])))
	return true


## Deletes a slot and everything in it (its cloud copy too).
static func delete(id: String) -> void:
	var had_game := FileAccess.file_exists(path(id, PROFILE))
	for file in [PROFILE, CAMPAIGN, BACKUP_PROFILE, BACKUP_CAMPAIGN]:
		DirAccess.remove_absolute(_abs(path(id, file)))
	DirAccess.remove_absolute(_abs(DIR + "/" + id))
	if had_game:
		SaveHooks.deleted(id)


static func _abs(p: String) -> String:
	return ProjectSettings.globalize_path(p)
