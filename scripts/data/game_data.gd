class_name GameData
extends RefCounted

## Static game content. Move to Resources (.tres) once there's enough of it to want an editor.
##
## Skill fields:
##   base      inherit every field from another skill, then override (used for flavor renames)
##   target    "enemy" | "all_enemies" | "ally" | "all_allies" | "self"  (relative to the user)
##   power     damage multiplier on ATK (0 = no damage)
##   heal      fraction of target max HP restored
##   cleanse   removes Infected
##   cooldown  own turns to wait before reuse
##   apply     statuses put on each target: [{status, turns, chance}]

const PARTY_SIZE := 3

## Pets lead the pack: their stats are multiplied, and every other living ally gets the aura bonus.
const PET_STAT_MULT := 1.15
const LEADER_AURA := 0.10
const WEAKENED_ATK_MULT := 0.7

const SKILLS := {
	# --- Basic attacks ---
	"bite": {"name": "Bite", "desc": "A solid chomp.", "target": "enemy", "power": 1.0},
	"scratch": {"name": "Scratch", "desc": "Quick claws.", "target": "enemy", "power": 1.0},
	"peck": {"name": "Peck", "desc": "A sharp jab.", "target": "enemy", "power": 1.0},
	"kick": {"name": "Kick", "desc": "A powerful kick.", "target": "enemy", "power": 1.0},
	"headbutt": {"name": "Headbutt", "desc": "Skull meets skull.", "target": "enemy", "power": 1.0},
	"nibble": {"base": "bite", "name": "Nibble", "desc": "Tiny teeth, big attitude."},

	# --- Heavy hits ---
	"maul": {"name": "Maul", "desc": "Heavy shake attack.", "target": "enemy", "power": 1.5, "cooldown": 2},
	"tail_slam": {"base": "maul", "name": "Tail Slam", "desc": "An armored tail to the face."},
	"charge": {"base": "maul", "name": "Charge", "desc": "Full-speed body slam."},
	"pounce": {
		"name": "Pounce", "desc": "Huge hit, high crit chance.",
		"target": "enemy", "power": 1.7, "crit_bonus": 0.25, "cooldown": 2,
	},
	"boxing_flurry": {"base": "pounce", "name": "Boxing Flurry", "desc": "A flurry of punches, high crit chance."},
	"dive": {
		"name": "Dive", "desc": "Plunge from above.",
		"target": "enemy", "power": 1.6, "crit_bonus": 0.1, "cooldown": 2,
	},
	"gore": {
		"name": "Gore", "desc": "Heavy hit that may stun.",
		"target": "enemy", "power": 1.3, "cooldown": 3,
		"apply": [{"status": "stunned", "turns": 1, "chance": 0.35}],
	},
	"thump": {"base": "gore", "name": "Thump", "desc": "Stomp hard enough to stun."},
	"rolling_charge": {"base": "gore", "name": "Rolling Charge", "desc": "Roll into them; may stun."},

	# --- Area attacks ---
	"shadow_swipe": {
		"name": "Shadow Swipe", "desc": "Hit every zombie.",
		"target": "all_enemies", "power": 0.6, "cooldown": 3,
	},
	"frenzy": {"base": "shadow_swipe", "name": "Frenzy", "desc": "Tear into every zombie."},
	"dust_devil": {"base": "shadow_swipe", "name": "Dust Devil", "desc": "Whirl through every zombie."},
	"wheel_frenzy": {"base": "shadow_swipe", "name": "Wheel Frenzy", "desc": "Years of wheel cardio, unleashed."},
	"stampede": {
		"name": "Stampede", "desc": "Trample every zombie.",
		"target": "all_enemies", "power": 0.7, "cooldown": 3,
	},
	"prickle_roll": {"base": "stampede", "name": "Prickle Roll", "desc": "Roll spines-first through the horde."},
	"tail_whip": {"base": "stampede", "name": "Tail Whip", "desc": "Sweep every zombie."},
	"screech": {
		"name": "Screech", "desc": "Hit all zombies; may stun.",
		"target": "all_enemies", "power": 0.5, "cooldown": 3,
		"apply": [{"status": "stunned", "turns": 1, "chance": 0.35}],
	},
	"squawk": {"base": "screech", "name": "Squawk"},
	"murder_call": {"base": "screech", "name": "Murder Call", "desc": "Summon the flock; may stun."},
	"alarm_call": {"base": "screech", "name": "Alarm Call"},
	"shriek": {"base": "screech", "name": "Shriek"},
	"laughing_call": {"base": "screech", "name": "Laughing Call", "desc": "Unsettling laughter; may stun."},

	# --- Taunts & defense ---
	"guard_bark": {
		"name": "Guard Bark", "desc": "Taunt all zombies and brace (DEF up).",
		"target": "self", "cooldown": 3,
		"apply": [{"status": "taunt", "turns": 2}, {"status": "guard", "turns": 2}],
	},
	"roar": {"base": "guard_bark", "name": "Roar"},
	"snarl": {"base": "guard_bark", "name": "Snarl"},
	"hiss": {"base": "guard_bark", "name": "Hiss"},
	"fearless": {"base": "guard_bark", "name": "Fearless", "desc": "Pick a fight with everything (taunt, DEF up)."},
	"bum_block": {"base": "guard_bark", "name": "Bum Block", "desc": "Plug the gap with an armored rump (taunt, DEF up)."},
	"curl_up": {
		"base": "guard_bark", "name": "Curl Up", "desc": "Roll into an armored ball (taunt, long DEF up).",
		"apply": [{"status": "taunt", "turns": 2}, {"status": "guard", "turns": 3}],
	},
	"play_dead": {
		"name": "Play Dead", "desc": "Heal 25% and brace (DEF up).",
		"target": "self", "heal": 0.25, "cooldown": 3,
		"apply": [{"status": "guard", "turns": 2}],
	},
	"bask": {"base": "play_dead", "name": "Bask", "desc": "Soak up the sun: heal 25% and brace."},
	"wallow": {"base": "play_dead", "name": "Wallow", "desc": "A relaxing mud bath: heal 25% and brace."},
	"bellow": {"base": "guard_bark", "name": "Bellow"},
	"stand_firm": {"base": "guard_bark", "name": "Stand Firm"},
	"death_roll": {"base": "gore", "name": "Death Roll", "desc": "Grab and spin; may stun."},
	"antler_charge": {"base": "gore", "name": "Antler Charge", "desc": "Antlers first; may stun."},
	"trample": {"base": "stampede", "name": "Trample"},
	"belly_slide": {"base": "stampede", "name": "Belly Slide", "desc": "Slide through every zombie."},
	"pack_hunt": {"base": "shadow_swipe", "name": "Pack Hunt", "desc": "Call the pack: hit every zombie."},
	"bugle": {"base": "screech", "name": "Bugle", "desc": "Ear-splitting call; may stun."},
	"honk": {"base": "screech", "name": "Honk"},
	"rock_smash": {"base": "dirty_trick", "name": "Rock Smash", "desc": "Bonk with a favorite rock; weakens."},

	# --- Support ---
	"mend": {
		"name": "Mend", "desc": "Heal an ally 30% and cure infection.",
		"target": "ally", "heal": 0.3, "cleanse": true, "cooldown": 1,
	},
	"groom": {"base": "mend", "name": "Groom"},
	"preen": {"base": "mend", "name": "Preen"},
	"huddle": {"base": "mend", "name": "Huddle"},
	"scavenge": {"base": "mend", "name": "Scavenge", "desc": "Share found scraps: heal an ally 30%, cure infection."},
	"snack_stash": {"base": "mend", "name": "Snack Stash", "desc": "Cheek-pouch snacks: heal an ally 30%, cure infection."},
	"chill_vibes": {
		"name": "Chill Vibes", "desc": "Heal every ally 15% and cure infection.",
		"target": "all_allies", "heal": 0.15, "cleanse": true, "cooldown": 3,
	},
	"spray": {
		"name": "Spray", "desc": "Douse every zombie; weakens them (ATK down).",
		"target": "all_enemies", "power": 0.4, "cooldown": 3,
		"apply": [{"status": "weakened", "turns": 2}],
	},
	"dirty_trick": {
		"name": "Dirty Trick", "desc": "Hit and weaken a zombie (ATK down).",
		"target": "enemy", "power": 0.8, "cooldown": 2,
		"apply": [{"status": "weakened", "turns": 2}],
	},
	"venom_spur": {
		"name": "Venom Spur", "desc": "Venomous jab; may weaken.",
		"target": "enemy", "power": 1.2, "cooldown": 2,
		"apply": [{"status": "weakened", "turns": 2, "chance": 0.5}],
	},

	# --- Signature skills (learned at SIGNATURE_LEVEL; each animal shows its own name) ---
	"last_stand": {
		"name": "Last Stand", "desc": "Dig in: taunt, heavy guard and heal 20%.",
		"target": "self", "heal": 0.2, "cooldown": 4,
		"apply": [{"status": "taunt", "turns": 3}, {"status": "guard", "turns": 3}],
	},
	"finishing_blow": {
		"name": "Finishing Blow", "desc": "A devastating strike.",
		"target": "enemy", "power": 2.2, "crit_bonus": 0.2, "cooldown": 3,
	},
	"rally": {
		"name": "Rally", "desc": "Heal the whole pack 20% and cure infection.",
		"target": "all_allies", "heal": 0.2, "cleanse": true, "cooldown": 4,
	},
	"hex_cloud": {
		"name": "Hex Cloud", "desc": "Weaken every zombie; may stun.",
		"target": "all_enemies", "power": 0.6, "cooldown": 4,
		"apply": [{"status": "weakened", "turns": 3}, {"status": "stunned", "turns": 1, "chance": 0.25}],
	},
	"stampede_charge": {
		"name": "Stampede Charge", "desc": "Plow through every zombie.",
		"target": "all_enemies", "power": 0.9, "cooldown": 3,
	},

	# --- Zombies ---
	"claw": {"name": "Claw", "desc": "", "target": "enemy", "power": 1.0},
	"infectious_bite": {
		"name": "Infectious Bite", "desc": "", "target": "enemy", "power": 0.8, "cooldown": 2,
		"apply": [{"status": "infected", "turns": 3, "chance": 0.6}],
	},
	"lunge": {"name": "Lunge", "desc": "", "target": "enemy", "power": 0.9, "crit_bonus": 0.15},
	"slam": {"name": "Slam", "desc": "", "target": "enemy", "power": 1.1},
	"smash": {"name": "Smash", "desc": "", "target": "enemy", "power": 1.4},
	"rampage": {"name": "Rampage", "desc": "", "target": "all_enemies", "power": 0.8, "cooldown": 3},
	"plague_spit": {
		"name": "Plague Spit", "desc": "", "target": "all_enemies", "power": 0.4, "cooldown": 2,
		"apply": [{"status": "infected", "turns": 3, "chance": 0.7}],
	},
	"scream": {
		"name": "Scream", "desc": "", "target": "all_enemies", "power": 0.3, "cooldown": 2,
		"apply": [{"status": "stunned", "turns": 1, "chance": 0.4}],
	},

	# --- Legends (bosses). The first skill in each kit must have no cooldown. ---
	"rend": {"base": "smash", "name": "Rend", "desc": "A brutal strike on one animal."},
	"wing_buffet": {"base": "smash", "name": "Wing Buffet", "desc": "Batters one animal with huge wings."},
	"tree_toss": {"base": "smash", "name": "Tree Toss", "desc": "Hurls a whole tree at one animal."},
	"heat_ray": {"base": "smash", "name": "Heat Ray", "desc": "A searing beam at one animal."},
	"axe_swing": {"base": "smash", "name": "Axe Swing", "desc": "A heavy axe blow on one animal."},
	"horn_gore": {"base": "smash", "name": "Horn Gore", "desc": "Gores one animal with its horns."},
	"lake_bite": {"base": "smash", "name": "Lake Bite", "desc": "Huge jaws snap at one animal."},
	"spindly_claw": {"base": "smash", "name": "Spindly Claw", "desc": "Long fingers rake one animal."},
	"trestle_charge": {"base": "smash", "name": "Trestle Charge", "desc": "Charges one animal like a freight train."},
	"stomp": {"base": "rampage", "name": "Stomp", "desc": "Shakes the ground under your whole pack."},
	"tail_lash": {"base": "rampage", "name": "Tail Lash", "desc": "Sweeps its tail across your whole pack."},
	"avalanche": {"base": "rampage", "name": "Avalanche", "desc": "Buries your whole pack in rock."},
	"omen": {
		"name": "Omen", "desc": "Dread falls on your pack: hits all, may weaken (ATK down).", "target": "all_enemies", "power": 0.4, "cooldown": 3,
		"apply": [{"status": "weakened", "turns": 2, "chance": 0.7}],
	},
	"howl": {"base": "omen", "name": "Bone-chilling Howl", "desc": "A chilling howl: hits all, may weaken (ATK down)."},
	"stench": {"base": "omen", "name": "Stench", "desc": "A choking stink: hits all, may weaken (ATK down)."},
	"red_gaze": {
		"name": "Red Gaze", "desc": "Glowing eyes freeze your pack: hits all, may stun.", "target": "all_enemies", "power": 0.5, "cooldown": 4,
		"apply": [{"status": "stunned", "turns": 1, "chance": 0.5}],
	},
	"hellish_shriek": {"base": "red_gaze", "name": "Hellish Shriek", "desc": "An ear-splitting shriek: hits all, may stun."},
	"toxic_mist": {
		"name": "Toxic Mist", "desc": "Poison fog: hits all, may infect.", "target": "all_enemies", "power": 0.4, "cooldown": 3,
		"apply": [{"status": "infected", "turns": 3, "chance": 0.6}],
	},
	"shadow_pounce": {"name": "Shadow Pounce", "desc": "A huge leap with a high critical-hit chance.", "target": "enemy", "power": 1.6, "crit_bonus": 0.3, "cooldown": 2},
	"blood_drain": {"base": "infectious_bite", "name": "Blood Drain", "power": 1.2, "desc": "A draining bite that may infect."},
}

