# Pathfinder

A Lord of the Rings Online plugin that guides you along a short route to the
targets of explorer and lore deeds: an arrow points to the next target, a map
shows the route, and a list lets you tick off what you already have.
German and English clients are supported.

Player documentation (install, commands): [plugin/Pathfinder/README.txt](plugin/Pathfinder/README.txt)

## Layout

| Path | Content |
|---|---|
| `plugin/Pathfinder/` | The plugin as it goes into the LOTRO `Plugins` folder |
| `plugin/Pathfinder/Route/Routes/` | Generated routes, one Lua file per map and deed type |
| `plugin/Pathfinder/Route/Resources/` | Arrow frames (generated) and map images (generated) |
| `tools/` | Generators, tests and packaging |

## Development

```sh
python3 -I tools/fetch_data.py        # LotroCompanion data -> cache/
python3 -I tools/build_routes.py      # routes + map JPGs (--scale 0.6, --map, --types)
python3 -I tools/make_images.py       # 36 rotated arrow frames per arrow
lua5.1 tools/test_loc.lua             # tests for parsing, geometry and route state
python3 -I tools/package.py           # dist/Pathfinder-<version>.zip
```

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
