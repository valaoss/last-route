class_name RegionState
extends RefCounted

## Six 0–100 gauges for a region. Play changes them through events (kills,
## searches, mission flags); resting at the safehouse advances the day and lets
## them drift back. The level reads them to decide how many zombies return,
## which loot refills, whether raiders patrol and how the town looks.

signal changed(key: String, value: float)

const KEYS := ["threat", "hostility", "resources", "infrastructure", "survivors", "route"]
const NAMES := {"threat": "Zombi tehdidi", "hostility": "Haydut düşmanlığı", "resources": "Kaynaklar",
	"infrastructure": "Altyapı", "survivors": "Hayatta kalanlar", "route": "Rota güvenliği"}
const START := {"threat": 70.0, "hostility": 70.0, "resources": 65.0, "infrastructure": 0.0, "survivors": 0.0, "route": 10.0}
const FLAG_EFFECTS := {
	"power": {"infrastructure": 35.0},
	"radio": {"infrastructure": 15.0, "survivors": 10.0},
	"survivor": {"survivors": 25.0},
	"shortcut": {"route": 30.0, "hostility": -20.0},
	"workbench": {"infrastructure": 10.0},
}
const KILL_THREAT := {ZombieData.Archetype.WALKER: 0.7, ZombieData.Archetype.RUNNER: 1.2, ZombieData.Archetype.BRUTE: 3.0, ZombieData.Archetype.SCREAMER: 2.5}
const MAX_DAY := 9999

var v := START.duplicate()
var day := 1


func get_value(key: String) -> float:
	return v.get(key, 0.0)


func add(key: String, delta: float) -> void:
	if not v.has(key) or delta == 0.0:
		return
	v[key] = clampf(v[key] + delta, 0.0, 100.0)
	changed.emit(key, v[key])


func on_zombie_killed(archetype: int) -> void:
	add("threat", -KILL_THREAT.get(archetype, 0.7))


func on_raider_killed() -> void:
	add("hostility", -5.0)
	add("route", 2.0)


func on_searched() -> void:
	add("resources", -1.2)


func on_flag(f: String) -> void:
	var fx: Dictionary = FLAG_EFFECTS.get(f, {})
	for k in fx:
		add(k, fx[k])


## A night at the safehouse. Returns {key: delta} for the morning report.
## The horde drifts back (less on safe routes), scavengers restock the town a
## little, raiders regroup unless the road is held, people trickle in once
## there is power and a radio.
func rest() -> Dictionary:
	var before := v.duplicate()
	day = mini(day + 1, MAX_DAY)
	add("threat", lerpf(9.0, 3.0, get_value("route") / 100.0))
	add("resources", 3.0 + 9.0 * (1.0 - get_value("resources") / 100.0))
	add("hostility", 4.0 if get_value("route") < 40.0 else 1.0)
	if get_value("infrastructure") >= 50.0:
		add("survivors", 5.0)
	add("route", -2.0 if get_value("threat") > 60.0 else 0.0)
	var d := {}
	for k in KEYS:
		var dk: float = v[k] - before[k]
		if absf(dk) >= 0.5:
			d[k] = dk
	return d


## Share of killed zombies that walk back in overnight.
func revive_share() -> float:
	return clampf(get_value("threat") / 100.0, 0.05, 0.95)


## Chance a searched (non-quest) spot has been restocked overnight.
func refill_chance() -> float:
	return clampf(get_value("resources") / 100.0 * 0.7, 0.0, 0.7)


func raiders_patrol() -> bool:
	return get_value("hostility") >= 30.0


func to_dict() -> Dictionary:
	var out := {"day": day}
	for k in KEYS:
		out[k] = snappedf(v[k], 0.1)
	return out


## Untrusted input: unknown keys ignored, values clamped.
func from_dict(d: Dictionary) -> void:
	v = START.duplicate()
	for k in KEYS:
		v[k] = SaveSystem.read_num(d, k, START[k], 0.0, 100.0)
	day = int(SaveSystem.read_num(d, "day", 1, 1, MAX_DAY))
