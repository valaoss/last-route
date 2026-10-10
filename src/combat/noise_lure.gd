class_name NoiseLure
extends RigidBody3D

## Thrown alarm clock: lands, then beeps loudly for a while. Zombies (and
## raiders) investigate it — pull a horde off the road or into a raider camp.

const RADIUS := 48.0
const DURATION := 14.0
const PERIOD := 0.8

var thrower: Node
var _armed_t := 0.6
var _life := DURATION
var _beep_t := 0.0
var _light: OmniLight3D


func _ready() -> void:
	mass = 0.6
	collision_layer = 0
	collision_mask = 1
	continuous_cd = true
	var cs := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 0.12
	cs.shape = sh
	add_child(cs)
	MeshKit.box(self, Vector3(0.18, 0.14, 0.1), Vector3.ZERO, Palette.mat(&"car_paint_b"))
	MeshKit.box(self, Vector3(0.05, 0.03, 0.03), Vector3(0, 0.08, 0), Palette.mat(&"taillight"), Vector3.ZERO, false)
	_light = OmniLight3D.new()
	_light.light_color = Color("ff4a2a")
	_light.omni_range = 3.0
	_light.light_energy = 0.0
	_light.position = Vector3(0, 0.2, 0)
	add_child(_light)


func _physics_process(dt: float) -> void:
	if _armed_t > 0.0:
		_armed_t -= dt
		return
	_life -= dt
	_beep_t -= dt
	if _beep_t <= 0.0:
		_beep_t = PERIOD
		Sfx.play_at(&"lure_beep", global_position, 4.0, 0.0)
		NoiseBus.emit_noise(global_position, RADIUS, NoiseBus.Priority.ALARM, self)
	_light.light_energy = 2.0 if _beep_t > PERIOD - 0.15 else 0.0
	if _life <= 0.0:
		queue_free()


## Spawns a lure at `from` flying along `dir` (flat forward).
static func throw(parent: Node, from: Vector3, dir: Vector3, by: Node) -> NoiseLure:
	var l := NoiseLure.new()
	l.thrower = by
	parent.add_child(l)
	l.global_position = from
	l.linear_velocity = dir.normalized() * 9.0 + Vector3.UP * 4.5
	l.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-6, 6), randf_range(-6, 6))
	return l
