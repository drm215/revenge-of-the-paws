# Revenge of the Paws — Design Outline

*Working title. Portrait, phone-first, turn-based squad RPG.*

## Pitch
The humans are gone. Zombies took them, and now the zombies are coming for everything else.
A ragtag pack of animals (a loyal dog, a reckless alley cat, a wise old owl, and more as you go)
band together to scavenge, survive, and push back the undead horde one ruined town at a time.

## Your world, your pet
The apocalypse starts **where you actually live**.
- **ZIP code (US):** first launch asks for your ZIP. It's looked up offline (bundled GeoNames data,
  `data/us_zips.gz`, CC BY 4.0, credited on the map screen) to get your town, state and US region.
  Outside the US: pick a world region (pre-selected from device locale/time zone) + optional town.
- **Starting animals are native to your region.** Each region has a pool of 4 local animals
  (tank, striker, support, wildcard); you pick your crew from it.
- **"Do you have a pet at home?"** If yes, pick species (dog, cat, bird, rabbit, lizard, hamster)
  and name. Your pet is the **pack leader**: +15% stats, and a **leadership aura** giving every
  other living ally +10% ATK and DEF. If the leader falls, the aura is gone.
  Party = pet + 2 locals, or 3 locals.

| Region (states) | Local animals |
|---|---|
| New England (ME NH VT MA RI CT) | Black Bear, Red Fox, Horned Owl, Moose |
| Mid-Atlantic (NY NJ PA DE MD DC) | Raccoon, Opossum, Red-tailed Hawk, Skunk |
| Appalachia (VA WV KY TN) | Black Bear, Bobcat, Horned Owl, Whitetail Deer |
| Carolinas & Georgia | Alligator, Bobcat, Blue Heron, Whitetail Deer |
| Florida | Alligator, Florida Panther, Blue Heron, Armadillo |
| Gulf South (AL MS LA AR) | Alligator, Bobcat, Blue Heron, Armadillo |
| Great Lakes (OH MI IN IL WI MN) | Badger, Gray Wolf, Horned Owl, Whitetail Deer |
| Great Plains (IA MO ND SD NE KS) | Bison, Coyote, Red-tailed Hawk, Whitetail Deer |
| Texas & Oklahoma | Armadillo, Coyote, Turkey Vulture, Roadrunner |
| Desert Southwest (AZ NM NV) | Gila Monster, Coyote, Turkey Vulture, Roadrunner |
| Rocky Mountains (CO UT WY MT ID) | Black Bear, Cougar, Bald Eagle, Elk |
| Pacific Northwest (WA OR) | Sea Lion, Cougar, Bald Eagle, Elk |
| California | Sea Lion, Bobcat, Sea Otter, Coyote |
| Alaska / Hawaii | Grizzly, Gray Wolf, Bald Eagle, Moose / Monk Seal, Mongoose, Nēnē, Wild Boar |
| Outside the US | 7 world regions (Europe, Asia, Africa, …), 4 animals each |

## The map: Risk-style liberation
- **Territories are your real neighborhood, drawn with real borders.** Your ZIP's actual area
  (US Census ZIP Code Tabulation Areas, `data/us_zcta_core.bin` plus an outline file per ZIP prefix in `data/zcta/`, fetched
  on the web the first time a map needs it and then kept on the device, built by `tools/build_zcta.py`) plus
  the 40 nearest connected ZIP areas, grown outward along real shared borders. Rivers/water that
  cut the region get a bridge/ferry link to the nearest area. Areas too small to read only get a
  label when zoomed in. Outside the US: generated Voronoi districts around your town.
- **The frontier grows.** Liberating an edge territory reveals the real ZIP areas bordering it, so
  the map expands in whatever direction you push, without limit. Threat keeps rising past 5
  (zombies +25% per step beyond), legends' lairs appear once the frontier reaches their
  real hometown ZIP areas, and new areas can hold survivors (25%) or a cache (12% at threat 5+). Revealed
  batches are saved and replayed on load. The map opens framed on your front line; zoom out to
  see it all. (Non-US maps stay a fixed 40 districts for now.)
- **You start holding your home ZIP.** You can only attack territories bordering ones you hold.
- **Threat 1–5** rises with distance from home: 1 = one wave, 2 = two waves, 3+ = full three-wave
  fight with a Brute; zombies get +8% / +18% / +30% / +42% stats at threat 2–5.
