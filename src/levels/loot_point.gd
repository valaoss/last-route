class_name LootPoint
extends Node3D

## Searchable spot. Amber glint marks it; searching makes noise that nearby
## zombies hear. Contents go through the player's Inventory (overflow → bike bag).

signal looted(point: LootPoint)

const LABELS := {&"fuel": "Benzin bidonu", &"part": "Karbüratör parçası", &"ammo": "Mühimmat", &"med": "İlk yardım", &"cache": "Ara", &"quest": "Ara"}

@export var kind: StringName = &"ammo"
@export var table: StringName = &"gas_station"   ## used by kind "cache"
@export var label := ""                          ## overrides the prompt text for caches
@export var item: StringName = &""               ## kind "quest": the single item it holds
@export var noise_radius := 22.0
const TABLES_EXTRA := [&"pharmacy", &"workshop", &"home", &"market"]
var point_id := ""                               ## stable id for save files
var interact_range := 2.0
var taken := false
var _glint: MeshInstance3D
var _light: OmniLight3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	if not LABELS.has(kind):
		kind = &"ammo"
	_rng.randomize()
	_glint = MeshKit.box(self, Vector3(0.28, 0.2, 0.18), Vector3(0, 0.12, 0), Palette.mat(&"loot_glint"), Vector3(0, 20, 0), false)
	_light = OmniLight3D.new()
	_light.light_color = Palette.LOOT_AMBER
	_light.light_energy = 0.6
	_light.omni_range = 2.2
	_light.position = Vector3(0, 0.6, 0)
	add_child(_light)
	if taken:
		_mark_taken()
	else:
		add_to_group(&"interactable")


func _process(_dt: float) -> void:
	if not taken:
		_light.light_energy = 0.45 + 0.25 * sin(Time.get_ticks_msec() * 0.004)


func interact_prompt() -> String:
	return "E  Ara · " + (label if label != "" else LABELS[kind])


func contents() -> Dictionary:
	match kind:
		&"fuel": return {&"fuel_can": 1}
		&"part": return {&"carb_part": 1}
		&"med":
			var m := LootTable.roll(&"pharmacy", _rng, 1)
			m[&"medkit"] = m.get(&"medkit", 0) + 1
			return m
		&"ammo": return LootTable.roll(&"ammo_cache", _rng, 2)
		&"quest":
			var q := {item: 1} if Inventory.is_valid(item) else {}
			if TABLES_EXTRA.has(table):
				q.merge(LootTable.roll(table, _rng, 1))
			return q
	return LootTable.roll(table, _rng, 2)


func interact(p: Player) -> void:
	if taken:
		return
	var lines := PackedStringArray()
	var got := contents()
	for id in got:
		var r: Dictionary = p.inventory.add(id, got[id])
		var line := "+%d %s" % [got[id], Inventory.display_name(id)]
		if r.bagged > 0:
			line += "  (%d çantaya)" % r.bagged
		if r.lost > 0:
			line += "  (%d sığmadı)" % r.lost
		lines.append(line)
	p.combat._emit_ammo()
	EventBus.toast.emit("\n".join(lines))
	p.anim.model.fire(&"interact")
	Sfx.play_at(&"pickup", global_position, -2.0)
	NoiseBus.emit_noise(global_position, noise_radius, NoiseBus.Priority.MOVEMENT, p)
	_mark_taken()
	looted.emit(self)


func _mark_taken() -> void:
	taken = true
	remove_from_group(&"interactable")
	if _glint:
		_glint.visible = false
		_light.visible = false
