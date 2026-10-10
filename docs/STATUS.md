# Status — 2026-10-10 (P3)

## Done and verified

| Area | Verified how | Result |
|---|---|---|
| Motorcycle model (arcade-sim, grip-limited yaw, slide, weight transfer, suspension, gears) | `tests/` + ride autotest | 0→60 km/h 3.2–3.4 s, top 92 km/h, 92→0 in ~32 m, lean capped at 42°, handbrake slip ~13–21° |
| Crash / bump / zombie ram | ride autotest (wall at 50 km/h) | crash → rider ejected, 25 HP damage, back on foot after 1.4 s |
| Mount / dismount | ride autotest | mount 0.5 s (controls at 0.35 s), IK hands on grips during the move |
| Rider body language | screenshots | leans with bike, extra lean into turns, head levels, foot-down at standstill, brake/accel pitch |
| Camera (single rig, profiles, collision, look-ahead, auto-recenter, speed FOV, shake) | screenshots | no cuts between foot/aim/ride |
| Procedural engine audio (V-twin, load, overrun crackle, tyres by surface, wind, skid) | runs without errors | **not judged by ear yet — needs your listening test** |
| On-foot movement, sprint/stamina, dodge with i-frames + cancel window | tests | windows ordered as designed |
| 3 guns + pipe combo, recoil climb/recovery, camera kick, hit-stop, hit markers, tracers, impacts | arena autotest | 8 hits / 3 kills in the scripted run |
| Aim assist (friction + weak magnetism, 3 levels) | code path exercised in arena run | needs touch playtest |
| Zombies: Walker / Runner / Brute, sight + hearing, investigate/search, attack slots (max 3), circling, telegraphs, lunge, brute charge, stagger/knockdown/leg-crawl | tests + arena autotest | reactions follow the power matrix |
| AI + animation LOD, manual anim advance, per-enemy hit-stop | perf autotest | 30 zombies: 4.8 ms avg frame, 157 draw calls (desktop) |
| Art pass: shared world shader, palette, fog, AgX, conifer forest, grass, buildings with windows, wrecks, graffiti | screenshots | coherent, but still primitive-built |
| P0c scenario "Benzinlik kaçışı": ride out → loot fuel + part (noise) → car alarm pulls 23 zombies (3 groups, one blocks the road) → ride back to safehouse; success/fail banners | gasrun autotest | full loop completes, step flow verified |
| Touch controls (floating stick, look drag, context buttons, fire-drag aim, left-handed) | code only | **not tested on a phone** |

## P1 — done and verified

| Area | Verified how | Result |
|---|---|---|
| Screamer zombie: sees you → 2 s scream → 60 m alarm noise, then keeps 7 m+ away, re-screams after 10 s | unit test | alarm broadcast + cooldown |
| Raider AI: patrol → alert (noise/sight) → combat (cover points, hide/peek bursts, reload) → flee (<25% HP or ≥4 zombies close); drops a loot bag | unit test + gasrun autotest | engages zombies, uses road barriers as cover, flees when hurt |
| Three-way conflict: zombies pick the nearest visible prey (player or raider), retarget whoever shot them; raider gunfire is 55 m noise | unit test + autotest | zombies retarget raiders; raiders fight the alarm horde |
| Inventory: category pockets with caps, overflow → bike bag, standing by the bike restocks pockets; medkit (H), refuel from can (T) | unit tests | caps / overflow / restock / validation |
| Loot tables per location (gas station, car, pharmacy, ammo cache, raider) | unit test | only valid items |
| Fuel: full tank ≈ 7 min full throttle, empty → reserve mode (40% power, never stranded); HUD gauge | code + HUD | — |
| Save: JSON v1, atomic tmp→rename, .bak fallback, schema/level whitelist, all values clamped; autosave on step / loot / Esc / app pause; "Devam et" in menu; death reloads the last save | unit tests + autotest restore | round trip, corrupt file → .bak |

## P2 — done and verified

| Area | Verified how | Result |
|---|---|---|
| "Karaçam" neighbourhood (~300 × 400 m): main road, Çarşı, Kuzey yolu, dere detour road, two walled city blocks, residential south, conifer forest | hood autotest screenshots | coherent street views; blocks are closed, so the main road is the only short way north |
| Walk-in interiors (InteriorKit): garage safehouse, pharmacy (back room), market, 2-storey apartment with stairs, workshop (car on lift), gas station shop, radio shack | unit tests (door clear, wall/lintel solid) + autotest | stairs climbed to the upper floor (y 3.2) |
| Radio hill: ramp, plateau, 26 m lattice tower, beacon that blinks after M02 | screenshot | — |
| Raider checkpoint on the main road (3 raiders, cover points, camp) | autotest | navmesh detour 387 m while closed → 63 m after M04 |
| Mission chain M01–M05 (data in `MissionDB`, runner in `MissionRunner`): goto / loot / interact / clear steps, intro/outro radio lines, rewards, permanent flags | 14 unit tests + full autotest run | M01 power → M02 radio → M03 survivor → M04 shortcut → M05 workbench, then free roam |
| Permanent world changes: garage lights + free refuel (M01), tower beacon + periodic radio chatter (M02), Nilay's window light (M03), gate pushed aside + lanterns (M04), workbench → saddlebag upgrade (visible on bike, bike bag ×2) (M05); Nilay moves into the garage once M03 + M04 are done | autotest | flags persist through save/load |
| Radio subtitles (HUD queue), quest items (antenna, antibiotics, toolbox), new loot tables (market, workshop, home) | unit tests | — |
| Save: level "neighborhood" whitelisted; mission index/step/flags/searched spots saved and validated; opened checkpoint is applied before the navmesh bake on load | unit tests + autotest | junk data clamped |
| Tiled navmesh (64 m tiles, geometry parsed once, async bake, tiles stitched; single-tile re-bake when the gate opens) | autotest path probes | garage → station path complete; re-bake parse hitch ≈ 60 ms once |
| Render optimisation: static meshes merged per 96 m chunk into one world-shader mesh (surface params per vertex), MultiMesh batches split per 128 m chunk with draw distances, characters culled at 100 m | unit tests + autotest | widest street view: draw calls 1081 → 278, primitives 1.9 M → 0.44 M, 4.5 ms/frame (desktop) |

