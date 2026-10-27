# Revenge of the Paws

A phone-first, turn-based 8-bit RPG: your real-life pet and the animals native to where you live
take back your actual neighborhood, ZIP code by ZIP code, from zombies and local cryptids.

Play: **https://revengeofthepaws.com**

Built with [Godot 4.7](https://godotengine.org). Design notes: [DESIGN.md](DESIGN.md).

## Running locally

Open the folder in Godot 4.7 and press F5. Balance check (plays simulated campaigns):

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

## Tools

- `tools/build_zcta.py` builds `data/us_zcta.bin` (ZIP area boundaries) from the Census shapefile.
- `tools/make_sprites.py` draws the unit portraits (`art/units/*.svg`).
- `tools/pixelate.gd` turns them into the 8-bit sprites in `art/pixel/`.

## Credits

- ZIP code places: [GeoNames](https://www.geonames.org), CC BY 4.0.
- ZIP code area boundaries: US Census Bureau, 2020 ZIP Code Tabulation Areas (public domain).
- Fonts: [Press Start 2P](https://fonts.google.com/specimen/Press+Start+2P) and
  [Pixelify Sans](https://fonts.google.com/specimen/Pixelify+Sans), SIL Open Font License (see `fonts/`).
- Palette: [ENDESGA 32](https://lospec.com/palette-list/endesga-32).
