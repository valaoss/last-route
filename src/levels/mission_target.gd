class_name MissionTarget
extends Node3D

## Interactable mission object (generator, radio, gate, workbench...). Only
## usable while `active`. Required items are checked and consumed on use;
## success is announced on EventBus.mission_interact and `used`.

signal used(target: MissionTarget)

@export var target_id := ""
@export var prompt := ""
@export var requires: Dictionary = {}      ## item id -> count
@export var noise_radius := 0.0
@export var show_glint := true
var interact_range := 2.2
var active := false: set = set_active
var _light: OmniLight3D


func _ready() -> void:
	if show_glint:
		_light = OmniLight3D.new()
		_light.light_color = Palette.LOOT_AMBER
		_light.omni_range = 2.6
		_light.position = Vector3(0, 1.0, 0)
		add_child(_light)
	set_active(active)


func set_active(on: bool) -> void:
	active = on
	if not is_inside_tree():
		return
	if on:
		add_to_group(&"interactable")
	else:
		remove_from_group(&"interactable")
	if _light:
		_light.visible = on


func _process(_dt: float) -> void:
	if active and _light:
		_light.light_energy = 0.5 + 0.3 * sin(Time.get_ticks_msec() * 0.005)


func interact_prompt() -> String:
	var t := "E  " + prompt
	var need := PackedStringArray()
	for id in requires:
		need.append("%s ×%d" % [Inventory.display_name(id), requires[id]])
	if not need.is_empty():
		t += "  (" + ", ".join(need) + ")"
	return t


func missing(inv: Inventory) -> PackedStringArray:
	var out := PackedStringArray()
	for id in requires:
		if inv.count(id) < int(requires[id]):
			out.append(Inventory.display_name(id))
	return out


func interact(p: Player) -> void:
	if not active:
		return
	var miss := missing(p.inventory)
	if not miss.is_empty():
		EventBus.toast.emit("Gerekli: " + ", ".join(miss))
		return
	for id in requires:
		p.inventory.take(id, int(requires[id]))
	p.anim.model.fire(&"interact")
	Sfx.play_at(&"pickup", global_position, -2.0)
	if noise_radius > 0.0:
		NoiseBus.emit_noise(global_position, noise_radius, NoiseBus.Priority.MOVEMENT, p)
	active = false
	used.emit(self)
	EventBus.mission_interact.emit(target_id)