const STATUSES := {
	"taunt": {"name": "Taunt"},
	"guard": {"name": "Guard"},
	"infected": {"name": "Infected"},
	"stunned": {"name": "Stunned"},
	"weakened": {"name": "Weakened"},
}

## Real-life pets the player can bring. They get PET_STAT_MULT and lead with LEADER_AURA.
const PETS := {
	"dog": {
		"name": "Dog", "role": "Tank", "desc": "Loyal guardian.", "color": Color("c98b4f"),
		"hp": 120, "atk": 14, "def": 12, "spd": 8, "crit": 0.05,
		"skills": ["bite", "guard_bark", "maul"],
	},
	"cat": {
		"name": "Cat", "role": "Striker", "desc": "Reckless, deadly pouncer.", "color": Color("8a8f99"),
		"hp": 80, "atk": 18, "def": 6, "spd": 14, "crit": 0.2,
		"skills": ["scratch", "pounce", "shadow_swipe"],
	},
	"bird": {
		"name": "Bird", "role": "Support", "desc": "Heals friends, deafens foes.", "color": Color("5fb3a1"),
		"hp": 70, "atk": 10, "def": 5, "spd": 12, "crit": 0.05,
		"skills": ["peck", "preen", "squawk"],
	},
	"rabbit": {
		"name": "Rabbit", "role": "Striker", "desc": "Fast feet, stunning stomp.", "color": Color("d8cfc0"),
		"hp": 78, "atk": 16, "def": 6, "spd": 16, "crit": 0.15,
		"skills": ["kick", "thump", "frenzy"],
	},
	"lizard": {
		"name": "Lizard", "role": "Tank", "desc": "Scaly, sun-powered wall.", "color": Color("7fa650"),
		"hp": 110, "atk": 13, "def": 13, "spd": 8, "crit": 0.05,
		"skills": ["bite", "bask", "tail_whip"],
	},
	"hamster": {
		"name": "Hamster", "role": "Support", "desc": "Tiny. Furious. Snacks.", "color": Color("e0a96d"),
		"hp": 65, "atk": 10, "def": 6, "spd": 13, "crit": 0.1,
		"skills": ["nibble", "snack_stash", "wheel_frenzy"],
	},
}