- **The horde keeps up:** once the pack outgrows a territory, its zombies scale to the pack's
  strongest possible lineup (pet plus highest-level animals, whoever is fielded, so benching
  doesn't fool them): 2 levels below it at threat 1, one level closer per threat (even at threat 3,
  2 above at threat 5). XP still comes from the territory's own strength. Levels convert to zombie
  strength with `GameData.LEVEL_STRENGTH`, measured with the simulator (the zombie strength a pack
  of each level beats ~85% of the time); the map notes when a horde was matched to the pack.
  A territory's threat and level are fixed when it's first discovered (`Territory.met_level`, saved
  in the shared map, so teammates see the same numbers). Only the horde changes them: a nest
  spreading into it, or losing a counter defense there (+1 threat, so +1 level); failed attacks
  thin it. Legends are the exception: they always match the pack of the day.
- **Legends fight like raid bosses** (`GameData.LEGEND_*`, `Battle._advance_legend`): below 66% HP
  they call a Runner and a Shambler (no XP), below 33% they hit 30% harder for good, and they keep
  winding up Cataclysm, which hits the whole pack unless the legend is stunned (cancels it) or the
  pack Guards (halves it). After a stun a legend is stun-proof for `LEGEND_STUN_PROOF` (2) of its
  turns, Knockdown included, so it can't be stun-locked (a fox's Dirty Trick plus heavy hits once
  stunned the Wampus Cat on over half its turns).
  Below 10% HP comes the **Last Gasp** (`LEGEND_LAST_GASP_*`): a countdown of 3 of its turns, shown
  big on screen, then every animal loses 70% of its max HP (DEF, Guard and stuns don't help; the
  count runs even while it's stunned). Kill it first; if it survives, it counts again.
  When a legend fight ends, win or lose, a **replay** plays (`LegendRecap` records it,
  `LegendRecapScene` shows it): the entrance, every phase, Cataclysms and the Last Gasp, the
  biggest blows each way, knockouts and the final blow, then an end card with the rounds and the
  MVP. About 20 seconds; it moves on by itself and a tap skips it. Worked out from HP alone, so every raid device agrees. Tuned so the
  simulator's AI wins about 10% of the time at Lv 10 and above; real players should do better.
- **Sweep**: attackable land `SWEEP_LEVEL_GAP` (8) or more levels below the fighting pack's level
  can be taken without a fight (Sweep, beside Attack!): a map turn, no injuries, `SWEEP_XP_SHARE`
  of the XP, no siege damage. Lairs, warlords and counterattacks are always fought.
- **Reinforcements:** the pack starts at +5% HP/ATK; land held beyond home and linked to it adds +1% per 20
  territories (max +30%): slow to build, big on a large map. The Guide spells it out.
- **Warlords:** from turn 10, nests raise named champions ("Rotjaw, the Butcher of Lebanon") that
  march toward home every 4 turns, one at a time per nest, raising threat where they tread. They're
  on the map: win where one stands to kill it for its treasure. If one reaches held land it attacks,
  in person; beat it there and it dies, lose and it takes the land.
- **Counterattacks:** every 7 map turns the horde attacks one of your border territories. These are
  rare and dangerous: they match the pack of the day (`Campaign.zombie_strength`), and land really falls. You
  must defend it before attacking elsewhere; lose and it falls back to the dead.
- **Regional legends are the bosses.** ~30 US folklore cryptids live at their real hometowns
  (Mothman: Point Pleasant WV; Woodbooger: Norton VA; Jersey Devil: Pine Barrens; Skunk Ape:
  Everglades; Chupacabra: Texas; Bigfoot: Pacific NW; lake monsters; ...). A legend's **lair is the
  real ZIP area of its hometown** and appears only when the expanding map reaches it; the map
  lists "Rumors" (nearest legends not yet on the map, with distance in miles and direction) so players know
  where to push. Outside the US, one legend per world region sits on the far edge (Yeti, Black
  Shuck, Drop Bear, ...). We stick to folklore cryptids and avoid figures sacred to living
  Indigenous traditions.
- **Zombie waves are randomized per territory** (shamblers, runners, bloaters; Brute or legend in
  the last wave at threat 3+), seeded by territory so a retry is a fair rematch.
- **40 territories**; drag to pan, pinch or mouse-wheel to zoom.
- **Lairs face their legend:** a lair sits on the map edge pointing toward the legend's real home
  (Loveland Frogman west of Point Pleasant, Flatwoods Monster east).
- **Attrition:** each failed attack thins that territory's horde by 8% (down to 70%), so no
  territory can wall the campaign forever.
- **Leveling:** every animal in the pack (pet included) earns XP from each fight: zombies 10–40,
  legends 120, scaled by the territory's threat; half XP on a retreat. Level L→L+1 costs 120×L XP
  (no top level); each level adds +6% HP, +4.5% ATK, +3% DEF.
- **Tech tree:** every animal gets one point per level to spend in its own tree, built from its
  own skills: three branches of 6 nodes, each needing the one above it. *Fang* (first skill's
  power/crit + Attack/Crit), *Hide* (Max HP/Defense + second skill), *Instinct* (third skill +
  Speed/Crit). A signature row: learn the role's signature skill at **Lv 10** (Tank: Last Stand,
  e.g. "Mama Bear"; Striker: Finishing Blow, e.g. "Bobcat Blitz"; Support: Rally, e.g. "Night
  Watch"; Disruptor: Hex Cloud, e.g. "Stink Bomb"; Bruiser: Stampede Charge), two upgrades to it,
  and **Mastery at Lv 20** (every skill +20% and recharges faster). 22 tree nodes vs. 19 points by
  Lv 20, so builds differ. **Training** buys stats directly any time (Max HP +8%, Attack +5%,
  Defense +6%, Speed +1, Crit +4%; up to 15/15/15/6/8), from the same points; past Lv 20 that's where points go. Reset is free. Opens
  after a level-up and from each Pack card.
- **Survivors & swapping:** ~8 territories per map hide a survivor, an animal native to *that
  territory's* region (so maps that cross into another region offer its animals). Liberate it and
  it joins at a quarter of the strongest pack's level. The **Pack** screen swaps who fights beside the pet.
- **The pack holds 6** (`PACK_LIMIT`, pet included): 3 fight, the rest are reserves. Everyone
  else waits in the **Stable**: no fighting, no XP, no duties. A recruit goes to the Stable when the
  pack is full. Sending a reserve to the Stable is free; bringing one back takes a map turn and needs
  a free slot, so swapping in a specialist for a push is a real decision. Older saves keep their
  team and highest-level reserves; the rest are stabled on load.
- **Trinkets:** each legend drops its own trinket the first time it's beaten (Moth Wing Charm:
  +25% SPD/-10% DEF; Hollow-Bark Armor: +30% DEF/-15% SPD; Chupacabra Fang: heals 25% of damage
  dealt/-10% DEF; ...). Effects mix stat changes with lifesteal, thorns, regeneration, infection
  immunity, and wave-start effects (braced, or weaken all zombies); most are trade-offs. Maps with
  few or no legends hide plain trinkets in caches (gold chest on the map). One trinket per animal,
  equipped from the Pack screen. Data: `GameData.TRINKETS`. **Fusion** (Fuse in the trinket
  picker): two trinkets become one with every effect added up, both drawbacks included; both are
  used up. A fused trinket can't be fused again, and two wave-start effects can't share one.
  Saved as `fuse:a+b`; `GameData.trinket()` builds it.
