class_name AttackSlots
extends RefCounted

## Limits how many enemies may attack the player at once; the rest circle and wait.
## Keeps crowds readable and stops everyone running the same straight line.

const MAX_ATTACKERS := 3

static var _holders: Array = []


static func request(z: Node) -> bool:
	_prune()
	if z in _holders:
		return true
	if _holders.size() >= MAX_ATTACKERS:
		return false
	_holders.append(z)
	return true


static func release(z: Node) -> void:
	_holders.erase(z)


static func count() -> int:
	_prune()
	return _holders.size()


static func _prune() -> void:
	_holders = _holders.filter(func(h): return is_instance_valid(h) and h.is_alive())