## Wild animals, grouped by home region in REGIONS.
const ANIMALS := {
	# North America – East
	"raccoon": {
		"name": "Raccoon", "role": "Striker", "desc": "Clever hands, sharper claws.", "color": Color("7d7f86"),
		"hp": 80, "atk": 18, "def": 6, "spd": 13, "crit": 0.15,
		"skills": ["scratch", "pounce", "frenzy"],
	},
	"opossum": {
		"name": "Opossum", "role": "Tank", "desc": "Too stubborn to stay dead.", "color": Color("c9c2b8"),
		"hp": 125, "atk": 12, "def": 11, "spd": 8, "crit": 0.05,
		"skills": ["bite", "hiss", "play_dead"],
	},
	"horned_owl": {
		"name": "Horned Owl", "role": "Support", "desc": "Sees everything, heals the pack.", "color": Color("a7865c"),
		"hp": 70, "atk": 10, "def": 5, "spd": 11, "crit": 0.05,
		"skills": ["peck", "mend", "screech"],
	},
	"skunk": {
		"name": "Skunk", "role": "Disruptor", "desc": "Weakens the whole horde.", "color": Color("3a3a3a"),
		"hp": 95, "atk": 14, "def": 8, "spd": 10, "crit": 0.05,
		"skills": ["bite", "spray", "maul"],
	},
	# North America – West
	"coyote": {
		"name": "Coyote", "role": "Striker", "desc": "Hunts in the dust.", "color": Color("b8935a"),
		"hp": 82, "atk": 18, "def": 6, "spd": 13, "crit": 0.15,
		"skills": ["bite", "pounce", "frenzy"],
	},
	"black_bear": {
		"name": "Black Bear", "role": "Tank", "desc": "A wall of fur and fury.", "color": Color("2f2a26"),
		"hp": 135, "atk": 15, "def": 12, "spd": 6, "crit": 0.05,
		"skills": ["scratch", "roar", "maul"],
	},
	"roadrunner": {
		"name": "Roadrunner", "role": "Striker", "desc": "Fastest thing in the wasteland.", "color": Color("8c7a5b"),
		"hp": 70, "atk": 15, "def": 5, "spd": 17, "crit": 0.2,
		"skills": ["peck", "dive", "dust_devil"],
	},
	"turkey_vulture": {
		"name": "Turkey Vulture", "role": "Support", "desc": "Knows where the scraps are.", "color": Color("5b4040"),
		"hp": 75, "atk": 10, "def": 6, "spd": 10, "crit": 0.05,
		"skills": ["peck", "scavenge", "screech"],
	},
	# Europe
	"red_fox": {
		"name": "Red Fox", "role": "Striker", "desc": "Cunning and quick.", "color": Color("d0682f"),
		"hp": 78, "atk": 18, "def": 6, "spd": 14, "crit": 0.2,
		"skills": ["bite", "pounce", "dirty_trick"],
	},
	"badger": {
		"name": "Badger", "role": "Tank", "desc": "Dug in and furious.", "color": Color("6e6e6e"),
		"hp": 125, "atk": 15, "def": 13, "spd": 7, "crit": 0.05,
		"skills": ["bite", "snarl", "maul"],
	},
	"hedgehog": {
		"name": "Hedgehog", "role": "Tank", "desc": "A pincushion that bites back.", "color": Color("8f7558"),
		"hp": 95, "atk": 14, "def": 14, "spd": 9, "crit": 0.05,
		"skills": ["nibble", "curl_up", "prickle_roll"],
	},
	"crow": {
		"name": "Crow", "role": "Support", "desc": "Never flies alone.", "color": Color("262833"),
		"hp": 70, "atk": 11, "def": 5, "spd": 12, "crit": 0.05,
		"skills": ["peck", "scavenge", "murder_call"],
	},
	# Latin America
	"jaguar": {
		"name": "Jaguar", "role": "Striker", "desc": "Jungle apex predator.", "color": Color("d9a441"),
		"hp": 88, "atk": 19, "def": 7, "spd": 13, "crit": 0.2,
		"skills": ["bite", "pounce", "maul"],
	},
	"armadillo": {
		"name": "Armadillo", "role": "Tank", "desc": "Built-in armor plating.", "color": Color("9a8a78"),
		"hp": 115, "atk": 12, "def": 14, "spd": 7, "crit": 0.05,
		"skills": ["scratch", "curl_up", "rolling_charge"],
	},
	"capybara": {
		"name": "Capybara", "role": "Support", "desc": "Everyone's calm around a capybara.", "color": Color("9b6b43"),
		"hp": 85, "atk": 9, "def": 7, "spd": 8, "crit": 0.05,
		"skills": ["bite", "chill_vibes", "wallow"],
	},
	"toucan": {
		"name": "Toucan", "role": "Striker", "desc": "That beak isn't just for show.", "color": Color("f08a24"),
		"hp": 72, "atk": 14, "def": 5, "spd": 12, "crit": 0.1,
		"skills": ["peck", "dive", "squawk"],
	},
	# Africa
	"lioness": {
		"name": "Lioness", "role": "Striker", "desc": "Leads every hunt.", "color": Color("c9a066"),
		"hp": 90, "atk": 18, "def": 7, "spd": 12, "crit": 0.15,
		"skills": ["bite", "pounce", "frenzy"],
	},
	"honey_badger": {
		"name": "Honey Badger", "role": "Tank", "desc": "Doesn't care. Never did.", "color": Color("4b4b4b"),
		"hp": 115, "atk": 14, "def": 12, "spd": 9, "crit": 0.05,
		"skills": ["bite", "fearless", "maul"],
	},
	"meerkat": {
		"name": "Meerkat", "role": "Support", "desc": "Always on lookout.", "color": Color("c4a27a"),
		"hp": 65, "atk": 10, "def": 5, "spd": 13, "crit": 0.05,
		"skills": ["bite", "huddle", "alarm_call"],
	},
	"warthog": {
		"name": "Warthog", "role": "Bruiser", "desc": "Tusks first, questions never.", "color": Color("7a5c4d"),
		"hp": 105, "atk": 14, "def": 9, "spd": 9, "crit": 0.05,
		"skills": ["headbutt", "gore", "stampede"],
	},
	# Asia
	"tiger": {
		"name": "Tiger", "role": "Striker", "desc": "Silent stripes, savage strikes.", "color": Color("e07b2a"),
		"hp": 92, "atk": 20, "def": 7, "spd": 12, "crit": 0.15,
		"skills": ["scratch", "pounce", "maul"],
	},
	"pangolin": {
		"name": "Pangolin", "role": "Tank", "desc": "Living armor.", "color": Color("8a7356"),
		"hp": 120, "atk": 11, "def": 15, "spd": 6, "crit": 0.05,
		"skills": ["scratch", "curl_up", "tail_slam"],
	},
	"macaque": {
		"name": "Macaque", "role": "Support", "desc": "Hot-spring healer.", "color": Color("b59a86"),
		"hp": 72, "atk": 11, "def": 6, "spd": 12, "crit": 0.05,
		"skills": ["scratch", "groom", "shriek"],
	},
	"tanuki": {
		"name": "Tanuki", "role": "Disruptor", "desc": "Trickster of the forest.", "color": Color("6b5a48"),
		"hp": 88, "atk": 14, "def": 8, "spd": 10, "crit": 0.1,
		"skills": ["bite", "dirty_trick", "frenzy"],
	},
	# Australia
	"kangaroo": {
		"name": "Kangaroo", "role": "Striker", "desc": "Boxes zombies for fun.", "color": Color("b5774a"),
		"hp": 88, "atk": 18, "def": 7, "spd": 13, "crit": 0.15,
		"skills": ["kick", "boxing_flurry", "gore"],
	},
	"wombat": {
		"name": "Wombat", "role": "Tank", "desc": "Armored where it counts.", "color": Color("7c6a58"),
		"hp": 130, "atk": 13, "def": 13, "spd": 6, "crit": 0.05,
		"skills": ["bite", "bum_block", "charge"],
	},
	"kookaburra": {
		"name": "Kookaburra", "role": "Support", "desc": "Laughs in the face of death.", "color": Color("8fa0b0"),
		"hp": 70, "atk": 11, "def": 5, "spd": 12, "crit": 0.05,
		"skills": ["peck", "preen", "laughing_call"],
	},
	"platypus": {
		"name": "Platypus", "role": "Disruptor", "desc": "Venomous. Seriously.", "color": Color("6b5440"),
		"hp": 85, "atk": 14, "def": 8, "spd": 10, "crit": 0.1,
		"skills": ["bite", "venom_spur", "frenzy"],
	},
	# US – Southeast
	"alligator": {
		"name": "Alligator", "role": "Tank", "desc": "Prehistoric and unimpressed.", "color": Color("4d5d3a"),
		"hp": 120, "atk": 14, "def": 13, "spd": 5, "crit": 0.05,
		"skills": ["bite", "hiss", "death_roll"],
	},
	"florida_panther": {
		"name": "Florida Panther", "role": "Striker", "desc": "Swamp ghost.", "color": Color("b08a5a"),
		"hp": 84, "atk": 17, "def": 6, "spd": 14, "crit": 0.2,
		"skills": ["scratch", "pounce", "maul"],
	},
	"blue_heron": {
		"name": "Blue Heron", "role": "Support", "desc": "Patient, precise, protective.", "color": Color("7a8fa6"),
		"hp": 72, "atk": 10, "def": 5, "spd": 11, "crit": 0.1,
		"skills": ["peck", "preen", "dive"],
	},
	# US – Midwest
	"bison": {
		"name": "Bison", "role": "Tank", "desc": "A ton of prairie.", "color": Color("5a4030"),
		"hp": 140, "atk": 14, "def": 12, "spd": 5, "crit": 0.05,
		"skills": ["headbutt", "stand_firm", "trample"],
	},
	"whitetail_deer": {
		"name": "Whitetail Deer", "role": "Bruiser", "desc": "Antlers sharpened by the apocalypse.", "color": Color("a67b52"),
		"hp": 95, "atk": 15, "def": 8, "spd": 12, "crit": 0.1,
		"skills": ["kick", "antler_charge", "stampede"],
	},
	"red_tailed_hawk": {
		"name": "Red-tailed Hawk", "role": "Support", "desc": "Eyes on the whole prairie.", "color": Color("9c5a3c"),
		"hp": 70, "atk": 10, "def": 5, "spd": 13, "crit": 0.1,
		"skills": ["peck", "preen", "dive"],
	},
	# US – Southwest
	"gila_monster": {
		"name": "Gila Monster", "role": "Tank", "desc": "Slow, venomous, beaded armor.", "color": Color("d0763a"),
		"hp": 115, "atk": 13, "def": 13, "spd": 6, "crit": 0.05,
		"skills": ["bite", "venom_spur", "bask"],
	},
	# US – Mountain
	"cougar": {
		"name": "Cougar", "role": "Striker", "desc": "Ambush from the ridgeline.", "color": Color("b8955f"),
		"hp": 86, "atk": 18, "def": 6, "spd": 13, "crit": 0.2,
		"skills": ["bite", "pounce", "maul"],
	},
	"bald_eagle": {
		"name": "Bald Eagle", "role": "Support", "desc": "Rallies the pack from above.", "color": Color("5b4a3a"),
		"hp": 74, "atk": 10, "def": 6, "spd": 12, "crit": 0.1,
		"skills": ["peck", "preen", "dive"],
	},
	"elk": {
		"name": "Elk", "role": "Bruiser", "desc": "Its bugle stops zombies cold.", "color": Color("8a6a4a"),
		"hp": 105, "atk": 14, "def": 9, "spd": 9, "crit": 0.05,
		"skills": ["kick", "antler_charge", "trample"],
	},
	# US – Pacific
	"sea_lion": {
		"name": "Sea Lion", "role": "Tank", "desc": "Loud, heavy, slippery.", "color": Color("6a5546"),
		"hp": 125, "atk": 13, "def": 12, "spd": 8, "crit": 0.05,
		"skills": ["bite", "bellow", "belly_slide"],
	},
	"bobcat": {
		"name": "Bobcat", "role": "Striker", "desc": "Small cat, big problem.", "color": Color("a08060"),
		"hp": 80, "atk": 18, "def": 6, "spd": 14, "crit": 0.2,
		"skills": ["scratch", "pounce", "frenzy"],
	},
	"sea_otter": {
		"name": "Sea Otter", "role": "Support", "desc": "Holds paws so nobody drifts away.", "color": Color("7a5c48"),
		"hp": 72, "atk": 11, "def": 6, "spd": 12, "crit": 0.05,
		"skills": ["bite", "huddle", "rock_smash"],
	},
	# US – Alaska
	"grizzly": {
		"name": "Grizzly", "role": "Tank", "desc": "Apex of the north.", "color": Color("6b4a30"),
		"hp": 135, "atk": 15, "def": 12, "spd": 6, "crit": 0.05,
		"skills": ["scratch", "roar", "maul"],
	},
	"gray_wolf": {
		"name": "Gray Wolf", "role": "Striker", "desc": "Never hunts alone.", "color": Color("8a8a8a"),
		"hp": 85, "atk": 18, "def": 7, "spd": 13, "crit": 0.15,
		"skills": ["bite", "pounce", "pack_hunt"],
	},
	"moose": {
		"name": "Moose", "role": "Bruiser", "desc": "Absolutely not to be messed with.", "color": Color("4a3a2a"),
		"hp": 120, "atk": 14, "def": 10, "spd": 7, "crit": 0.05,
		"skills": ["kick", "antler_charge", "trample"],
	},
	# US – Hawaii
	"monk_seal": {
		"name": "Monk Seal", "role": "Tank", "desc": "Napping? Guarding. Definitely guarding.", "color": Color("7f7f7a"),
		"hp": 125, "atk": 12, "def": 12, "spd": 7, "crit": 0.05,
		"skills": ["bite", "bellow", "bask"],
	},
	"mongoose": {
		"name": "Mongoose", "role": "Striker", "desc": "Fearless and lightning fast.", "color": Color("9a7a50"),
		"hp": 76, "atk": 17, "def": 6, "spd": 16, "crit": 0.2,
		"skills": ["bite", "pounce", "frenzy"],
	},
	"nene": {
		"name": "Nēnē", "role": "Support", "desc": "Hawaiian goose with attitude.", "color": Color("8c7a62"),
		"hp": 72, "atk": 11, "def": 6, "spd": 11, "crit": 0.05,
		"skills": ["peck", "preen", "honk"],
	},
	"wild_boar": {
		"name": "Wild Boar", "role": "Bruiser", "desc": "Tusks and bad temper.", "color": Color("4f3f35"),
		"hp": 105, "atk": 15, "def": 9, "spd": 9, "crit": 0.05,
		"skills": ["headbutt", "gore", "stampede"],
	},
}