- **Supply lines:** a held territory must link back home through held land. Cut off (when a
  counterattack takes a link), it adds no held bonus, can't launch attacks, is defended at +1
  threat, and falls to the horde after 3 map turns unless the link is retaken (the map fades it
  and counts down). Counterattacks go for the chokepoint that would cut off the most land 70% of
  the time, and say what's at stake. Data: `GameData.CUT_OFF_*`, `Campaign.supplied()`.
- **Horde migration:** the 2 farthest max-threat areas of the starting map (not lairs) are nests,
  marked on the map. Every 3 map turns each raises one unheld area next to its infested ground
  by +1 threat (each area at most +2, never above the nest's threat), most infested first, so
  the danger creeps toward the pack until around turn 45. Liberating a nest stops it for good.
  Saved as `spread`; data `GameData.NEST_COUNT`, `MIGRATE_EVERY`, `MAX_SPREAD`.
- **Teams** (co-op, Cloud screen; US ZIP maps only; `scripts/net/team.gd`, `server/teams.sql`): up
  to 4 signed-in players share one map built from all their homes. A team belongs to one saved
  game (`Profile.team_id`; an account can be on one team per game): a new game starts solo and
  fresh (only home liberated), and right after its setup asks "Play with a partner?" (Invite: a
  team for this game and a code to share; Join: their code; Play solo). The Cloud screen lists the
  account's other teams so one can be played in the current game. Each home grows its own patch
  as big as a solo map; patches that touch merge. Threat counts from the nearest home, supply links
  to any home, each home gets 2 nests, and the horde's clock (counterattacks, spread, cut-off
  countdown) runs `pace()` = team size times slower, since every member's moves advance it.
  Everyone keeps their own critters; liberating is shared, and whoever liberates gets the
  survivor and trinket. After each battle for a territory (attack or defense, won or lost; not
  patrols), every other member whose home links to the fighter's through held land is owed 10% of
  its XP (`TEAM_XP_SHARE`), for every animal in their pack; no link, no XP. The shared map keeps
  each player's running total (`shared_xp`) and each profile what it has collected (`team_xp`).
  **Catch-up**: the shared map also keeps each player's pack level from their latest fight or
  patrol (`pack_levels`); a pack below the team's strongest earns +10% XP per level behind, up to
  double (`CATCH_UP_*`), on its own fights, patrols and sweeps (not on what it shares). Join with a 6-character code. Moves apply at once on the device and queue;
  Team.flush() replays them on the newest shared map (no rewards on replay) and saves it only if
  the version is unchanged, retrying on a teammate's newer map. A territory a teammate already
  freed just costs the turn. The map shows teammates' homes (cyan) and a feed of recent moves;
  it polls every 20 s while on a team.
