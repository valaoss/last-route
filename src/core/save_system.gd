extends Node

## JSON save with schema version + migration and atomic write (tmp → rename,
## previous file kept as .bak). The active level registers `provider`
## (returns a snapshot Dictionary); the game autosaves when the app is
## backgrounded or closed. Everything read back is treated as untrusted.

const VERSION := 1
const PATH := "user://save_v1.json"
const LEVELS := {"gas_run": "res://src/levels/gas_run.tscn", "neighborhood": "res://src/levels/neighborhood.tscn"}   ## whitelist for "continue"

var provider: Callable          ## () -> Dictionary, set by the running level
var pending: Dictionary = {}     ## loaded data waiting for its level to apply it


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_CLOSE_REQUEST:
		autosave()


func autosave() -> bool:
	if not provider.is_valid():
		return false
	var snap: Variant = provider.call()
	return save_data(snap) if snap is Dictionary and not snap.is_empty() else false


func has_save() -> bool:
	return not load_data().is_empty()


func save_data(d: Dictionary, path := PATH) -> bool:
	var out := d.duplicate(true)
	out["version"] = VERSION
	out["saved_at"] = int(Time.get_unix_time_from_system())
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(out))
	f.close()
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(abs_path + ".bak")
		DirAccess.rename_absolute(abs_path, abs_path + ".bak")
	return DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), abs_path) == OK


## Returns {} when there is no valid save. Falls back to the .bak copy.
func load_data(path := PATH) -> Dictionary:
	for p in [path, path + ".bak"]:
		var d := _read(p)
		if not d.is_empty():
			return d
	return {}


func delete_save(path := PATH) -> void:
	for p in [path, path + ".bak", path + ".tmp"]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func level_path(d: Dictionary) -> String:
	return LEVELS.get(str(d.get("level", "")), "")


func _read(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null or f.get_length() > 1_000_000:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not parsed is Dictionary:
		return {}
	return migrate(parsed)


## Upgrades older schemas; rejects unknown future versions.
func migrate(d: Dictionary) -> Dictionary:
	var v := int(d.get("version", 0)) if (d.get("version") is float or d.get("version") is int) else 0
	if v < 1 or v > VERSION:
		return {}
	if not LEVELS.has(str(d.get("level", ""))):
		return {}
	return d


# ------------------------------------------------------------------ value helpers (untrusted → typed)

static func vec(v: Vector3) -> Array:
	return [snappedf(v.x, 0.01), snappedf(v.y, 0.01), snappedf(v.z, 0.01)]


static func read_vec(a: Variant, fallback: Vector3, bounds := 2000.0) -> Vector3:
	if not a is Array or a.size() != 3:
		return fallback
	for x in a:
		if not (x is float or x is int) or is_nan(float(x)) or absf(float(x)) > bounds:
			return fallback
	return Vector3(a[0], a[1], a[2])


static func read_num(d: Dictionary, key: String, fallback: float, lo: float, hi: float) -> float:
	var x: Variant = d.get(key)
	if not (x is float or x is int) or is_nan(float(x)):
		return fallback
	return clampf(float(x), lo, hi)


## Player + bike state shared by every level.
static func snapshot_actors(p: Player, b: Moto) -> Dictionary:
	var ammo := {}
	for id in p.combat.ammo:
		ammo[String(id)] = p.combat.ammo[id].duplicate()
	return {
		"player": {"pos": vec(p.global_position), "facing": p.facing, "health": p.health, "ammo": ammo, "inventory": p.inventory.to_dict()},
		"bike": {"pos": vec(b.global_position), "heading": b.heading, "fuel": b.fuel},
	}


static func apply_actors(d: Dictionary, p: Player, b: Moto) -> void:
	var pd: Dictionary = d.get("player", {}) if d.get("player") is Dictionary else {}
	var bd: Dictionary = d.get("bike", {}) if d.get("bike") is Dictionary else {}
	p.global_position = read_vec(pd.get("pos"), p.global_position) + Vector3.UP * 0.1
	p.facing = read_num(pd, "facing", p.facing, -TAU, TAU)
	p.health = read_num(pd, "health", p.max_health, 1.0, p.max_health)
	p.health_changed.emit(p.health, p.max_health)
	var ammo: Variant = pd.get("ammo", {})
	if ammo is Dictionary:
		for w in p.combat.weapons:
			var a: Variant = ammo.get(String(w.id))
			if a is Array and a.size() == 2 and (a[0] is float or a[0] is int) and (a[1] is float or a[1] is int):
				var cap: int = Inventory.DEFS[StringName("ammo_" + String(w.id))].cap
				p.combat.ammo[w.id] = [clampi(int(a[0]), 0, w.mag_size), clampi(int(a[1]), 0, cap)]
		p.combat._emit_ammo()
	var inv: Variant = pd.get("inventory", {})
	if inv is Dictionary:
		p.inventory.from_dict(inv)
	var heading := read_num(bd, "heading", b.heading, -TAU * 4.0, TAU * 4.0)
	b.global_transform = Transform3D(Basis(Vector3.UP, heading), read_vec(bd.get("pos"), b.global_position) + Vector3.UP * 0.15)
	b.heading = heading
	b.vel_heading = heading
	b.fuel = read_num(bd, "fuel", 1.0, 0.0, 1.0)
	p.rig.snap_behind(p.facing)