## Where the player lives decides which animals they start with.
## US regions are picked from the player's ZIP code (see ZipDB.STATE_REGIONS); the rest from a list.
const REGIONS := {
	"us_new_england": {
		"name": "New England", "blurb": "North woods, rocky coast and old mill towns.", "us": true,
		"animals": ["black_bear", "red_fox", "horned_owl", "moose"],
		"recruits": ["raccoon", "skunk", "opossum", "coyote", "red_tailed_hawk", "bald_eagle", "whitetail_deer", "bobcat"],
	},
	"us_mid_atlantic": {
		"name": "Mid-Atlantic", "blurb": "Big cities, suburbs and the Pine Barrens.", "us": true,
		"animals": ["raccoon", "opossum", "red_tailed_hawk", "skunk"],
		"recruits": ["red_fox", "whitetail_deer", "black_bear", "horned_owl", "coyote", "bobcat", "blue_heron"],
	},
	"us_appalachia": {
		"name": "Appalachia", "blurb": "Hollows, ridges and coal towns.", "us": true,
		"animals": ["black_bear", "bobcat", "horned_owl", "whitetail_deer"],
		"recruits": ["raccoon", "opossum", "red_fox", "skunk", "coyote", "red_tailed_hawk", "turkey_vulture", "elk"],
	},
	"us_carolinas": {
		"name": "Carolinas & Georgia", "blurb": "Piedmont pines and Lowcountry marsh.", "us": true,
		"animals": ["alligator", "bobcat", "blue_heron", "whitetail_deer"],
		"recruits": ["raccoon", "opossum", "black_bear", "red_fox", "horned_owl", "armadillo", "turkey_vulture"],
	},
	"us_florida": {
		"name": "Florida", "blurb": "Everglades, beaches and strip malls.", "us": true,
		"animals": ["alligator", "florida_panther", "blue_heron", "armadillo"],
		"recruits": ["raccoon", "bobcat", "black_bear", "turkey_vulture", "opossum", "horned_owl"],
	},
	"us_gulf_south": {
		"name": "Gulf South", "blurb": "Bayous, delta towns and piney woods.", "us": true,
		"animals": ["alligator", "bobcat", "blue_heron", "armadillo"],
		"recruits": ["raccoon", "opossum", "black_bear", "coyote", "whitetail_deer", "turkey_vulture", "red_tailed_hawk"],
	},
	"us_great_lakes": {
		"name": "Great Lakes", "blurb": "Lake towns, rust belt and north woods.", "us": true,
		"animals": ["badger", "gray_wolf", "horned_owl", "whitetail_deer"],
		"recruits": ["raccoon", "red_fox", "coyote", "black_bear", "bald_eagle", "skunk", "opossum"],
	},
	"us_plains": {
		"name": "Great Plains", "blurb": "Prairie, farmland and small towns.", "us": true,
		"animals": ["bison", "coyote", "red_tailed_hawk", "whitetail_deer"],
		"recruits": ["badger", "red_fox", "skunk", "horned_owl", "turkey_vulture", "opossum", "raccoon"],
	},
	"us_texas": {
		"name": "Texas & Oklahoma", "blurb": "Hill country, plains and sprawling suburbs.", "us": true,
		"animals": ["armadillo", "coyote", "turkey_vulture", "roadrunner"],
		"recruits": ["bobcat", "raccoon", "opossum", "whitetail_deer", "red_tailed_hawk", "skunk", "cougar"],
	},
	"us_desert": {
		"name": "Desert Southwest", "blurb": "Desert, canyons and neon cities.", "us": true,
		"animals": ["gila_monster", "coyote", "turkey_vulture", "roadrunner"],
		"recruits": ["bobcat", "cougar", "red_tailed_hawk", "horned_owl", "skunk", "black_bear"],
	},
	"us_rockies": {
		"name": "Rocky Mountains", "blurb": "Peaks, pine forests and ski towns.", "us": true,
		"animals": ["black_bear", "cougar", "bald_eagle", "elk"],
		"recruits": ["coyote", "gray_wolf", "bison", "moose", "red_fox", "horned_owl", "badger"],
	},
	"us_pacific_nw": {
		"name": "Pacific Northwest", "blurb": "Rainforest, rivers and coffee towns.", "us": true,
		"animals": ["sea_lion", "cougar", "bald_eagle", "elk"],
		"recruits": ["black_bear", "raccoon", "coyote", "bobcat", "sea_otter", "gray_wolf", "horned_owl"],
	},
	"us_california": {
		"name": "California", "blurb": "Coast, valleys and freeways.", "us": true,
		"animals": ["sea_lion", "bobcat", "sea_otter", "coyote"],
		"recruits": ["black_bear", "raccoon", "cougar", "opossum", "red_tailed_hawk", "skunk", "horned_owl"],
	},
	"us_alaska": {
		"name": "Alaska", "blurb": "Tundra, fjords and frontier towns.", "us": true,
		"animals": ["grizzly", "gray_wolf", "bald_eagle", "moose"],
		"recruits": ["red_fox", "sea_lion", "sea_otter", "horned_owl", "bison"],
	},
	"us_hawaii": {
		"name": "Hawaii", "blurb": "Volcanoes, reefs and island towns.", "us": true,
		"animals": ["monk_seal", "mongoose", "nene", "wild_boar"],
		"recruits": [],
	},
	"na_east": {
		"name": "Canada & North America – East", "blurb": "Eastern forests, suburbs and river towns.",
		"animals": ["raccoon", "opossum", "horned_owl", "skunk"],
		"recruits": ["red_fox", "black_bear", "whitetail_deer", "coyote", "bald_eagle"],
	},
	"na_west": {
		"name": "Canada & North America – West", "blurb": "Deserts, mountains and the Pacific coast.",
		"animals": ["coyote", "black_bear", "roadrunner", "turkey_vulture"],
		"recruits": ["cougar", "elk", "bald_eagle", "red_fox", "moose"],
	},
	"europe": {
		"name": "Europe", "blurb": "Old cities, hedgerows and dark forests.",
		"animals": ["red_fox", "badger", "hedgehog", "crow"],
		"recruits": ["wild_boar", "gray_wolf", "horned_owl"],
	},
	"latin_america": {
		"name": "Latin America", "blurb": "Rainforests, wetlands and mountain towns.",
		"animals": ["jaguar", "armadillo", "capybara", "toucan"],
		"recruits": ["cougar", "opossum", "skunk", "turkey_vulture"],
	},
	"africa": {
		"name": "Africa", "blurb": "Savannah, bush and sprawling cities.",
		"animals": ["lioness", "honey_badger", "meerkat", "warthog"],
		"recruits": ["mongoose"],
	},
	"asia": {
		"name": "Asia", "blurb": "Megacities, bamboo forests and hot springs.",
		"animals": ["tiger", "pangolin", "macaque", "tanuki"],
		"recruits": ["wild_boar", "red_fox"],
	},
	"australia": {
		"name": "Australia & Oceania", "blurb": "Outback, bush and coastal towns.",
		"animals": ["kangaroo", "wombat", "kookaburra", "platypus"],
		"recruits": [],
	},
}

## Zombies use the last skill in their list that's ready, so order weakest → strongest.
const ZOMBIES := {
	"shambler": {
		"name": "Shambler", "color": Color("5f7a52"), "xp": 12,
		"hp": 45, "atk": 10, "def": 4, "spd": 5, "crit": 0.05,
		"skills": ["claw", "infectious_bite"],
	},
	"runner": {
		"name": "Runner", "color": Color("7d8f4e"), "xp": 10,
		"hp": 28, "atk": 8, "def": 2, "spd": 15, "crit": 0.1,
		"skills": ["lunge"], "traits": {"hunts_weak": true},
	},
	"bloater": {
		"name": "Bloater", "color": Color("6b8a6a"), "xp": 15,
		"hp": 60, "atk": 9, "def": 2, "spd": 4, "crit": 0.0,
		"skills": ["slam"], "traits": {"explode_on_death": 14},
	},
	"brute": {
		"name": "Brute", "color": Color("4a5e3e"), "xp": 40,
		"hp": 260, "atk": 22, "def": 10, "spd": 7, "crit": 0.05,
		"skills": ["smash", "rampage"],
	},
	"riot": {
		"name": "Riot Zombie", "color": Color("3a4466"), "xp": 22,
		"hp": 70, "atk": 11, "def": 10, "spd": 4, "crit": 0.05,
		"skills": ["claw", "slam"], "traits": {"armored": true},
	},
	"plague": {
		"name": "Plague Carrier", "color": Color("3e8948"), "xp": 18,
		"hp": 50, "atk": 8, "def": 3, "spd": 6, "crit": 0.05,
		"skills": ["claw", "plague_spit"],
	},
	"screamer": {
		"name": "Screamer", "color": Color("c0cbdc"), "xp": 16,
		"hp": 32, "atk": 6, "def": 2, "spd": 13, "crit": 0.05,
		"skills": ["claw", "scream"],
	},
}

## What the counter zombies do, for the scout report and briefing.
const ZOMBIE_NOTES := {
	"riot": "armored: takes half damage from single-target attacks",
	"plague": "sprays infection over the whole pack",
	"screamer": "fast, and its scream can stun everyone",
	"bloater": "explodes when killed",
	"runner": "fast, hunts the weakest",
}

## Regional legends: the boss of a lair on the far edge of the map. US legends sit at their real
## hometown and appear when the player's ZIP is within `range_km`; others appear by world region.
## Kept to folklore cryptids, not figures sacred to living Indigenous traditions.
const BOSS_BUILDS := {
	"giant": {"hp": 340, "atk": 21, "def": 12, "spd": 6, "crit": 0.05, "xp": 120},
	"stalker": {"hp": 270, "atk": 20, "def": 8, "spd": 12, "crit": 0.15, "xp": 120},
	"flyer": {"hp": 250, "atk": 18, "def": 7, "spd": 14, "crit": 0.1, "xp": 120},
	"lurker": {"hp": 310, "atk": 19, "def": 11, "spd": 7, "crit": 0.05, "xp": 120},
}