- **Legend raids** (teams; `scripts/net/raid.gd`, `scripts/ui/raid_screen.gd`, `server/raids.sql`):
  in a legend's lair, Ready the pack offers "Start a raid with your team". It opens a lobby (and
  a chat ping); teammates join from the map's "Join the raid" button. Each player picks the 3
  critters they bring and readies up; the opener starts with everyone ready (up to 4 players, 12
  critters). Each player controls their own critters, live: every device runs the same battle
  from the raid's seed and config (the lair's own level; the legend grows with the raiders), and only
  moves travel, numbered in order; the first move posted for a number stands, so if a player
  doesn't move within 45 s any device plays that turn with the AI. Each pack keeps its own
  leader aura, bonds, terrain and home-turf bonuses, injuries and fatigue; knockouts injure their
  owner's critters. The legend grows with the players who fight (`GameData.LEGEND_GROWTH`: HP x2.9
  / x4.8 / x6.6, ATK x1.6 / x2.2 / x2.7 for 2 / 3 / 4), tuned so every raid size wins about as
  often as one pack alone (the simulator's AI wins ~20%; real players, who play better, should
  find legends a real fight); a raid of one is a normal legend fight. XP is split
  between the players; every player gets the legend's trinket on a win. The first device to
  report the end stores the outcome and records the territory on the team map; each player
  collects their own share once (`Profile.claim_raid`), even if they closed the game. Big raids
  draw two compact cards per row. A fight everyone left can't be picked up again: anyone can call it off,
  a raid whose lair has fallen is called off by itself, and unfinished raids lapse after 2 hours.
  With no connection at the end of a fight the player can still leave: the result is kept on the
  device and sent once back online, and the map and their rewards catch up (`Raid.finish_later`).
- **Team chat** (`scripts/net/chat.gd`, `server/chat.sql`; Chat button in the footer on team
  maps, with the unread count): six one-tap quick phrases, typed messages (200 characters, 5 per
  10 s), and map pings (Ping beside the territory action) that outline the territory in cyan on
  teammates' maps for 10 minutes. Ping on a pinged territory becomes Unping (clears it for everyone),
  and pings clear themselves once done: horde land when it's liberated, a counterattack when it's
  over. Polls every 10 s on a team; the server keeps 200 per team.
- **Loading screen:** `art/splash.png` (drawn by `tools/make_splash.gd`) is the boot splash, and
  the web page matches it (dark background, gold progress bar, "Rallying the pack...").
- **Saves** (`scripts/data/saves.gd`, `scripts/ui/save_screen.gd`): any number of games, each in
  its own folder (`user://saves/<id>/`). After the loading screen the save picker lists them, newest
  first (pet and town, level, territories held, turn, last played), with Play, Delete (asks twice)
  and New game; the map's Saves button comes back here (there is no Setup button any more). A save from before slots becomes the
  first one. The cloud keeps every game (one `saves` row per player and game) and syncs them one
  by one: a game this device doesn't have downloads, the newer copy of each game wins, the same
  game changed on both devices asks which to keep, and deleting a game deletes its cloud copy.
  Only the game being played restarts when its copy downloads.
- **Clearing states and regions:** free every ZIP area that's really in a state (counted by
  `tools/build_state_areas.py`: Virginia has 903, DC 57) and the state is cleared; clear every
  state of a region and the region is too (`Campaign.cleared`, shared on a team). Each player on
  the map then gets one permanent bonus, rolled at random (`GameData.CLEAR_BONUSES`: +8% HP, ATK or
  DEF, +10% SPD or +5% crit; double for a region), and gives it to any critter of theirs. Once
  each, for good. A territory's info shows its state's progress.
- **Dungeon waves**: 2 zombies at first, then 3, 4, 5 (wave 10) and 6 (wave 20). Every 5th wave is a
  Brute wave; past wave 10 the others bring a lone Brute. Mixed waves avoid repeats, favour the
  dungeon's signature zombie (by terrain: bloaters in water, riot gear in the mountains...), and
  between Brute waves from wave 8 comes a named wave of one kind (Swarm, Plague Ward, Riot Line,
  Bloat Tide, The Choir). Kills pay a quarter of their usual XP; new depths pay the treasure.
