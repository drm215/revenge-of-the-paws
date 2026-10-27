# Revenge of the Paws — Design Outline

*Working title. Portrait, phone-first, turn-based squad RPG.*

## Pitch
The humans are gone. Zombies took them, and now the zombies are coming for everything else.
A ragtag pack of animals (a loyal dog, a reckless alley cat, a wise old owl, and more as you go)
band together to scavenge, survive, and push back the undead horde one ruined town at a time.

## Your world, your pet
The apocalypse starts **where you actually live**.
- **ZIP code (US):** first launch asks for your ZIP. It's looked up offline (bundled GeoNames data,
  `data/us_zips.csv`, CC BY 4.0, credited on the map screen) to get your town, state and US region.
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
  (US Census ZIP Code Tabulation Areas, `data/us_zcta.bin`, built by `tools/build_zcta.py`) plus
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
- **Reinforcements:** every territory held beyond home gives the pack +2.5% HP/ATK (max +40%).
- **Counterattacks:** every 3 map turns the horde attacks one of your border territories. You
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
  (max Lv 20); each level adds +6% HP, +4.5% ATK, +3% DEF.
- **Tech tree:** every animal gets one point per level to spend in its own tree, built from its
  own skills: three branches of 6 nodes, each needing the one above it. *Fang* (first skill's
  power/crit + Attack/Crit), *Hide* (Max HP/Defense + second skill), *Instinct* (third skill +
  Speed/Crit). A signature row: learn the role's signature skill at **Lv 10** (Tank: Last Stand,
  e.g. "Mama Bear"; Striker: Finishing Blow, e.g. "Bobcat Blitz"; Support: Rally, e.g. "Night
  Watch"; Disruptor: Hex Cloud, e.g. "Stink Bomb"; Bruiser: Stampede Charge), two upgrades to it,
  and **Mastery at Lv 20** (every skill +20% and recharges faster). 22 nodes vs. 19 points by
  Lv 20, so builds differ. **Training** buys stats directly any time (Max HP +8%, Attack +5%,
  Defense +6%, Speed +1, Crit +4%; up to 5/5/5/4/4), from the same points. Reset is free. Opens
  after a level-up and from each Pack card.
- **Survivors & swapping:** ~8 territories per map hide a survivor, an animal native to *that
  territory's* region (so maps that cross into another region offer its animals). Liberate it and
  it joins the pack near the pack's level. The **Pack** screen swaps who fights beside the pet.
- **Trinkets:** each legend drops its own trinket the first time it's beaten (Moth Wing Charm:
  +25% SPD/-10% DEF; Hollow-Bark Armor: +30% DEF/-15% SPD; Chupacabra Fang: heals 25% of damage
  dealt/-10% DEF; ...). Effects mix stat changes with lifesteal, thorns, regeneration, infection
  immunity, and wave-start effects (braced, or weaken all zombies); most are trade-offs. Maps with
  few or no legends hide plain trinkets in caches (gold chest on the map). One trinket per animal,
  equipped from the Pack screen. Data: `GameData.TRINKETS`.
- **Why the lineup matters** (data in `GameData`, bookkeeping in `Profile.after_battle`):
  - *Injuries:* animals knocked out in a battle you win fight the next 2 battles at -25% HP/ATK
    (a retreat carries its wounded home, so losses don't snowball).
  - *Recovery:* **Rest** at home heals all injuries and clears fatigue (costs a map turn);
    **Patrol** a territory you hold for an easier fight (threat -1) that earns XP.
  - *Fatigue:* -5% stats per battle fought in a row (max -20%); one battle benched resets it. The
    pet leader never tires.
  - *Territory conditions:* Streets (small city ZIPs), Forest, Riverside, Mountains, Badlands (by
    the region's terrain mix) or Night raid (15%). Animals suited to it get +15% ATK/DEF.
  - *Home turf:* animals native to the territory's region get +10% ATK/DEF.
  - *Counter zombies:* Riot Zombie (halves single-target damage: bring area attacks), Plague
    Carrier (infection spray: bring cleansers), Screamer (fast, stuns everyone).
  - *Legend weak spots:* +50% damage from one kind of animal, -40% from another (flyers: birds
    vs night animals; giants: forest vs city; stalkers: canines vs felines; lurkers: water vs desert).
  - *Bonds* (+8% ATK/DEF): Pack Hunters, Big Cats, Sky Watch, Night Shift, Trash Pact, Odd
    Couple (canine + feline), Neighbors (all wild members from one region).
  - *Bench:* benched animals get 50% XP and take duties (auto-filled from the bench: fastest
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

Balance (from `tests/simulate.gd`, decent-player AI): single 3-wave fights ~76–95% without a pet,
~91–99% with one; random play ~8–35%. With leveling, skill upgrades and trinkets, 40-territory campaigns finish in ~57–68 turns with 0–7 setbacks, the pack ending around Lv 10–16 with 6–8 recruits and 3–4 trinkets.

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
- **Between waves:** the party rests (+30% HP), fallen animals get back up at 25% HP,
  cooldowns and statuses reset.
- **Zombie AI:** uses its strongest ready skill; obeys Taunt; some types hunt the weakest target.
  Big zombies start with their big skill on cooldown, so it's telegraphed.

## Starting roster

### Animals
All stats and skills live in `scripts/data/game_data.gd` (`PETS`, `ANIMALS`, `REGIONS`). Skills share
a small set of mechanics with regional flavor names (e.g. Wombat's *Bum Block* is a taunt).

Future: recruit animals from other regions by travelling; more regions (Arctic, Middle East,
Pacific Islands); unique mechanics per animal (Raccoon steals, Crow marks targets).

### Zombies
| Zombie | Threat | Notes |
|---|---|---|
| Shambler | Basic | Infectious Bite spreads Infected |
| Runner | Fast, fragile | Hunts the weakest animal |
| Bloater | Slow, tanky | Explodes on death, damaging the whole party |
| Brute | Boss | Smash, plus a telegraphed Rampage that hits everyone |

Future: Screamer (buffs other zombies), Crawler (hides in back row), Hazmat (immune to Infected),
Zombie animals (corrupted versions of your recruits; a story beat).

## Progression (post-prototype)
- **Levels & gear:** animals level up; gear is scavenged junk (bottle-cap armor, tin-can helmets).
- **Skill trees:** each animal picks between two upgrades per skill.
- **The Den:** build rooms (Kitchen = heal between runs, Workshop = craft gear, Lookout = scout waves).
- **World map:** zones (Suburbs → Mall → Hospital → Downtown → Military Base), each with a boss.
- **Recruitment:** rescue caged animals during runs to unlock them.

## Mobile UX
- Portrait 9:16 (720×1280 base, stretches to taller phones).
- Tap a skill, then tap a highlighted unit. Strong skill = longer, juicier animation.
- Battle log for clarity; floating damage numbers; turn-order strip.
- Sessions are pausable at any point (state lives in plain data, easy to save).

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
body text (both SIL Open Font License, in `fonts/`), aliasing-free map borders and block-style
threat pips.

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