const LEGENDS := {
	"mothman": {"name": "Mothman", "lore": "Red-eyed omen of Point Pleasant, WV.", "drop": "moth_wing_charm", "build": "flyer",
		"color": Color("5a1f2a"), "lat": 38.84, "lon": -82.14, "range_km": 350,
		"skills": ["wing_buffet", "omen", "red_gaze"]},
	"woodbooger": {"name": "Woodbooger", "lore": "Shaggy giant of the hollows around Norton, VA.", "drop": "hollow_bark_armor", "build": "giant",
		"color": Color("4a3a28"), "lat": 36.93, "lon": -82.63, "range_km": 250,
		"skills": ["tree_toss", "howl", "stomp"]},
	"flatwoods_monster": {"name": "Flatwoods Monster", "lore": "Hooded thing from the sky over Braxton County, WV.", "drop": "glowing_hood_scrap", "build": "lurker",
		"color": Color("3a4a3a"), "lat": 38.72, "lon": -80.65, "range_km": 250,
		"skills": ["heat_ray", "toxic_mist"]},
	"wampus_cat": {"name": "Wampus Cat", "lore": "Half-woman, half-cat prowler of the Smokies.", "drop": "wampus_claw", "build": "stalker",
		"color": Color("3a3030"), "lat": 35.96, "lon": -83.92, "range_km": 300,
		"skills": ["rend", "shadow_pounce", "howl"]},
	"pope_lick_monster": {"name": "Pope Lick Monster", "lore": "Goat-man under the Louisville trestle.", "drop": "trestle_spike", "build": "giant",
		"color": Color("5a4a3a"), "lat": 38.2, "lon": -85.6, "range_km": 250,
		"skills": ["trestle_charge", "stomp"]},
	"loveland_frogman": {"name": "Loveland Frogman", "lore": "Upright frog of the Little Miami River, OH.", "drop": "frogman_crown", "build": "lurker",
		"color": Color("3f5a3a"), "lat": 39.27, "lon": -84.26, "range_km": 250,
		"skills": ["rend", "toxic_mist"]},
	"jersey_devil": {"name": "Jersey Devil", "lore": "Winged terror of the Pine Barrens, NJ.", "drop": "devils_hoofprint", "build": "stalker",
		"color": Color("4a1f1f"), "lat": 39.8, "lon": -74.5, "range_km": 250,
		"skills": ["rend", "tail_lash", "hellish_shriek"]},
	"goatman": {"name": "Goatman", "lore": "Axe-swinging horror of Prince George's County, MD.", "drop": "goatman_horn", "build": "giant",
		"color": Color("4a4038"), "lat": 38.98, "lon": -76.88, "range_km": 180,
		"skills": ["axe_swing", "stomp"]},
	"snallygaster": {"name": "Snallygaster", "lore": "Dragon-bird of Frederick County, MD.", "drop": "snallygaster_scale", "build": "flyer",
		"color": Color("3a3a4a"), "lat": 39.41, "lon": -77.41, "range_km": 200,
		"skills": ["wing_buffet", "tail_lash", "hellish_shriek"]},
	"champ": {"name": "Champ", "lore": "The serpent of Lake Champlain, VT.", "drop": "lake_pearl", "build": "lurker",
		"color": Color("2a3a4a"), "lat": 44.5, "lon": -73.3, "range_km": 250,
		"skills": ["lake_bite", "tail_lash"]},
	"dover_demon": {"name": "Dover Demon", "lore": "Glowing-eyed wisp seen in Dover, MA.", "drop": "dover_eye", "build": "flyer",
		"color": Color("6a6a50"), "lat": 42.25, "lon": -71.28, "range_km": 180,
		"skills": ["spindly_claw", "omen", "red_gaze"]},
	"dogman": {"name": "Michigan Dogman", "lore": "Seven-foot dog-headed stalker of northern Michigan.", "drop": "moonlit_fang", "build": "stalker",
		"color": Color("3a3028"), "lat": 44.3, "lon": -85.6, "range_km": 350,
		"skills": ["rend", "howl", "shadow_pounce"]},
	"beast_of_bray_road": {"name": "Beast of Bray Road", "lore": "Wolf-thing of Elkhorn, WI.", "drop": "moonlit_fang", "build": "stalker",
		"color": Color("40382f"), "lat": 42.67, "lon": -88.55, "range_km": 250,
		"skills": ["rend", "howl", "stomp"]},
	"hodag": {"name": "Hodag", "lore": "Horned, spiked beast of Rhinelander, WI.", "drop": "hodag_spine", "build": "lurker",
		"color": Color("2f2f2a"), "lat": 45.64, "lon": -89.41, "range_km": 220,
		"skills": ["horn_gore", "tail_lash"]},
	"van_meter_visitor": {"name": "Van Meter Visitor", "lore": "Horn-lit winged thing of Van Meter, IA.", "drop": "horn_lantern", "build": "flyer",
		"color": Color("4a3a2a"), "lat": 41.53, "lon": -93.95, "range_km": 300,
		"skills": ["heat_ray", "wing_buffet", "red_gaze"]},
	"ozark_howler": {"name": "Ozark Howler", "lore": "Horned black cat of the Ozark hills.", "drop": "howler_tuft", "build": "stalker",
		"color": Color("26221f"), "lat": 36.5, "lon": -92.5, "range_km": 300,
		"skills": ["rend", "howl", "red_gaze"]},
	"fouke_monster": {"name": "Fouke Monster", "lore": "The Boggy Creek beast of Fouke, AR.", "drop": "plaster_footprint", "build": "giant",
		"color": Color("4a3626"), "lat": 33.26, "lon": -93.89, "range_km": 300,
		"skills": ["tree_toss", "stomp", "howl"]},
	"rougarou": {"name": "Rougarou", "lore": "Wolf-headed haunt of the Louisiana bayous.", "drop": "moonlit_fang", "build": "stalker",
		"color": Color("33302a"), "lat": 30.0, "lon": -91.0, "range_km": 300,
		"skills": ["rend", "howl", "stomp"]},
	"lizard_man": {"name": "Lizard Man", "lore": "Scaly swamp-stalker of Scape Ore Swamp, SC.", "drop": "swamp_scale", "build": "lurker",
		"color": Color("3a4a2a"), "lat": 34.22, "lon": -80.25, "range_km": 250,
		"skills": ["rend", "tail_lash", "toxic_mist"]},
	"altamaha_ha": {"name": "Altamaha-ha", "lore": "River serpent of coastal Georgia.", "drop": "lake_pearl", "build": "lurker",
		"color": Color("2a3a3a"), "lat": 31.3, "lon": -81.5, "range_km": 250,
		"skills": ["lake_bite", "tail_lash"]},
	"skunk_ape": {"name": "Skunk Ape", "lore": "Reeking swamp ape of the Everglades.", "drop": "bottled_stench", "build": "giant",
		"color": Color("4a4a30"), "lat": 26.5, "lon": -81.0, "range_km": 550,
		"skills": ["tree_toss", "stench", "stomp"]},
	"chupacabra": {"name": "Chupacabra", "lore": "Spined goat-sucker of Texas ranch country.", "drop": "chupacabra_fang", "build": "stalker",
		"color": Color("4a3a3a"), "lat": 29.4, "lon": -98.5, "range_km": 700, "regions": ["latin_america"],
		"skills": ["rend", "blood_drain", "shadow_pounce"]},
	"mogollon_monster": {"name": "Mogollon Monster", "lore": "Rim-country giant of central Arizona.", "drop": "plaster_footprint", "build": "giant",
		"color": Color("5a3a28"), "lat": 34.3, "lon": -111.0, "range_km": 400,
		"skills": ["tree_toss", "howl", "stomp"]},
	"bigfoot": {"name": "Bigfoot", "lore": "Sasquatch of the Pacific Northwest woods.", "drop": "plaster_footprint", "build": "giant",
		"color": Color("4a3020"), "lat": 44.5, "lon": -122.5, "range_km": 750, "regions": ["na_east", "na_west"],
		"skills": ["tree_toss", "howl", "stomp"]},
	"tahoe_tessie": {"name": "Tahoe Tessie", "lore": "Deep-water beast of Lake Tahoe.", "drop": "lake_pearl", "build": "lurker",
		"color": Color("2a3a4a"), "lat": 39.1, "lon": -120.04, "range_km": 250,
		"skills": ["lake_bite", "tail_lash"]},
	"bear_lake_monster": {"name": "Bear Lake Monster", "lore": "Serpent of Bear Lake, on the Utah-Idaho line.", "drop": "lake_pearl", "build": "lurker",
		"color": Color("2a3a40"), "lat": 41.95, "lon": -111.33, "range_km": 350,
		"skills": ["lake_bite", "tail_lash"]},
	"flathead_monster": {"name": "Flathead Lake Monster", "lore": "Giant thing of Flathead Lake, MT.", "drop": "lake_pearl", "build": "lurker",
		"color": Color("2a3440"), "lat": 47.9, "lon": -114.1, "range_km": 300,
		"skills": ["lake_bite", "tail_lash"]},
	"slide_rock_bolter": {"name": "Slide-Rock Bolter", "lore": "Mountain-gripping whale of the Colorado peaks.", "drop": "bolter_hook", "build": "giant",
		"color": Color("50504a"), "lat": 39.5, "lon": -106.0, "range_km": 350,
		"skills": ["rend", "avalanche"]},
	"iliamna_monster": {"name": "Iliamna Lake Monster", "lore": "Huge fish-beast of Lake Iliamna, AK.", "drop": "lake_pearl", "build": "lurker",
		"color": Color("2a3a4a"), "lat": 59.75, "lon": -154.9, "range_km": 1200,
		"skills": ["lake_bite", "tail_lash"]},
	"black_shuck": {"name": "Black Shuck", "lore": "Fiery-eyed hellhound of the English coast.", "drop": "hellhound_ember", "build": "stalker",
		"color": Color("1f1f1f"), "regions": ["europe"],
		"skills": ["rend", "howl", "red_gaze"]},
	"mokele_mbembe": {"name": "Mokèlé-mbèmbé", "lore": "River-blocking giant of the Congo basin.", "drop": "lake_pearl", "build": "lurker",
		"color": Color("3a4030"), "regions": ["africa"],
		"skills": ["lake_bite", "tail_lash"]},
	"yeti": {"name": "Yeti", "lore": "Snow-beast of the high Himalaya.", "drop": "yeti_fur", "build": "giant",
		"color": Color("c0c4c8"), "regions": ["asia"],
		"skills": ["tree_toss", "avalanche", "howl"]},
	"drop_bear": {"name": "Drop Bear", "lore": "The thing that falls on tourists from the gum trees.", "drop": "drop_bear_claw", "build": "stalker",
		"color": Color("6a6a6a"), "regions": ["australia"],
		"skills": ["rend", "shadow_pounce", "stomp"]},
}

