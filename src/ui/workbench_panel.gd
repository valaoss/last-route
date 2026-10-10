class_name WorkbenchPanel
extends MenuPanel

## Garage workbench: fit bike upgrades and craft from the four recipes.
## Materials come from pockets and the bike bag. Keys 1–7 = rows.

var inv: Inventory
var installed: Callable     ## (id) -> bool
var on_upgrade: Callable    ## (id) -> void, after paying
var on_craft: Callable      ## (id) -> void, after paying
var _actions: Array[Callable] = []


func refresh() -> void:
	clear_body()
	_actions.clear()
	body.add_child(label("TEZGÂH", 26, AMBER))
	body.add_child(label("Malzeme cepten, eksikse motor çantasından düşülür.", 13, DIM))
	body.add_child(label("Motor", 18, INK))
	for id in UpgradeDB.UPGRADES:
		var u: Dictionary = UpgradeDB.UPGRADES[id]
		var done: bool = installed.call(id)
		_row(u.name, u.desc, u.cost, "Takılı" if done else "Tak", not done, _upgrade.bind(id))
	body.add_child(label("Üretim", 18, INK))
	for id in UpgradeDB.RECIPES:
		var r: Dictionary = UpgradeDB.RECIPES[id]
		_row(r.name, "", r.cost, "Yap", true, _craft.bind(id))
	close_row()


func _row(title: String, desc: String, cost: Dictionary, verb: String, can: bool, cb: Callable) -> void:
	_actions.append(cb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 2)
	col.add_child(label("%d  %s" % [_actions.size(), title], 17, INK))
	if desc != "":
		col.add_child(label(desc, 13, DIM))
	var miss := UpgradeDB.missing(inv, cost)
	col.add_child(label(UpgradeDB.cost_text(cost) if miss.is_empty() else "Eksik: " + ", ".join(miss), 13, GOOD if miss.is_empty() else BAD))
	row.add_child(col)
	row.add_child(button(verb, can and miss.is_empty(), cb))
	body.add_child(row)


func _upgrade(id: String) -> void:
	if installed.call(id) or not UpgradeDB.pay(inv, UpgradeDB.cost_of(id)):
		return
	on_upgrade.call(id)
	refresh.call_deferred()


func _craft(id: String) -> void:
	if not UpgradeDB.pay(inv, UpgradeDB.cost_of(id)):
		return
	on_craft.call(id)
	refresh.call_deferred()


func _on_key(code: int) -> void:
	var i := code - KEY_1
	if i >= 0 and i < _actions.size():
		_actions[i].call()