- **Brute targets** (`EYEING_ZOMBIES`: Brutes, warlords): at the end of each of its turns (and as its
  wave starts) it picks the reachable animal with the least HP, logs "Brute eyes X" and tags that
  card "BRUTE'S TARGET"; its next single-target hit goes there unless a taunt pulls it away.
- **Well rested** (`RESTED_*`): an animal that sits out 5 battles in a row (in the pack, not the
  Stable) is well rested for its next 3 fights: +15% ATK/DEF and x1.5 XP.
- **The week** (siege weeks, Monday UTC): a **mutation** (`MUTATIONS`) changes every territory
  fight, never legends: zombie HP/ATK/SPD, a boost for tagged animals, +crit, an extra zombie per
  wave, or more XP. Tests set `PAWS_NO_MUTATION=1`. A **week goal** (`WEEK_GOALS`: free / win /
  hold) is shared on the team map (`goal_progress`), `per_player` times the team size; finishing it
  gives each player a cache trinket and half a level of XP for every animal (pet included).
- **Perfect waves**: clear a wave with no animal taking any damage and the whole pack gets +10% ATK
  (stacking to +30% over perfect waves in a row) until any animal is hurt. The wave banner shows it.
- **Dungeons** (Enter, from the entrance's territory once it's held): each region has one, set in
  its best-known wild place (the Everglades, the Old Coal Mine, the Paris Catacombs...;
  `GameData.DUNGEONS`). On a US map the entrance is the ZIP area nearest the real place (Appalachia,
  VA for the coal mine), and any dungeon whose place is on the map appears there, marked with a
  doorway; until your own region's is in reach, the map points the way to it. Generated maps put
  their region's part way out from home. Endless waves that climb
  0.6 zombie levels a wave; every 5th wave adds a Brute (two on screen at most: each past that
  makes them 8% tougher), and the mix grows nastier. Half HP back between waves. Tuned so the
  simulator's AI reaches about wave 12 at pack Lv 10, 21 at Lv 20 and 26 at Lv 30. Clearing a depth for
  the first time pays once per saved game (`DUNGEON_REWARDS`: XP and trinkets up to wave 40, the
  region's own trinket at 25, a legendary at 40); waves give no other XP. Runs start from wave 1 or
  any cleared checkpoint (every 10), cost no map turn and leave no injuries. Leave between waves
  or fall: either way you keep what you won. Deepest waves go on a leaderboard per region
  (`server/dungeons.sql`).
- **Weekly siege** (map footer, co-op): one giant horde a week (`GameData.SIEGES`, new each
  Monday UTC) shared by every signed-in player. Each zombie a pack destroys, in battles and
  patrols, hits it for the territory's threat. It breaks in stages (`GameData.SIEGE_STAGES`: 500,
  2000, 5000 and 10000 damage per pack taking part), each with a reward for everyone who helped: XP
  and trinkets, the last one legendary. A fight's results show its damage, and the map announces a
  stage breaking and shows rewards waiting on the Siege button (last week's stay claimable for a
  week). Damage queues on the device (also while logged out) and is sent with the cloud sync, at
  most 5000 an hour per player; the leaderboard shows the pet and region, never the town. Server
  side: `server/siege.sql`.
- **Sync**: every save goes to the cloud at once (`Cloud.SYNC_DELAY` only gathers one action's
  saves), and a save made while a sync is running goes up right after it.
- **Sync safety**: when the game being played can't back up (an upload refused, or more than
  `Cloud.BACKUP_WARN_MINUTES` with changes the cloud hasn't), the map shows a red warning; tap to
  retry. Every failure (read, upload, conflict, a cloud copy replacing different progress, an
  expired login) is reported to `sync_events` (server/sync_events.sql), and battle logs carry the
  save slot, minutes without a backup and the last upload error. A cloud copy that replaces a
  different copy on the device keeps the old one; the save picker offers it back.
  server/admin_queries.sql finds players whose fights arrive but whose saves don't.
- **Battle log** (for balancing): every finished fight sends a report (`Battle.report()`: the
  setup (including whether it was an assault or had a warlord), each critter's level, row, stats, damage dealt and taken, skills used and knockouts, the
  legend's stats and HP left, rounds per wave) with the cloud sync, queued while offline (newest
  30). Raids log once. Reports carry no names; `tools/battle_report.py` reads them back.
  Server side: `server/battle_logs.sql`, which also limits them (120 an hour and the newest 500 per
  player, 180 days); the siege caps each player at 5000 damage an hour, and the rest waits.