## Trinkets: one per animal. Legends drop their own (see LEGENDS "drop"); caches hold the plain ones.
## Effects: hp/atk/def/spd are multipliers (+0.2 = +20%), crit adds to crit chance, lifesteal heals
## that share of damage dealt, thorns reflects that share of damage taken, regen heals that share
## of max HP each turn, immune blocks statuses, start triggers at the start of every wave.
const TRINKETS := {
	"moth_wing_charm": {"name": "Moth Wing Charm", "flavor": "A dusty scale from a red-eyed omen.", "spd": 0.25, "def": -0.1},
	"hollow_bark_armor": {"name": "Hollow-Bark Armor", "flavor": "Bark peeled off a Virginia giant.", "def": 0.3, "spd": -0.15},
	"glowing_hood_scrap": {"name": "Glowing Hood Scrap", "flavor": "Still faintly warm. Smells like metal.", "immune": ["infected"], "atk": -0.1},
	"wampus_claw": {"name": "Wampus Claw", "flavor": "Curved, black and still sharp.", "crit": 0.2, "hp": -0.1},
	"trestle_spike": {"name": "Trestle Spike", "flavor": "Pried from the Pope Lick trestle.", "atk": 0.25, "def": -0.15},
	"frogman_crown": {"name": "Frogman's Crown", "flavor": "Damp. Always damp.", "regen": 0.05, "atk": -0.1},
	"devils_hoofprint": {"name": "Devil's Hoofprint", "flavor": "A scorched cast of a Pine Barrens hoof.", "lifesteal": 0.2, "hp": -0.15},
	"goatman_horn": {"name": "Goatman's Horn", "flavor": "Heavy, ridged and very much not a goat's.", "atk": 0.15, "hp": 0.1},
	"snallygaster_scale": {"name": "Snallygaster Scale", "flavor": "Edged like a razor.", "thorns": 0.25, "spd": -0.1},
	"lake_pearl": {"name": "Lake Pearl", "flavor": "Coughed up from very deep water.", "hp": 0.25},
	"dover_eye": {"name": "Dover Eye", "flavor": "It blinks sometimes.", "crit": 0.15, "spd": 0.15, "hp": -0.2},
	"moonlit_fang": {"name": "Moonlit Fang", "flavor": "Glows under a full moon.", "lifesteal": 0.1, "atk": 0.1},
	"hodag_spine": {"name": "Hodag Spine", "flavor": "Rhinelander's finest souvenir.", "thorns": 0.3, "atk": -0.1},
	"horn_lantern": {"name": "Horn Lantern", "flavor": "The light from a winged visitor's brow.", "start": "guard", "spd": -0.1},
	"howler_tuft": {"name": "Howler Tuft", "flavor": "A tuft of black fur that hums.", "spd": 0.2, "crit": 0.1, "hp": -0.15},
	"swamp_scale": {"name": "Swamp Scale", "flavor": "Green-black and cold to the touch.", "def": 0.2, "immune": ["infected"], "spd": -0.1},
	"bottled_stench": {"name": "Bottled Stench", "flavor": "Do NOT open indoors.", "start": "weaken_foes", "spd": -0.15},
	"chupacabra_fang": {"name": "Chupacabra Fang", "flavor": "Hollow, like a straw.", "lifesteal": 0.25, "def": -0.1},
	"plaster_footprint": {"name": "Plaster Footprint", "flavor": "A cast of a very, very big foot.", "hp": 0.2, "def": 0.1},
	"bolter_hook": {"name": "Bolter Hook", "flavor": "The tail-hook of a mountain whale.", "atk": 0.3, "spd": -0.2},
	"hellhound_ember": {"name": "Hellhound Ember", "flavor": "Never goes out.", "atk": 0.2, "hp": -0.1},
	"yeti_fur": {"name": "Yeti Fur", "flavor": "Warm, white and enormous.", "hp": 0.2, "def": 0.15, "spd": -0.1},
	"drop_bear_claw": {"name": "Drop Bear Claw", "flavor": "Look up. Always look up.", "crit": 0.15, "atk": 0.15, "def": -0.15},
	# Cache finds
	"rusty_dog_tag": {"name": "Rusty Dog Tag", "flavor": "Someone's good dog. Now yours.", "hp": 0.1},
	"lucky_bottle_cap": {"name": "Lucky Bottle Cap", "flavor": "Heads up. Always.", "crit": 0.1},
	"duct_tape_armor": {"name": "Duct-Tape Armor", "flavor": "It holds. Mostly.", "def": 0.15, "spd": -0.05},
	"spare_battery": {"name": "Spare Battery", "flavor": "Licking it is a bad idea. Very energizing.", "spd": 0.1},
	"first_aid_kit": {"name": "First-Aid Kit", "flavor": "Half full. Better than empty.", "regen": 0.03},
}
const CACHE_TRINKETS := ["rusty_dog_tag", "lucky_bottle_cap", "duct_tape_armor", "spare_battery", "first_aid_kit"]


## A trinket's effects in words, e.g. "+25% SPD, -10% DEF".
static func trinket_effects(id: String) -> String:
	var t: Dictionary = TRINKETS[id]
	var parts: PackedStringArray = []
	var pct := func(v: float) -> String: return ("+" if v > 0 else "") + str(roundi(v * 100)) + "%"
	for stat in ["hp", "atk", "def", "spd"]:
		if t.has(stat):
			parts.append("%s %s" % [pct.call(t[stat]), stat.to_upper()])
	if t.has("crit"):
		parts.append("%s crit" % pct.call(t.crit))
	if t.has("lifesteal"):
		parts.append("heals %d%% of damage dealt" % roundi(t.lifesteal * 100))
	if t.has("thorns"):
		parts.append("reflects %d%% of damage taken" % roundi(t.thorns * 100))
	if t.has("regen"):
		parts.append("regains %d%% HP each turn" % roundi(t.regen * 100))
	if t.has("immune"):
		parts.append("can't be " + ", ".join(PackedStringArray(t.immune)))
	match t.get("start", ""):
		"guard":
			parts.append("starts every wave braced (Guard)")
		"weaken_foes":
			parts.append("weakens every zombie as each wave starts")
	return ", ".join(parts)


const WAVES := [
	["shambler", "shambler", "runner"],
	["runner", "bloater", "shambler", "shambler"],
	["shambler", "brute", "runner"],
]

## Map territories: threat 1-5, from distance to home. Higher threat = more waves, tougher zombies.
const MAX_THREAT := 5
const THREAT_ZOMBIE_MULT := {1: 1.0, 2: 1.15, 3: 1.38, 4: 1.62, 5: 1.9}

## Leveling: every animal in the pack (pet included) earns XP from each fight it's part of.
const MAX_LEVEL := 20
const XP_STEP := 120  # XP to go from level L to L+1 is XP_STEP * L
const LEVEL_GROWTH := {"hp": 0.06, "atk": 0.045, "def": 0.03}  # per level above 1
const DEFEAT_XP_SHARE := 0.5  # a retreat still teaches something

## --- Lineup: reasons to swap animals in and out ---------------------------------------------

## Tags: kinds (canine, feline, bird, scavenger) and the conditions an animal fights best in.
const ANIMAL_TAGS := {
	"dog": ["canine", "urban"],
	"cat": ["feline", "urban", "night"],
	"bird": ["bird", "urban"],
	"rabbit": ["forest", "urban"],
	"lizard": ["desert"],
	"hamster": ["urban"],
	"raccoon": ["scavenger", "urban", "night"],
	"opossum": ["scavenger", "urban", "night"],
	"horned_owl": ["bird", "night", "forest"],
	"skunk": ["scavenger", "night", "urban"],
	"coyote": ["canine", "desert", "urban"],
	"black_bear": ["forest", "mountain"],
	"roadrunner": ["bird", "desert"],
	"turkey_vulture": ["bird", "scavenger", "desert"],
	"red_fox": ["canine", "forest", "night"],
	"badger": ["forest", "night"],
	"hedgehog": ["forest", "night"],
	"crow": ["bird", "scavenger", "urban"],
	"jaguar": ["feline", "forest", "water"],
	"armadillo": ["desert", "night"],
	"capybara": ["water"],
	"toucan": ["bird", "forest"],
	"lioness": ["feline", "desert"],
	"honey_badger": ["desert", "night"],
	"meerkat": ["desert"],
	"warthog": ["desert"],
	"tiger": ["feline", "forest", "water"],
	"pangolin": ["forest", "night"],
	"macaque": ["forest", "mountain"],
	"tanuki": ["canine", "forest", "night", "urban"],
	"kangaroo": ["desert"],
	"wombat": ["forest", "night"],
	"kookaburra": ["bird", "forest"],
	"platypus": ["water"],
	"alligator": ["water"],
	"florida_panther": ["feline", "forest", "water"],
	"blue_heron": ["bird", "water"],
	"bison": ["mountain"],
	"whitetail_deer": ["forest"],
	"red_tailed_hawk": ["bird", "urban"],
	"gila_monster": ["desert"],
	"cougar": ["feline", "mountain", "night"],
	"bald_eagle": ["bird", "water", "mountain"],
	"elk": ["mountain", "forest"],
	"sea_lion": ["water"],
	"bobcat": ["feline", "forest", "night"],
	"sea_otter": ["water"],
	"grizzly": ["mountain", "forest"],
	"gray_wolf": ["canine", "mountain", "forest", "night"],
	"moose": ["forest", "water"],
	"monk_seal": ["water"],
	"mongoose": ["urban"],
	"nene": ["bird"],
	"wild_boar": ["forest"],
}

## Every territory has a condition; animals tagged with it fight better there.
const CONDITIONS := {
	"urban": {"name": "Streets", "who": "city animals"},
	"forest": {"name": "Forest", "who": "forest animals"},
	"water": {"name": "Riverside", "who": "water animals"},
	"mountain": {"name": "Mountains", "who": "mountain animals"},
	"desert": {"name": "Badlands", "who": "desert animals"},
	"night": {"name": "Night raid", "who": "night animals"},
}
const CONDITION_FIELD := {
	"urban": Color("2b2e3a"), "forest": Color("1e3324"), "water": Color("16304a"),
	"mountain": Color("2c3040"), "desert": Color("3a2e22"), "night": Color("141428"),
}
## How likely each terrain is, by region (cities and night raids are decided separately).
const REGION_TERRAIN := {
	"us_new_england": {"forest": 3, "mountain": 1, "water": 2},
	"us_mid_atlantic": {"forest": 2, "water": 2},
	"us_appalachia": {"forest": 3, "mountain": 3, "water": 1},
	"us_carolinas": {"forest": 3, "water": 2},
	"us_florida": {"water": 3, "forest": 1},
	"us_gulf_south": {"water": 3, "forest": 2},
	"us_great_lakes": {"forest": 2, "water": 3},
	"us_plains": {"forest": 1, "water": 1},
	"us_texas": {"desert": 2, "forest": 1, "water": 1},
	"us_desert": {"desert": 4, "mountain": 2},
	"us_rockies": {"mountain": 4, "forest": 2},
	"us_pacific_nw": {"forest": 3, "water": 2, "mountain": 1},
	"us_california": {"water": 2, "mountain": 1, "desert": 1, "forest": 1},
	"us_alaska": {"mountain": 3, "water": 2, "forest": 2},
	"us_hawaii": {"water": 3, "forest": 1, "mountain": 1},
	"na_east": {"forest": 2, "water": 1},
	"na_west": {"mountain": 2, "forest": 1, "desert": 1},
	"europe": {"forest": 2, "water": 1},
	"latin_america": {"forest": 2, "water": 2},
	"africa": {"desert": 3, "forest": 1},
	"asia": {"forest": 2, "mountain": 2, "water": 1},
	"australia": {"desert": 3, "forest": 1, "water": 1},
}
const NIGHT_RAID_CHANCE := 0.15
const URBAN_MAX_KM2 := 25.0
const CONDITION_BONUS := 0.15
const HOME_TURF_BONUS := 0.1
const BOND_BONUS := 0.08
const INJURY_BATTLES := 2
const INJURY_PENALTY := 0.25
const FATIGUE_STEP := 0.05
const MAX_FATIGUE := 0.2
const BENCH_XP_SHARE := 0.25
const DUTIES := ["scout", "forage", "guard"]
const DUTY_INFO := {
	"scout": "Scout: reveals every territory's zombie waves.",
	"forage": "Forage: after each battle, may find XP for the pack (25%) or a trinket (5%).",
	"guard": "Guard: the horde counterattacks less often (every 5 turns, not 3).",
}
const FORAGE_XP_CHANCE := 0.25
const FORAGE_XP := 60
const FORAGE_TRINKET_CHANCE := 0.05
const GUARD_COUNTER_DELAY := 2

