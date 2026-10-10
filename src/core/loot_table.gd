class_name LootTable
extends RefCounted

## Location-tagged loot: each entry is [item id, weight, min, max].
## `risk` (0..1, e.g. near a horde) adds extra rolls.

const TABLES := {
	&"gas_station": [[&"scrap", 4, 1, 3], [&"cloth", 2, 1, 2], [&"ammo_pistol", 3, 6, 12], [&"fuel_can", 1, 1, 1], [&"medkit", 1, 1, 1], [&"powder", 1, 1, 1]],
	&"ammo_cache": [[&"ammo_pistol", 4, 10, 18], [&"ammo_carbine", 3, 12, 24], [&"ammo_shotgun", 2, 4, 8], [&"powder", 2, 1, 2]],
	&"pharmacy": [[&"medkit", 5, 1, 2], [&"cloth", 3, 1, 3], [&"alcohol", 3, 1, 2]],
	&"car": [[&"scrap", 4, 1, 2], [&"ammo_pistol", 2, 4, 8], [&"cloth", 2, 1, 1]],
	&"market": [[&"cloth", 3, 1, 3], [&"scrap", 2, 1, 2], [&"medkit", 1, 1, 1], [&"ammo_pistol", 1, 4, 8], [&"alcohol", 2, 1, 1]],
	&"workshop": [[&"scrap", 5, 2, 4], [&"fuel_can", 1, 1, 1], [&"ammo_shotgun", 1, 2, 5], [&"powder", 2, 1, 2]],
	&"home": [[&"cloth", 3, 1, 2], [&"medkit", 2, 1, 1], [&"ammo_pistol", 2, 4, 10], [&"scrap", 1, 1, 2], [&"alcohol", 2, 1, 1]],
	&"raider": [[&"ammo_carbine", 4, 8, 16], [&"ammo_pistol", 3, 6, 12], [&"medkit", 1, 1, 1], [&"powder", 2, 1, 2]],
}


## Returns {id: count}. Unknown tables return nothing.
static func roll(table: StringName, rng: RandomNumberGenerator, rolls := 2, risk := 0.0) -> Dictionary:
	var out := {}
	if not TABLES.has(table):
		return out
	var entries: Array = TABLES[table]
	var total := 0
	for e in entries:
		total += int(e[1])
	var n := rolls + (1 if rng.randf() < clampf(risk, 0.0, 1.0) else 0)
	for i in n:
		var pick := rng.randi_range(1, total)
		for e in entries:
			pick -= int(e[1])
			if pick <= 0:
				out[e[0]] = out.get(e[0], 0) + rng.randi_range(int(e[2]), int(e[3]))
				break
	return out
