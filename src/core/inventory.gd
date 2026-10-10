class_name Inventory
extends RefCounted

## Category pockets with per-item caps. Whatever doesn't fit on the player goes
## to the bike bag automatically; walking up to the bike tops the pockets back up.
## No grid, no sorting screen. Ammo reserves live in PlayerCombat (pocket = reserve cap).

signal changed

const DEFS := {
	&"medkit": {"name": "İlk yardım kiti", "pocket": &"med", "cap": 3, "bag": 3},
	&"scrap": {"name": "Hurda", "pocket": &"mat", "cap": 10, "bag": 30},
	&"cloth": {"name": "Bez", "pocket": &"mat", "cap": 10, "bag": 30},
	&"powder": {"name": "Barut", "pocket": &"mat", "cap": 6, "bag": 12},
	&"alcohol": {"name": "Alkol", "pocket": &"med", "cap": 3, "bag": 6},
	&"lure": {"name": "Gürültü tuzağı", "pocket": &"tool", "cap": 3, "bag": 3},
	&"fuel_can": {"name": "Benzin bidonu", "pocket": &"fuel", "cap": 1, "bag": 2},
	&"carb_part": {"name": "Karbüratör parçası", "pocket": &"quest", "cap": 1, "bag": 1},
	&"antenna_part": {"name": "Yedek anten", "pocket": &"quest", "cap": 1, "bag": 1},
	&"antibiotics": {"name": "Antibiyotik", "pocket": &"quest", "cap": 2, "bag": 2},
	&"toolbox": {"name": "Alet çantası", "pocket": &"quest", "cap": 1, "bag": 1},
	&"ammo_pistol": {"name": "Tabanca mermisi", "pocket": &"ammo", "cap": 90, "bag": 120, "weapon": &"pistol"},
	&"ammo_carbine": {"name": "Karabina mermisi", "pocket": &"ammo", "cap": 150, "bag": 200, "weapon": &"carbine"},
	&"ammo_shotgun": {"name": "Fişek", "pocket": &"ammo", "cap": 30, "bag": 40, "weapon": &"shotgun"},
}

var items: Dictionary = {}     ## id -> count on the player
var bag: Dictionary = {}       ## id -> count in the bike bag
var ammo: Dictionary = {}      ## PlayerCombat.ammo (id -> [mag, reserve]); null in tests
var bag_mult := 1.0            ## saddlebag upgrade raises bike-bag capacity


static func is_valid(id: StringName) -> bool:
	return DEFS.has(id)


static func display_name(id: StringName) -> String:
	return DEFS[id].name if DEFS.has(id) else String(id)


func count(id: StringName) -> int:
	if _is_ammo(id) and not ammo.is_empty():
		return ammo[DEFS[id].weapon][1]
	return items.get(id, 0)


func bag_count(id: StringName) -> int:
	return bag.get(id, 0)


## Pockets + bike bag (the bag doubles as the garage stash at the workbench).
func total(id: StringName) -> int:
	return count(id) + bag_count(id)


## Removes `n` from pockets first, then the bag. Returns how many were removed.
func spend(id: StringName, n: int) -> int:
	var k := take(id, n)
	var rest := mini(maxi(n, 0) - k, bag_count(id))
	if rest > 0:
		bag[id] = bag_count(id) - rest
		changed.emit()
	return k + rest


func bag_cap(id: StringName) -> int:
	return int(DEFS[id].bag * bag_mult) if DEFS.has(id) else 0


## Adds `n`; returns {"kept", "bagged", "lost"}.
func add(id: StringName, n: int) -> Dictionary:
	var res := {"kept": 0, "bagged": 0, "lost": 0}
	if not is_valid(id) or n <= 0:
		return res
	var def: Dictionary = DEFS[id]
	var room := maxi(int(def.cap) - count(id), 0)
	res.kept = mini(n, room)
	_set_count(id, count(id) + res.kept)
	var rest: int = n - res.kept
	var bag_room := maxi(bag_cap(id) - bag_count(id), 0)
	res.bagged = mini(rest, bag_room)
	if res.bagged > 0:
		bag[id] = bag_count(id) + res.bagged
	res.lost = rest - res.bagged
	changed.emit()
	return res


## Removes up to `n` from the player; returns how many were removed.
func take(id: StringName, n := 1) -> int:
	var have := count(id)
	var k := mini(have, maxi(n, 0))
	if k > 0:
		_set_count(id, have - k)
		changed.emit()
	return k


## Moves bag contents into free pocket space. Returns {id: moved}.
func restock_from_bag() -> Dictionary:
	var moved := {}
	for id in bag.keys():
		var room := maxi(int(DEFS[id].cap) - count(id), 0)
		var k := mini(room, bag_count(id))
		if k > 0:
			_set_count(id, count(id) + k)
			bag[id] = bag_count(id) - k
			moved[id] = k
	if not moved.is_empty():
		changed.emit()
	return moved


func _is_ammo(id: StringName) -> bool:
	return DEFS.has(id) and DEFS[id].has("weapon")


func _set_count(id: StringName, n: int) -> void:
	if _is_ammo(id) and not ammo.is_empty():
		ammo[DEFS[id].weapon][1] = n
	else:
		items[id] = n


# ------------------------------------------------------------------ save

func to_dict() -> Dictionary:
	var out := {"items": {}, "bag": {}}
	for id in DEFS:
		if not _is_ammo(id) and count(id) > 0:
			out.items[String(id)] = count(id)
		if bag_count(id) > 0:
			out.bag[String(id)] = bag_count(id)
	return out


## Untrusted input: unknown ids dropped, counts clamped to caps.
func from_dict(d: Dictionary) -> void:
	items.clear()
	bag.clear()
	for key in ["items", "bag"]:
		var src: Variant = d.get(key, {})
		if not src is Dictionary:
			continue
		for k in src:
			var id := StringName(str(k))
			if not is_valid(id) or (key == "items" and _is_ammo(id)):
				continue
			var cap: int = DEFS[id].cap if key == "items" else bag_cap(id)
			var n := clampi(int(src[k]) if (src[k] is int or src[k] is float) else 0, 0, cap)
			if key == "items":
				items[id] = n
			else:
				bag[id] = n
	changed.emit()
