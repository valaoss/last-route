class_name HitboxSet
extends RefCounted

## Bone-driven hit zones (head / torso / legs) shared by zombies and raiders.
## Areas are top_level and synced manually so non-uniform body scale never
## reaches the physics shapes (Jolt rejects it).

var owner: Node3D
var model: CharacterModel
var _areas: Array[Area3D] = []
var _bones: PackedInt32Array = []
var _offsets: Array[Transform3D] = []


func _init(o: Node3D, m: CharacterModel) -> void:
	owner = o
	model = m


## Standard humanoid layout; `s` = overall scale, `girth` = torso width factor.
func build_humanoid(s: float, girth := 1.0) -> void:
	add(&"head", "DEF-head", Vector3(0, 0.1, 0.02), _sphere(0.14 * s))
	add(&"torso", "DEF-spine.002", Vector3(0, 0.08, 0.0), _box(Vector3(0.42 * girth, 0.62 * s, 0.3 * girth)))
	for side in ["L", "R"]:
		add(&"legs", "DEF-thigh." + side, Vector3(0, -0.22, 0), _box(Vector3(0.17, 0.48, 0.18) * s))
		add(&"legs", "DEF-shin." + side, Vector3(0, -0.22, 0), _box(Vector3(0.13, 0.46, 0.14) * s))


func add(zone: StringName, bone: String, offset: Vector3, shape: Shape3D) -> void:
	var a := Area3D.new()
	a.collision_layer = 16
	a.collision_mask = 0
	a.monitoring = false
	a.top_level = true
	a.set_meta(&"enemy", owner)
	a.set_meta(&"zone", zone)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	a.add_child(cs)
	owner.add_child(a)
	var idx := model.skeleton.find_bone(bone)
	var rest := model.skeleton.get_bone_global_rest(idx)
	var along := rest.basis.y.normalized()
	# legs hang down from the hip/knee: place the box toward the child joint
	var pos := rest.origin + along * absf(offset.y) if offset.y < 0.0 else rest.origin + Vector3(0, offset.y, 0)
	var skel_xf := Transform3D(Basis.IDENTITY, pos + Vector3(0, 0, offset.z))
	_areas.append(a)
	_bones.append(idx)
	_offsets.append(rest.affine_inverse() * skel_xf)


func sync() -> void:
	var sk := model.skeleton
	var base := sk.global_transform
	for i in _areas.size():
		var xf := base * sk.get_bone_global_pose(_bones[i]) * _offsets[i]
		_areas[i].global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)


func disable() -> void:
	for a in _areas:
		a.collision_layer = 0


static func _sphere(r: float) -> SphereShape3D:
	var s := SphereShape3D.new()
	s.radius = r
	return s


static func _box(size: Vector3) -> BoxShape3D:
	var b := BoxShape3D.new()
	b.size = size
	return b
