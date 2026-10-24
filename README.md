# Pathfinder

A Lord of the Rings Online plugin that guides you along a short route to the
targets of explorer and lore deeds: an arrow points to the next target, a map
shows the route, and a list lets you tick off what you already have. The map
also marks where the monsters of slayer deeds gather.
German and English clients are supported.

Player documentation (install, commands): [plugin/Pathfinder/README.txt](plugin/Pathfinder/README.txt)

## Layout

| Path | Content |
|---|---|
| `plugin/Pathfinder/` | The plugin as it goes into the LOTRO `Plugins` folder |
| `plugin/Pathfinder/Route/Routes/` | Generated routes, one Lua file per map and deed type; slayer areas per map (`A*_SLAYER.lua`) |
| `plugin/Pathfinder/Route/Resources/` | Arrow frames and rings (generated) and map images (generated) |
| `tools/` | Generators, tests and packaging |

## Development

```sh
python3 -I tools/fetch_data.py        # LotroCompanion data -> cache/ (--markers: +650 MB monster spawns)
python3 -I tools/build_routes.py      # routes + map JPGs (--scale 0.6, --map, --types, --no-areas)
python3 -I tools/make_images.py       # 36 rotated arrow frames per arrow, area rings
lua5.1 tools/test_loc.lua             # tests for parsing, geometry and route state
python3 -I tools/package.py           # dist/Pathfinder-<version>.zip
```

The slayer areas need the map markers (`fetch_data.py --markers`): every
spawn of every monster. `build_routes.py` matches the slayer deeds' monster
selection against `mobs.xml`, takes the deed's map (or the map of the
territory it names) and puts circles on the densest spots. Deeds it can't
place are listed in `cache/slayer_unmatched.txt`, targets without a map in
`cache/dropped_targets.txt`. Without the markers (or with `--no-areas`)
the existing area files stay as they are.

CI (`.github/workflows/ci.yml`) runs the syntax check, the tests and the
packaging on every push to `main` and on pull requests; the ZIP is attached
as a build artifact. To release, bump `<Version>` in
`plugin/Pathfinder/Route.plugin` and push a matching tag (`v0.4`): the
release workflow builds the ZIP and publishes a GitHub release with it.

For local testing, link `plugin/Pathfinder` into the game's `Plugins` folder
and run `/plugins load Pathfinder` in game.

Notes on the LOTRO plugin API that shaped the design:

- There is no player position in the API. The position comes from the `/loc`
  (`/pos` on German clients) chat output; plugins may not run commands
  themselves, so a quickslot under the arrow runs it on click.
- Controls cannot be rotated, hence 36 pre-rendered arrow images.
- Game map images could not be shown by resource ID, so the maps ship as JPGs
  in their final size (the game does not scale them reliably).
- Discovering a single landmark writes nothing to chat; only a completed deed
  does (`Abgeschlossen:` / `Completed:`).
- The German client's `tonumber()` expects a decimal comma.

## License

Code: [MIT](LICENSE), Copyright (c) 2026 jmennig.

Deed coordinates, names and map images come from
[LotroCompanion](https://github.com/LotroCompanion) (`lotro-data`,
`lotro-maps-db`) and originally from the game data of The Lord of the Rings
Online (Standing Stone Games). They are not covered by the MIT license.
The `/loc` conversion formula follows the Waypoint plugin by Lunarwater.
