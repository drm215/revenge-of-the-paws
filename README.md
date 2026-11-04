# Revenge of the Paws

A phone-first, turn-based 8-bit RPG: your real-life pet and the animals native to where you live
take back your actual neighborhood, ZIP code by ZIP code, from zombies and local cryptids.

Play: **https://revengeofthepaws.com**

Built with [Godot 4.7](https://godotengine.org). Design notes: [DESIGN.md](DESIGN.md).

## Running locally

Open the folder in Godot 4.7 and press F5. Tests (`tests/checks/*`, a fake Supabase server and a
two-device raid; each check gets empty user data, so real saves are safe, and deploys run them):

```
python tests/run_all.py            # everything
python tests/run_all.py syncnow    # one check
```

Balance check (plays simulated campaigns):

```
godot --headless --path . --script res://tests/simulate.gd
```

## Web build and deploy

```
godot --headless --path . --export-release "Web" build/web/index.html   # needs Godot's web export templates
python tools/serve_web.py --https                                        # test on a phone on the same Wi-Fi
tools/deploy_web.sh                                                      # build and publish (gh-pages branch)
```

The site is a Render static site that serves the `gh-pages` branch (no build command, publish
directory `.`) and redeploys on every push.

## Cloud saves

Accounts and saves live in a Supabase project (`scripts/net/cloud.gd`). Cloud saves are off while
`scripts/net/cloud_config.gd` has an empty `URL`. To turn them on:

1. Create a free project at https://supabase.com and run `server/supabase.sql`, then
   `server/siege.sql` (the weekly siege), `server/teams.sql` (teams), `server/chat.sql` (team
   chat) and `server/raids.sql` (legend raids) and `server/battle_logs.sql` (battle log), in its SQL Editor.
2. Authentication → URL Configuration: set **Site URL** to `https://revengeofthepaws.com` and add
   it under **Redirect URLs**, so confirm and reset emails open the game.
3. Optionally turn **Confirm email** off (Authentication → Sign In / Providers → Email).
4. Copy the Project URL and the anon public key (Project Settings → API) into `cloud_config.gd`.
   The anon key is public by design; row-level security keeps each player to their own save.

Free projects pause after about a week without activity; un-pause them from the dashboard.

## Tools

- `tools/build_zcta.py` builds `data/us_zcta.bin` (ZIP area boundaries) from the Census shapefile.
- `tools/make_sprites.py` draws the unit portraits (`art/units/*.svg`).
- `tools/pixelate.gd` turns them into the 8-bit sprites in `art/pixel/`.
- `tools/battle_report.py` prints the latest fights from the cloud battle log, for balancing.
- `tools/make_splash.gd` draws the loading-screen splash (`art/splash.png`) from those sprites.

## Credits

- ZIP code places: [GeoNames](https://www.geonames.org), CC BY 4.0.
- ZIP code area boundaries: US Census Bureau, 2020 ZIP Code Tabulation Areas (public domain).
- Fonts: [Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) (titles) and
  [Atkinson Hyperlegible](https://fonts.google.com/specimen/Atkinson+Hyperlegible) (text) by the
  Braille Institute, SIL Open Font License (see `fonts/`).
- Palette: [ENDESGA 32](https://lospec.com/palette-list/endesga-32).