## Bonds: animals that fight well together. Each member gets +BOND_BONUS ATK and DEF.
const BONDS := [
	{"name": "Pack Hunters", "desc": "2+ canines", "tag": "canine"},
	{"name": "Big Cats", "desc": "2+ felines", "tag": "feline"},
	{"name": "Sky Watch", "desc": "2+ birds", "tag": "bird"},
	{"name": "Night Shift", "desc": "2+ night animals", "tag": "night"},
	{"name": "Trash Pact", "desc": "2+ scavengers", "tag": "scavenger"},
	{"name": "Odd Couple", "desc": "a canine and a feline", "pair": ["canine", "feline"]},
	{"name": "Neighbors", "desc": "all wild members from one region", "neighbors": true},
]

## Legends' weak spots (+LEGEND_WEAK_MULT damage) and resistances (x LEGEND_RESIST_MULT), by tag.
const LEGEND_WEAKNESS := {
	"giant": {"weak": "forest", "resist": "urban", "why": "Forest animals know its hollows; city animals panic."},
	"stalker": {"weak": "canine", "resist": "feline", "why": "It hates dogs and wolves; cats can't out-stalk it."},
	"flyer": {"weak": "bird", "resist": "night", "why": "Birds meet it in the air; it owns the night."},
	"lurker": {"weak": "water", "resist": "desert", "why": "Water animals fight it on its own terms; desert animals flounder."},
}
const LEGEND_WEAK_MULT := 1.5
const LEGEND_RESIST_MULT := 0.6

## Skills grow with levels: every level-up the player picks one small upgrade for one skill; at
## SIGNATURE_LEVEL each animal learns its role's signature skill; at MASTERY_LEVEL every skill
## hits harder, heals more and recharges a turn faster.
const SIGNATURE_LEVEL := 10
const MASTERY_LEVEL := 20
const MASTERY_BOOST := 0.2
const UPGRADE_STEP := {"power": 0.1, "crit": 0.08, "heal": 0.05, "chance": 0.15}
const UPGRADE_LIMITS := {"power": 5, "crit": 3, "heal": 4, "cooldown": 3, "chance": 3, "duration": 2}
const UPGRADE_LABELS := {
	"power": "Power +10%", "crit": "Crit chance +8%", "heal": "Heals 5% more",
	"cooldown": "Recharges 1 turn faster", "chance": "Effect chance +15%", "duration": "Effects last 1 turn longer",
}
## Stat nodes in the tech tree (speed is flat: +1 per node). Training: stats bought directly,
## any time, up to TRAINING_LIMITS times each.
const STAT_STEP := {"hp": 0.08, "atk": 0.05, "def": 0.06, "spd": 1, "crit": 0.04}
const TRAINING_LIMITS := {"hp": 5, "atk": 5, "def": 5, "spd": 4, "crit": 4}
const STAT_LABELS := {
	"hp": "Max HP +8%", "atk": "Attack +5%", "def": "Defense +6%", "spd": "Speed +1", "crit": "Crit chance +4%",
}
const ROLE_SIGNATURES := {
	"Tank": "last_stand", "Striker": "finishing_blow", "Support": "rally", "Disruptor": "hex_cloud",
	"Bruiser": "stampede_charge",
}
const SIGNATURE_NAMES := {
	"dog": "Loyal Stand",
	"lizard": "Scale Fortress",
	"opossum": "Undying Hiss",
	"black_bear": "Mama Bear",
	"badger": "Burrow Fortress",
	"hedgehog": "Spine Fortress",
	"armadillo": "Armadillo Ball",
	"honey_badger": "Don't Care",
	"pangolin": "Living Fortress",
	"wombat": "Bunker",
	"alligator": "Ancient Hide",
	"bison": "Herd Wall",
	"gila_monster": "Venom Hide",
	"sea_lion": "Harbor Wall",
	"grizzly": "Grizzly Stand",
	"monk_seal": "Beach Fortress",
	"cat": "Nine Lives Pounce",
	"rabbit": "Lucky Foot",
	"raccoon": "Midnight Raid",
	"coyote": "Trickster Strike",
	"roadrunner": "Meep Meep",
	"red_fox": "Fox Fire",
	"jaguar": "Jungle Ambush",
	"toucan": "Beak Breaker",
	"lioness": "Pride Strike",
	"tiger": "Tiger Fang",
	"kangaroo": "Knockout Punch",
	"florida_panther": "Ghost Strike",
	"cougar": "Ridge Ambush",
	"bobcat": "Bobcat Blitz",
	"gray_wolf": "Alpha Fang",
	"mongoose": "Cobra Killer",
	"bird": "Morning Song",
	"hamster": "Seed Feast",
	"horned_owl": "Night Watch",
	"turkey_vulture": "Scrap Feast",
	"crow": "Murder Rally",
	"capybara": "Hot Spring",
	"meerkat": "Sentry Call",
	"macaque": "Onsen Rally",
	"kookaburra": "Dawn Chorus",
	"blue_heron": "Still Waters",
	"red_tailed_hawk": "Sky Rally",
	"bald_eagle": "Freedom Call",
	"sea_otter": "Raft Up",
	"nene": "Island Song",
	"skunk": "Stink Bomb",
	"tanuki": "Shapeshift Hex",
	"platypus": "Venom Cloud",
	"warthog": "Tusk Rampage",
	"whitetail_deer": "Rut Charge",
	"elk": "Bugle Charge",
	"moose": "Moose Stampede",
	"wild_boar": "Boar Rush",
}

## How to beat each kind of legend, shown in the lair briefing.
const BOSS_TIPS := {
	"giant": "Slow, with huge HP. Taunt with your tank and pile on your biggest hits.",
	"stalker": "Fast, with deadly crits. Keep your healer ready and guard your weakest animal.",
	"flyer": "Quick, and its attacks hit the whole pack. Heal often and stun it if you can.",
	"lurker": "Thick hide and a sweeping tail. Weaken it (ATK down) and wear it down.",
}

## Zombie strength for any threat. Past MAX_THREAT (the expanding frontier) it keeps climbing.
static func zombie_mult(threat: int) -> float:
	if THREAT_ZOMBIE_MULT.has(threat):
		return THREAT_ZOMBIE_MULT[threat]
	return THREAT_ZOMBIE_MULT[MAX_THREAT] + 0.25 * (threat - MAX_THREAT)


## A territory's level: roughly the pack level that usually takes it on, so it reads on the same
## scale as the pack. Each level is worth about +9% (stats plus tech-tree points, trinkets and held
## territory), giving threat 1-5 levels 1, 3, 5, 8 and 11, and about +3 per threat beyond.
static func territory_level(zombie_strength: float) -> int:
	return maxi(1, 1 + roundi((zombie_strength - 1.0) / TERRITORY_LEVEL_STEP))


const TERRITORY_LEVEL_STEP := 0.09
## Auto mode fights a territory on its own when the pack leader is at least this many levels above it.
const AUTO_LEVEL_GAP := 10


## Risk-style reinforcements: every territory held beyond home strengthens the pack (HP/ATK).
const HELD_TERRITORY_BONUS := 0.01
const MAX_HELD_BONUS := 0.15
## Each failed attack thins the horde in that territory, down to a floor, so nothing walls you forever.
const ATTRITION_PER_LOSS := 0.08
const MIN_ATTRITION := 0.7
## The horde counterattacks one of your border territories every N map turns.
const COUNTERATTACK_EVERY := 3


## An animal's tags plus its role (lowercase), e.g. ["canine", "urban", "tank"].
static func tags_of(unit_id: String) -> Array[String]:
	var tags: Array[String] = []
	tags.assign(ANIMAL_TAGS.get(unit_id, []))
	var data: Dictionary = PETS.get(unit_id, ANIMALS.get(unit_id, {}))
	if data.has("role"):
		tags.append(String(data.role).to_lower())
	return tags


## Regions where an animal lives (as a starter or a recruit).
static func native_regions(unit_id: String) -> Array[String]:
	var out: Array[String] = []
	for region_id in REGIONS:
		var r: Dictionary = REGIONS[region_id]
		if unit_id in r.animals or unit_id in r.get("recruits", []):
			out.append(region_id)
	return out


