extends Node

## Central sound-awareness channel. Emitters publish a world position and an audible
## radius; AI listeners filter by distance themselves.

signal noise_emitted(pos: Vector3, radius: float, priority: int, source: Node)

enum Priority { AMBIENT, MOVEMENT, ENGINE, COMBAT, ALARM }

var _recent: Array[Dictionary] = []

func emit_noise(pos: Vector3, radius: float, priority: int = Priority.MOVEMENT, source: Node = null) -> void:
	if radius <= 0.0:
		return
	_recent.append({"pos": pos, "radius": radius, "t": Time.get_ticks_msec()})
	if _recent.size() > 16:
		_recent.pop_front()
	noise_emitted.emit(pos, radius, priority, source)

func recent_noises(max_age_ms: int = 1500) -> Array[Dictionary]:
	var now := Time.get_ticks_msec()
	return _recent.filter(func(n): return now - n.t <= max_age_ms)
