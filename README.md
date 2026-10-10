# LAST ROUTE — P3 depth

Mobile-first open-world zombie survival (Godot 4.7, Mobile renderer). This build covers P0 (motorcycle + combat feel), P1 (raiders, screamer, inventory, save), P2 (the first neighbourhood, walk-in buildings, M01–M05) and **P3**: region gauges, nights at the safehouse, persistent dead, workbench upgrades and crafting, a garage and town that change with your progress.

## Run

```
tools\godot.exe --path .
```
(`scripts\fetch_godot.ps1` downloads the portable engine into `tools\` if missing.) Open the editor with `tools\godot.exe -e --path .` and press F5.

Main menu → **Karaçam mahallesi** (neighbourhood, missions M01–M05), **Sürüş test pisti** (riding loop), **Savaş arenası** (combat yard) or **Senaryo · Benzinlik kaçışı** (ride → loot → alarm → escape home, with a raider patrol and a screamer). It autosaves; **Devam et** resumes.

| Key | Action |
|---|---|
| WASD / left stick | move · throttle/brake/steer on the bike |
| Mouse / right stick | camera |
| LMB / RMB | fire / aim |
| Shift | sprint |
| Space | dodge (on foot) · rear brake/slide (bike) |
| R · F · Q/1-3 | reload · melee combo · weapon |
| H · T · G | use medkit · refuel the bike from a fuel can (stand next to it) · throw a noise lure |
| E | mount / dismount · use (garage: workbench, region board, bed = end the day) |
| C | recenter camera |
| F1 · F2 · F3 | live tuning · control scheme A/B · debug overlay |
| F5–F10 (arena) | spawn walker / group / runner / brute / clear / horde |
| Backspace | respawn |

## Verify

```
scripts\run_tests.ps1                      # headless checks (physics, weapons, AI, inventory, save, missions, interiors, merging, region, upgrades)
scripts\autotest.ps1 -Scenario ride        # scripted ride: 0-60, braking, lean, slide, crash + screenshots
scripts\autotest.ps1 -Scenario arena -Level arena
scripts\autotest.ps1 -Scenario perf -Level arena   # 30 zombies frame-time
scripts\autotest.ps1 -Scenario gasrun -Level gasrun # P0c scenario loop
scripts\autotest.ps1 -Scenario hood -Level hood     # M01–M05 chain, workbench, lure, region board, a night → day 2, frame cost
```
Screenshots/logs land in `.autotest/`.

## Layout

`src/` code (vehicle, player, combat, ai, camera, anim, art, levels, ui, core) · `docs/` design + status · `tests/` · `scripts/` · `assets/` (CC0, see licenses) · `config/` saved tuning.