## P3 — done and verified

| Area | Verified how | Result |
|---|---|---|
| Render budget closed: far trees as one camera-facing card each (procedural atlas, per-tree cut-off in the shader, 256 m chunks), 3D tree parts on 48 m chunks, character import LODs kept, bike/weapon parts merged per moving group | unit tests + hood autotest | main street 1081 → **207 draws / 141 k prims**; hill panorama **225 / 156 k** (target 250 / 300 k), 4.2 ms/frame desktop |
| RegionState (threat, raider hostility, resources, infrastructure, survivors, route safety; 0–100): moved by kills, searches and mission flags; drifts each night | 8 unit tests + autotest | values saved/validated; old P2 saves rebuild them from flags |
| Persistent dead: every zombie has a spawn id; the dead stay dead in saves; a night revives `threat %` of them | autotest | 3 killed → 2 back next morning |
| Night at the safehouse (bed): blocked if enemies within 35 m; heals, advances the day, revives some dead, refills some searched spots (`resources`), autosaves and reloads into a morning banner with the deltas | autotest | Gün 2 banner, report shown once |
| Raider patrol on the Kuzey yolu while hostility ≥ 30 after the checkpoint falls | autotest | 2 patrol raiders on day 2 |
| Workbench (pauses the game): 3 bike upgrades — saddlebags, muffler (noise −35 %, quieter engine, wrapped can visible), off-road suspension (more grip/power, less drag on loose ground, softer landings, yellow coil-overs + fork gaiters) — and 4 recipes (medkit, pistol ammo, shells, noise lure); pays from pockets then the bike bag | unit tests + autotest | engine noise 25 → 16 m with the muffler |
| Noise lure (G / touch "TUZAK"): thrown alarm clock, 14 s of 48 m alarm-priority beeps | unit test + autotest | 3 nearby zombies closed from 14.7 to 8.4 m in 9 s |
| Region board in the garage: six gauges, last night's deltas, plain-language consequences | screenshot | — |
| Safehouse growth: roof antenna, tool wall, second bed + stove, string lights, sandbag walls, vegetable crates — each unlocked by flags/gauges, merged per set | unit tests + screenshots | 5 of 6 sets after the chain + one night |
| Town reflects the region: lit pharmacy cross + market "AÇIK" (infrastructure ≥ 50), green chevrons on the main road (route ≥ 40), burn pile with a smoke column at the Çarşı (threat < 45) | screenshots | — |
| New materials: alcohol, gunpowder (loot tables), lure; touch buttons for medkit and lure | unit tests | — |

## Not done / known issues

- **No device testing yet** — Android export needs JDK + SDK setup (P6). No mobile performance claim is made.
- Motor sound and gun sounds are synthesized; quality must be judged by you.
- Strafing uses procedural hip twist over forward clips (the CC0 library has no strafe clips); backwards walk plays Walk reversed.
- Rifle/shotgun aim uses the pistol aim pose + IK; acceptable at gameplay distance, visible up close.
- Zombies share the mannequin mesh (faceless); variety comes from colours, body proportions, posture and gait.
- Knockdown get-up is a cross-fade, not a dedicated clip.
- Event Director, horde T2/T3 tiers: designed in GDD, scheduled for P4.
- Raiders use the pistol clip set with a carbine model (no rifle clips in the CC0 library); no dedicated cover-lean animation (crouch idle).
- In the neighbourhood the dead stay dead, but living zombies respawn at their spawn points on load (positions aren't saved). Gas-run zombies are still not saved.
- Night is a reload, not a time-of-day change (no night lighting yet); a night costs a few seconds of loading.
- Far tree cards are lit as one flat card; at the 80 m swap a tree can briefly show both versions.
- Draw-call numbers are desktop measurements; still no device test.
- Interiors are lit by the sky ambient + a few omni lights (no baked GI yet); they read darker but flat.
- The checkpoint gate re-bake costs one ~60 ms frame when it opens.
- Nilay is a static idle figure; no dialogue/NPC interaction yet.
- GUT was replaced by a small self-contained runner (`tests/test_runner.gd`) to avoid an extra dependency.

## Next

1. Your playtest of "Karaçam mahallesi" over 2–3 in-game days → does the next session feel different (P3 exit question), economy of scrap/powder, lure usefulness.
2. Android export + first device profile (measures the draw-call/primitive numbers above on real hardware).
3. P4: Event Director, horde tiers T2/T3, faction interaction.
