class_name UpgradeDB
extends RefCounted

## Workbench data: three bike upgrades (each visible on the bike and stored as
## a permanent flag) and four recipes. Costs are paid from pockets first, then
## from the bike bag (the garage stash).

const UPGRADES := {
	"saddlebags": {"name": "Yan çantalar", "desc": "Motor çantası kapasitesi ×2", "cost": {&"scrap": 6, &"cloth": 4}},
	"muffler": {"name": "Susturucu", "desc": "Motor sesi −%35 · sürü seni daha geç duyar", "cost": {&"scrap": 8, &"cloth": 2, &"alcohol": 1}},
	"suspension": {"name": "Arazi süspansiyonu", "desc": "Toprak, çim, çamurda daha çok tutuş ve hız · sert inişler yumuşar", "cost": {&"scrap": 14, &"powder": 1}},
}
const RECIPES := {
	"medkit": {"name": "İlk yardım kiti", "cost": {&"cloth": 3, &"alcohol": 1}, "out": {&"medkit": 1}},
	"ammo_pistol": {"name": "Tabanca mermisi ×12", "cost": {&"scrap": 2, &"powder": 1}, "out": {&"ammo_pistol": 12}},
	"ammo_shotgun": {"name": "Fişek ×5", "cost": {&"scrap": 2, &"powder": 2}, "out": {&"ammo_shotgun": 5}},
	"lure": {"name": "Gürültü tuzağı", "cost": {&"scrap": 2, &"cloth": 1}, "out": {&"lure": 1}},
}
const MUFFLER_NOISE := 0.65


static func cost_of(id: String) -> Dictionary:
	if UPGRADES.has(id):
		return UPGRADES[id].cost
	if RECIPES.has(id):
		return RECIPES[id].cost
	return {}


static func missing(inv: Inventory, cost: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	for item in cost:
		var have := inv.total(item)
		if have < int(cost[item]):
			out.append("%s %d/%d" % [Inventory.display_name(item), have, cost[item]])
	return out


## Pays `cost` if everything is there; returns false (and takes nothing) otherwise.
static func pay(inv: Inventory, cost: Dictionary) -> bool:
	if cost.is_empty() or not missing(inv, cost).is_empty():
		return false
	for item in cost:
		inv.spend(item, int(cost[item]))
	return true


static func cost_text(cost: Dictionary) -> String:
	var parts := PackedStringArray()
	for item in cost:
		parts.append("%s ×%d" % [Inventory.display_name(item), cost[item]])
	return ", ".join(parts)