- **Team check-in** (`Pulse`, `server/pulse.sql`): teammates' moves, chat and the raid in one
  request, every 12 s while playing, every 60 s after 2 idle minutes, none while the page is hidden.
  The map and raid only come back when they changed.
- **Why the lineup matters** (data in `GameData`, bookkeeping in `Profile.after_battle`):
  - *Injuries:* animals knocked out in a battle you win fight the next 2 battles at -25% HP/ATK
    (a retreat carries its wounded home, so losses don't snowball).
  - *Recovery:* **Rest** at home heals all injuries and clears fatigue (costs a map turn);
    **Patrol** a territory you hold for an easier fight (threat -1) that earns XP.
  - *Auto mode* (parked: `GameData.AUTO_MODE_ENABLED` is false, so no footer button or auto-fights): territories and counterattacks at least 10 levels below the
    pack leader (the pet, else the highest-level animal) are fought one at a time after a short
    pause on the map: the AI plays the pack's turns on the battle screen ("Take control" hands it
    back) and the fight earns half XP. Legend lairs are never auto-fought; a retreat turns it off.
    Territory level is the pack level that usually takes it on: threat 1-5 = Lv 1, 3, 5, 8, 9.
    Auto mode measures a territory by its own level, not the pack-scaled one, but fights the
    scaled horde.
  - *Fatigue:* -5% stats per battle fought in a row (max -20%); one battle benched resets it. The
    pet leader never tires.
  - *Territory conditions:* Streets (small city ZIPs), Forest, Riverside, Mountains, Badlands (by
    the region's terrain mix) or Night raid (15%). Animals suited to it get +15% ATK/DEF.
  - *Home turf:* animals native to the territory's region get +10% ATK/DEF.
  - *Counter zombies:* Riot Zombie (halves single-target damage: bring area attacks), Plague
    Carrier (infection spray: bring cleansers), Screamer (fast, stuns everyone, frenzies the
    other zombies), Medic (threat 3+; raises a destroyed zombie at 40% HP, once per zombie, no
    XP the second time: kill it first).
  - *Legend weak spots:* +50% damage from one kind of animal, -40% from another (flyers: birds
    vs night animals; giants: forest vs city; stalkers: canines vs felines; lurkers: water vs desert).
  - *Bonds* (+8% ATK/DEF): Pack Hunters, Big Cats, Sky Watch, Night Shift, Trash Pact, Odd
    Couple (canine + feline), Neighbors (all wild members from one region).
  - *Bench:* reserves (pack members not fighting) get 50% XP and take duties (auto-filled from the bench: fastest
    scouts, toughest guards; a duty passes on when its holder joins the lineup; Duty button to
    change): Scout (reveals waves), Forage (25%
    XP stash / 5% trinket per battle), Guard (counterattacks every 5 turns instead of 3).
- **Ready the pack:** every fight (attack, defend, patrol, lair) opens a pre-battle pack screen
  first: the place, its terrain and home-turf bonus, the waves if a scout is out, and which
  animals get a bonus here. Adjust the lineup, duties, trinkets or tech trees, then Fight! (or
  Back to the map).
- **Lair briefing:** attacking a lair first shows the legend's sprite, lore, stats at this threat,
  each ability and when it fires, its escorts, and a tip for beating it.
- **Losing an attack** costs a turn but nothing else. Liberate all 40 to free your neighborhood.
- Progress saves to `user://campaign.cfg`, keyed to your home ZIP/region.

Balance (from `tests/simulate.gd`, decent-player AI that stuns or braces against wind-ups,
kills Medics and Screamers first, plays combos and respects rows): single 3-wave fights ~56–97%
without a pet, ~76–97% with one; random play ~6–44%. With leveling, skill upgrades and trinkets,
40-territory campaigns finish in ~53–84 turns with 2–19 setbacks with a pet (~55–80 turns, 4–15
setbacks without), the pack ending around Lv 12–16 with 6–8 recruits and 3–10 trinkets. (Before the horde scaled with the
pack, rest was halved and zombies focused fire: fights 76–99%, campaigns 48–60 turns with 0–6
setbacks.)

## Pillars
1. **Short, tactical turns.** A battle fits in a 3–5 minute session. Every turn should have a
   meaningful choice (who to hit, when to burn a cooldown, who to protect).
2. **Animals feel like animals.** Abilities come from real animal behavior: dogs guard, cats
   pounce, owls see everything, raccoons steal, skunks... you get it.
3. **One thumb.** Everything is playable one-handed in portrait. Tap a skill, tap a target.
4. **Hopeful apocalypse.** Overgrown cities, rusted cars, sunsets. Grim enemies, warm heroes.

## Core loop
```
Map ──► attack a bordering territory ──► 1–3 waves ──► territory held (+reinforcements)
 ▲                                                                       │
 └──── defend counterattacks · later: loot, level up, build the Den ◄────┘
```

## Combat rules (prototype implements these)
- **Party** of 3 animals vs a **wave** of 1–4 zombies. Several waves per run.
- **Turn order:** each round, all living units act in order of Speed (ties go to animals).
  The next turns are shown at the top of the screen.
- **Skills:** each unit has 2–3 skills. Basic attacks are always available; strong skills have
  a cooldown (in the unit's own turns).
- **Damage:** `ATK × power × 50/(50+DEF) × (0.9–1.1)`, crits ×1.5.
- **Statuses:**
  | Status   | Effect                                                      |
  |----------|-------------------------------------------------------------|
  | Taunt    | Zombies must target this unit                               |
  | Guard    | DEF ×1.6                                                    |
  | Infected | Takes 6% max HP at the start of each turn; cured by healing |
  | Stunned  | Skips its next turn                                         |
  | Weakened | ATK ×0.7                                                    |
  | Frenzied | ATK ×1.25 (zombies, from a Screamer)                        |
- **Between waves:** the party rests (+15% HP) and statuses clear. An animal knocked out sits the
  next wave out and gets back up at 25% HP the wave after. Cooldowns keep running: the rest
  counts as one turn.
- **Telegraphed attacks:** big area attacks (Brute's Rampage, Plague Spit, the legends' area
  skills) take a wind-up turn, shown on the zombie's card and in the log, then land on its next
  turn at ×1.75 power. Stunning the zombie in between cancels it (the cooldown still runs);
  animals with Guard up take half; Taunt pulls single-target hits.
- **Enrage:** past round 8 of a wave, zombies gain +10% ATK every round.
- **Rows:** each side has a front and back row. Single-target attacks can't reach the back row
  while at least 2 stand in front; area attacks hit everyone. Birds, Runners and flying legends
  reach the back row, and a taunting animal can always be hit. Single-target attacks from the back
  row deal -25% (birds excepted). Tanks, Strikers and Bruisers default to the front, Supports and
  Disruptors to the back; the Row button on each Pack tile changes it. Screamers, Plague Carriers
  and Medics stand at the back. Battle cards sit closer to the middle in front, nearer the edge
  in back.
- **Combos** (pack only; the log and a floating COMBO! call them out, skill descriptions name them):
  *Opening*: a skill with a crit bonus always crits a stunned zombie. *Knockdown*: a heavy hit
  (power 150%+) stuns a weakened zombie (a second way to cancel a wind-up). *Follow-up*: +25% on
  the zombie an ally hit on the turn just before (any zombie turn in between breaks it).
- **Zombie weak points** (`GameData.ZOMBIE_WEAKNESS`): animals with the right tag deal +50% to a
  zombie type: Shambler/Canine, Runner/Feline, Brute/Mountain, Screamer/Night, Medic/Urban,
  Bloater/Water (and no death blast when they finish it), Plague Carrier/Scavenger (and immune to
  its infection). Bruisers ignore a Riot Zombie's armor instead. Zombie cards show "Weak: X", the
  log explains it on the first hit and WEAK SPOT! floats on each; scouting lists the weak spots of
  the waves ahead and each critter's Details lists what it counters.
- **Zombie AI:** uses its strongest ready skill; obeys Taunt. Single-target hits focus fire: 80% of
  the time on an animal they can knock out, otherwise 50% on an animal that heals its allies; some
  types hunt the weakest target. Shamblers hit 15% harder for each other Shambler standing.
  Big zombies start with their big skill on cooldown.

## Starting roster

### Animals
All stats and skills live in `scripts/data/game_data.gd` (`PETS`, `ANIMALS`, `REGIONS`). Skills share
a small set of mechanics with regional flavor names (e.g. Wombat's *Bum Block* is a taunt).

Future: recruit animals from other regions by travelling; more regions (Arctic, Middle East,
Pacific Islands); unique mechanics per animal (Raccoon steals, Crow marks targets).

### Zombies
| Zombie | Threat | Notes |
|---|---|---|
| Shambler | Basic | Infectious Bite spreads Infected; stronger in groups |
| Runner | Fast, fragile | Hunts the weakest animal |
| Bloater | Slow, tanky | Explodes on death, damaging the whole party |
| Brute | Boss | Smash, plus a telegraphed Rampage that hits everyone |
| Riot | Armored | Halves single-target damage |
| Plague Carrier | Support | Telegraphed infection spray |
| Screamer | Fast | Scream may stun everyone and frenzies the other zombies |
| Medic | Support | Raises a destroyed zombie at 40% HP |

Future: Crawler (hides in back row), Hazmat (immune to Infected), Zombie animals (corrupted
versions of your recruits; a story beat).

## Progression (post-prototype)
- **Levels & gear:** animals level up; gear is scavenged junk (bottle-cap armor, tin-can helmets).
- **Skill trees:** each animal picks between two upgrades per skill.
- **The Den:** build rooms (Kitchen = heal between runs, Workshop = craft gear, Lookout = scout waves).
- **World map:** zones (Suburbs → Mall → Hospital → Downtown → Military Base), each with a boss.
- **Recruitment:** rescue caged animals during runs to unlock them.

## Feel
- `BattleFx` watches a battle and changes nothing in it, so raid devices can't drift apart: shake, a
  beat's freeze on crits and big hits, flying bits, slow motion and a push-in on the last blow,
  combos slammed across the screen. `Sound` plays original chiptune effects and music from
  `tools/make_audio.py` (map, battle and legend themes), with a mute button on the map.
- Legend fights are events: a dark entrance with footfalls, roar, portrait and name (a tap skips
  it); "REINFORCEMENTS!" and "ENRAGED!" moments, with the legend swelling, the screen's edges pulsing
  red and the music speeding up; a banner and dimmed screen while Cataclysm winds up, then
  "INTERRUPTED!" or a red blast and "SURVIVED!"; and a chest bursting with its trinket.

- Freeing a territory plays on the map (`Campaign.take_liberation`, `MapScreen._play_liberation`,
  `MapView.play_liberation`): green rolls in from the held land next door, fireworks, the pet and any
  rescued animal run across, and "ABINGDON IS FREE!" across the map, with what it means under it:
  a new state reached, a legend dead, a round number of territories, or the count so far. Nothing
  waits for it; a teammate's move arriving meanwhile rebuilds the map when it ends.
- The horde is seen moving (`Campaign.horde_news`, by comparing with what the map last showed, so a
  teammate's turn counts too): the view swings over, zombies march in from next door, a red tide
  washes over land it spreads into or takes, and a siren and red flash mark a counterattack.

## Mobile UX
- Land you can attack is shaded by level, pale for the lowest in reach and dark for the highest.
- Portrait 9:16 (720×1280 base, stretches to taller phones).
- Tap a skill, then tap a highlighted unit. Strong skill = longer, juicier animation.
- Battle log for clarity; floating damage numbers; turn-order strip.
- Sessions are pausable at any point (state lives in plain data, easy to save).
- The map draws in layers (`MapView`): shapes stay drawn and just move when panned, what glows
  redraws at 20 fps, labels when the view changes. Call `refresh()` after changing what it shows.

## Art (current)
8-bit style sprites for every unit. Pipeline: `tools/make_sprites.py` draws vector portraits into
`art/units/<id>.svg` (facing right), then `tools/pixelate.gd` turns them into 40x40 pixel sprites
in `art/pixel/<id>.png` (ENDESGA 32 palette, majority-vote downscale, 1px outline). The game shows
them with nearest-neighbor scaling; enemies are mirrored. Drop real pixel art into `art/pixel/`
with the same file name to replace any of them. Battle layout: animals stacked on the left facing
right, the horde on the right facing left; gold ring = acting unit, pulsing cyan = valid target,
units hop forward when they act.

UI is retro too (`scripts/ui/retro.gd`): ENDESGA 32 colors everywhere, square chunky panels and
buttons with a thick bottom "lip", Press Start 2P for titles/buttons/tags and Pixelify Sans for
body text (both SIL Open Font License, in `fonts/`), aliasing-free map borders, and
threat shown by shading (land you can attack goes darker as it gets tougher).

## Art direction (later)
Chunky hand-drawn 2D, warm color animals against desaturated green/grey zombies. Overgrown
ruins backgrounds. Sprites idle-bob; attacks are quick lunges and squash-and-stretch.

## Roadmap
1. **Prototype (done):** first-launch setup (ZIP or region, pet leader, local crew), Risk-style
   map of real nearby ZIPs with threat, reinforcements and counterattacks; 15 regions, 48 wild
   animals + 6 pet species, 4 zombie types, placeholder art.
2. **Vertical slice:** real sprites + animations, sound, 1 zone with map, save/load, levels.
3. **Content:** 6+ animals, 10+ zombie types, 5 zones, Den building.
4. **Ship:** Android/iOS exports, tutorial, balancing, store assets.