## Bonds active for a lineup: [{name, desc, members}].
static func active_bonds(ids: Array[String]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for bond: Dictionary in BONDS:
		var members: Array[String] = []
		if bond.has("tag"):
			for id in ids:
				if bond.tag in ANIMAL_TAGS.get(id, []):
					members.append(id)
			if members.size() < 2:
				continue
		elif bond.has("pair"):
			var has_a := false
			var has_b := false
			for id in ids:
				var tags: Array = ANIMAL_TAGS.get(id, [])
				if bond.pair[0] in tags:
					has_a = true
					members.append(id)
				elif bond.pair[1] in tags:
					has_b = true
					members.append(id)
			if not (has_a and has_b):
				continue
		else:
			var wild: Array[String] = []
			for id in ids:
				if ANIMALS.has(id):
					wild.append(id)
			if wild.size() < 2:
				continue
			var shared := native_regions(wild[0])
			for id in wild:
				var regions := native_regions(id)
				shared = shared.filter(func(r: String) -> bool: return r in regions)
			if shared.is_empty():
				continue
			members = wild
		out.append({"name": bond.name, "desc": bond.desc, "members": members})
	return out


## "Shambler x2, Runner | Riot Zombie, Brute" for a territory's waves.
static func waves_text(waves: Array) -> String:
	var parts: PackedStringArray = []
	for wave: Array in waves:
		var counts := {}
		var order: Array[String] = []
		for id: String in wave:
			if not counts.has(id):
				order.append(id)
			counts[id] = counts.get(id, 0) + 1
		var names: PackedStringArray = []
		for id in order:
			names.append(enemy(id).name + ((" x%d" % counts[id]) if counts[id] > 1 else ""))
		parts.append(", ".join(names))
	return " | ".join(parts)


## --- Tech tree ---------------------------------------------------------------------------------
## Each animal's tree is built from its own skills: three branches of TREE_DEPTH nodes (each needs
## the one above it) plus a signature row gated by level. One point per level, more nodes than
## points, so which branches you finish matters.
const TREE_DEPTH := 6
const TREE_BRANCHES := [
	{"id": "fang", "name": "Fang", "skill": 0, "plan": ["skill", "atk", "skill", "crit", "skill", "atk"]},
	{"id": "hide", "name": "Hide", "skill": 1, "plan": ["hp", "skill", "def", "hp", "skill", "def"]},
	{"id": "instinct", "name": "Instinct", "skill": 2, "plan": ["skill", "spd", "skill", "crit", "skill", "spd"]},
]
static var _trees := {}


## Nodes: {id, branch, tier, requires, min_level, kind ("stat" | "skill" | "signature" | "mastery"),
## stat | skill + upgrade, title}.
static func tech_tree(unit_id: String) -> Array[Dictionary]:
	if _trees.has(unit_id):
		return _trees[unit_id]
	var data: Dictionary = PETS.get(unit_id, ANIMALS.get(unit_id, {}))
	var nodes: Array[Dictionary] = []
	for branch: Dictionary in TREE_BRANCHES:
		var skill_id: String = data.skills[branch.skill]
		var steps := {}
		var turn := 0
		var prev := ""
		for tier in TREE_DEPTH:
			var node := {"id": "%s%d" % [branch.id, tier + 1], "branch": branch.id, "tier": tier + 1,
				"requires": [prev] if prev != "" else [], "min_level": 1}
			var step: String = branch.plan[tier]
			if step == "skill":
				var options := upgrade_options(skill_id, steps)
				if options.is_empty():
					step = "hp" if branch.id == "hide" else "atk"
				else:
					var kind: String = options[turn % options.size()]
					turn += 1
					steps[kind] = steps.get(kind, 0) + 1
					node.merge({"kind": "skill", "skill": skill_id, "upgrade": kind,
						"title": "%s: %s" % [skill(skill_id).name, UPGRADE_LABELS[kind]]})
			if step != "skill":
				node.merge({"kind": "stat", "stat": step, "title": STAT_LABELS[step]})
			nodes.append(node)
			prev = node.id
	var sig := signature_skill(data.role)
	var sig_name: String = SIGNATURE_NAMES.get(unit_id, skill(sig).name)
	nodes.append({"id": "sig", "branch": "signature", "tier": 1, "requires": [], "min_level": SIGNATURE_LEVEL,
		"kind": "signature", "skill": sig, "title": "Learn " + sig_name})
	var sig_steps := {}
	var prev_sig := "sig"
	for k in 2:
		var options := upgrade_options(sig, sig_steps)
		var kind: String = options[k % options.size()]
		sig_steps[kind] = sig_steps.get(kind, 0) + 1
		var node_id := "sig%d" % (k + 2)
		nodes.append({"id": node_id, "branch": "signature", "tier": k + 2, "requires": [prev_sig],
			"min_level": SIGNATURE_LEVEL, "kind": "skill", "skill": sig, "upgrade": kind,
			"title": "%s: %s" % [sig_name, UPGRADE_LABELS[kind]]})
		prev_sig = node_id
	nodes.append({"id": "mastery", "branch": "signature", "tier": 4, "requires": ["sig"],
		"min_level": MASTERY_LEVEL, "kind": "mastery", "title": "Mastery",
		"detail": "Every skill +%d%% power and healing, and recharges a turn faster." % roundi(MASTERY_BOOST * 100)})
	for stat in TRAINING_LIMITS:
		var prev_train := ""
		for k in TRAINING_LIMITS[stat]:
			var node_id := "train_%s%d" % [stat, k + 1]
			nodes.append({"id": node_id, "branch": "training", "tier": k + 1, "stat": stat,
				"requires": [prev_train] if prev_train != "" else [], "min_level": 1,
				"kind": "stat", "title": STAT_LABELS[stat]})
			prev_train = node_id
	_trees[unit_id] = nodes
	return nodes


static func tree_node(unit_id: String, node_id: String) -> Dictionary:
	for node in tech_tree(unit_id):
		if node.id == node_id:
			return node
	return {}


static func signature_skill(role: String) -> String:
	return ROLE_SIGNATURES.get(role, "finishing_blow")


## Upgrades still available for a skill, given the steps already taken.
static func upgrade_options(skill_id: String, steps: Dictionary) -> Array[String]:
	var s := skill(skill_id)
	var kinds: Array[String] = []
	var power: float = s.get("power", 0.0)
	if power > 0.0:
		kinds.append("power")
		if s.target == "enemy":
			kinds.append("crit")
	if s.get("heal", 0.0) > 0.0:
		kinds.append("heal")
	if s.get("cooldown", 0) - steps.get("cooldown", 0) >= 2:
		kinds.append("cooldown")
	for e: Dictionary in s.get("apply", []):
		if e.has("chance") and e.chance + UPGRADE_STEP.chance * steps.get("chance", 0) < 1.0 and "chance" not in kinds:
			kinds.append("chance")
		if not e.has("chance") and "duration" not in kinds:
			kinds.append("duration")
	var out: Array[String] = []
	for k in kinds:
		if steps.get(k, 0) < UPGRADE_LIMITS[k]:
			out.append(k)
	return out


## A skill with a unit's upgrade steps (and mastery) applied.
static func upgraded_skill(skill_id: String, steps: Dictionary, mastery := false) -> Dictionary:
	var s: Dictionary = skill(skill_id).duplicate(true)
	var boost := MASTERY_BOOST if mastery else 0.0
	if s.has("power"):
		s.power = s.power * (1.0 + UPGRADE_STEP.power * steps.get("power", 0) + boost)
	if s.has("heal"):
		s.heal = s.heal * (1.0 + boost) + UPGRADE_STEP.heal * steps.get("heal", 0)
	if steps.has("crit"):
		s.crit_bonus = s.get("crit_bonus", 0.0) + UPGRADE_STEP.crit * steps.crit
	var cd: int = s.get("cooldown", 0)
	if cd > 0:
		s.cooldown = maxi(1, cd - steps.get("cooldown", 0) - (1 if mastery else 0))
	for e: Dictionary in s.get("apply", []):
		if e.has("chance"):
			e.chance = minf(1.0, e.chance + UPGRADE_STEP.chance * steps.get("chance", 0))
		else:
			e.turns = e.turns + steps.get("duration", 0)
	return s


## A skill's numbers in words, e.g. "One foe · Power 170% · Crit +25% · Cooldown 2".
static func skill_stats(s: Dictionary) -> String:
	var who := {"enemy": "One foe", "all_enemies": "All foes", "ally": "One ally", "all_allies": "All allies", "self": "Self"}
	var parts: PackedStringArray = [who.get(s.target, "")]
	if s.get("power", 0.0) > 0.0:
		parts.append("Power %d%%" % roundi(s.power * 100))
	if s.get("crit_bonus", 0.0) > 0.0:
		parts.append("Crit +%d%%" % roundi(s.crit_bonus * 100))
	if s.get("heal", 0.0) > 0.0:
		parts.append("Heals %d%%" % roundi(s.heal * 100))
	for e: Dictionary in s.get("apply", []):
		parts.append("%s %d turn%s%s" % [STATUSES[e.status].name, e.turns, "" if e.turns == 1 else "s",
			(" (%d%%)" % roundi(e.chance * 100)) if e.has("chance") else ""])
	if s.get("cooldown", 0) > 0:
		parts.append("Cooldown %d" % s.cooldown)
	return " · ".join(parts)


static func level_for_xp(xp: int) -> int:
	var level := 1
	while level < MAX_LEVEL and xp >= xp_to_reach(level + 1):
		level += 1
	return level


## Total XP needed to reach `level` from level 1.
static func xp_to_reach(level: int) -> int:
	return XP_STEP * level * (level - 1) / 2


## Random zombie waves for a territory. Threat 3+ ends with a Brute, or with `boss` (a legend id).
static func generate_waves(threat: int, rng: RandomNumberGenerator, boss := "") -> Array:
	var waves := []
	var count := 3 if boss != "" else clampi(threat, 1, 3)
	for w in count:
		var wave := []
		if w == count - 1 and boss != "":
			wave.append(boss)
		elif w == count - 1 and threat >= 3:
			wave.append("brute")
		# Grunts: 3 on their own (sometimes 4 far from home), 2 escorting a big one.
		var grunts := 2 if not wave.is_empty() else 3 + (1 if threat >= 4 and rng.randf() < 0.5 else 0)
		for g in grunts:
			var roll := rng.randf()
			if threat >= 3 and roll < 0.1:
				wave.append("riot")
			elif threat >= 2 and roll < 0.18:
				wave.append("screamer")
			elif threat >= 2 and roll < 0.26:
				wave.append("plague")
			elif threat >= 2 and roll < 0.38:
				wave.append("bloater")
			elif roll < 0.65:
				wave.append("runner")
			else:
				wave.append("shambler")
		waves.append(wave)
	return waves


## Stats for any enemy id: a zombie, or a legend boss (its build's stats + its own name and skills).
static func enemy(id: String) -> Dictionary:
	if ZOMBIES.has(id):
		return ZOMBIES[id]
	var legend: Dictionary = LEGENDS[id]
	var data: Dictionary = BOSS_BUILDS[legend.build].duplicate()
	data.merge(legend)
	data["boss"] = true
	return data


## Skill data with any `base` skill's fields filled in.
static func skill(id: String) -> Dictionary:
	var s: Dictionary = SKILLS[id]
	if not s.has("base"):
		return s
	var merged: Dictionary = skill(s.base).duplicate()
	merged.merge(s, true)
	return merged
