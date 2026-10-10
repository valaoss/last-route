class_name FeelMath
extends RefCounted

## Frame-rate independent smoothing helpers used by camera, vehicle and animation code.

## Exponential approach; `rate` = 1/time-constant.
static func damp(current: float, target: float, rate: float, delta: float) -> float:
	return lerpf(target, current, exp(-rate * delta))

static func damp_v3(current: Vector3, target: Vector3, rate: float, delta: float) -> Vector3:
	return target.lerp(current, exp(-rate * delta))

static func damp_angle(current: float, target: float, rate: float, delta: float) -> float:
	return current + angle_difference(current, target) * (1.0 - exp(-rate * delta))

## Asymmetric approach (different rise and fall times), used for steering input.
static func approach_asym(current: float, target: float, rise_time: float, fall_time: float, delta: float) -> float:
	var rising := current == 0.0 or (signf(target) == signf(current) and absf(target) > absf(current))
	var t := rise_time if rising else fall_time
	return move_toward(current, target, delta / maxf(t, 0.001))


## Critically-damped / under-damped second-order spring. Holds its own state.
class Spring:
	var value := 0.0
	var velocity := 0.0
	var frequency := 4.0
	var damping := 0.75

	func _init(freq := 4.0, zeta := 0.75) -> void:
		frequency = freq
		damping = zeta

	func step(target: float, delta: float) -> float:
		var omega := TAU * frequency
		# semi-implicit Euler, sub-stepped for stability at low frame rates
		var steps := maxi(1, ceili(delta / 0.008))
		var h := delta / steps
		for i in steps:
			var accel := omega * omega * (target - value) - 2.0 * damping * omega * velocity
			velocity += accel * h
			value += velocity * h
		return value

	func impulse(v: float) -> void:
		velocity += v

	func reset(v := 0.0) -> void:
		value = v
		velocity = 0.0


class Spring3:
	var value := Vector3.ZERO
	var velocity := Vector3.ZERO
	var frequency := 4.0
	var damping := 0.75

	func _init(freq := 4.0, zeta := 0.75) -> void:
		frequency = freq
		damping = zeta

	func step(target: Vector3, delta: float) -> Vector3:
		var omega := TAU * frequency
		var steps := maxi(1, ceili(delta / 0.008))
		var h := delta / steps
		for i in steps:
			var accel := (target - value) * omega * omega - velocity * 2.0 * damping * omega
			velocity += accel * h
			value += velocity * h
		return value

	func impulse(v: Vector3) -> void:
		velocity += v

	func reset(v := Vector3.ZERO) -> void:
		value = v
		velocity = Vector3.ZERO
