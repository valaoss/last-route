class_name MissionRunner
extends Node

## Runs MissionDB.CHAIN in order. The level feeds it events (position, loot,
## target use, tag counts) and reacts to its signals (objective text, flags).

signal step_started(mission: Dictionary, step: Dictionary)
signal mission_completed(mission: Dictionary)
signal flag_set(flag: String)
signal chain_completed

var index := 0                ## current mission in the chain
var step := 0                 ## current step in that mission
var flags: Dictionary = {}    ## flag -> true
var looted: Dictionary = {}   ## loot id -> true (kept for loot steps)
var places: Dictionary = {}   ## place name -> Vector3 (from the level)
var tag_alive: Callable       ## (tag) -> int, enemies still fighting under a tag
var _poll_t := 0.0


func _ready() -> void:
	EventBus.mission_interact.connect(on_interact)


func done() -> bool:
	return index >= MissionDB.CHAIN.size()


func mission() -> Dictionary:
	return {} if done() else MissionDB.CHAIN[index]


func current() -> Dictionary:
	return {} if done() else mission().steps[step]


func has_flag(f: String) -> bool:
	return flags.has(f)


func set_flag(f: String) -> void:
	if f in MissionDB.FLAGS and not flags.has(f):
		flags[f] = true
		flag_set.emit(f)


## Begins (or resumes) the current step; plays the intro on a mission's first step.
func start(play_intro := true) -> void:
	if done():
		chain_completed.emit()
		return
	if step == 0 and play_intro:
		for l in mission().intro:
			EventBus.radio.emit(l[0], l[1])
	step_started.emit(mission(), current())
	_check_instant()


func update(player_pos: Vector3, dt: float) -> void:
	var s := current()
	if s.is_empty():
		return
	match s.type:
		"goto":
			var p: Variant = places.get(s.place)
			if p is Vector3 and player_pos.distance_to(p) < float(s.r):
				_advance()
		"clear":
			_poll_t -= dt
			if _poll_t <= 0.0:
				_poll_t = 0.5
				if tag_alive.is_valid() and int(tag_alive.call(s.tag)) == 0:
					_advance()


func on_looted(id: String) -> void:
	looted[id] = true
	if current().get("type") == "loot":
		_check_instant()


func on_interact(target_id: String) -> void:
	var s := current()
	if s.get("type") == "interact" and s.target == target_id:
		_advance()


## Loot steps can already be satisfied (e.g. searched before the step began).
func _check_instant() -> void:
	var s := current()
	if s.get("type") == "loot":
		for id in s.ids:
			if not looted.has(id):
				return
		_advance()


func _advance() -> void:
	step += 1
	if step >= mission().steps.size():
		var m := mission()
		for l in m.outro:
			EventBus.radio.emit(l[0], l[1])
		set_flag(m.flag)
		index += 1
		step = 0
		mission_completed.emit(m)
	start()


# ------------------------------------------------------------------ save

func to_dict() -> Dictionary:
	return {"index": index, "step": step, "flags": flags.keys(), "looted": looted.keys()}


## Untrusted input: indices clamped, unknown flags dropped.
func from_dict(d: Dictionary) -> void:
	index = int(SaveSystem.read_num(d, "index", 0, 0, MissionDB.CHAIN.size()))
	var max_step: int = 0 if done() else mission().steps.size() - 1
	step = int(SaveSystem.read_num(d, "step", 0, 0, max_step))
	flags.clear()
	var f: Variant = d.get("flags", [])
	if f is Array:
		for x in f:
			if str(x) in MissionDB.FLAGS:
				flags[str(x)] = true
	looted.clear()
	var l: Variant = d.get("looted", [])
	if l is Array:
		for x in l.slice(0, 256):
			if x is String and x.length() <= 32:
				looted[x] = true
