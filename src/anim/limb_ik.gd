class_name LimbIK
extends SkeletonModifier3D

## Analytic two-bone IK for any number of limbs. Each chain blends in with its own
## weight so the same rig handles riding (hands→grips, feet→pegs/ground) and a
## support hand on long guns.

class Chain:
	var upper := -1
	var mid := -1
	var end := -1
	var target: Node3D
	var pole: Node3D
	var pole_dir := Vector3.FORWARD     ## used when pole node is null (skeleton space)
	var weight := 0.0
	var align_end := true


var chains: Dictionary = {}   # name -> Chain


func add_chain(key: StringName, upper: String, mid: String, end: String, target: Node3D, pole: Node3D = null, pole_dir := Vector3.FORWARD) -> Chain:
	var sk := get_skeleton()
	var c := Chain.new()
	c.upper = sk.find_bone(upper)
	c.mid = sk.find_bone(mid)
	c.end = sk.find_bone(end)
	c.target = target
	c.pole = pole
	c.pole_dir = pole_dir
	chains[key] = c
	return c


func set_weight(key: StringName, w: float) -> void:
	if chains.has(key):
		chains[key].weight = clampf(w, 0.0, 1.0)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null:
		return
	var to_skel := sk.global_transform.affine_inverse()
	for key in chains:
		var c: Chain = chains[key]
		if c.weight <= 0.001 or c.target == null or c.upper < 0 or c.mid < 0 or c.end < 0:
			continue
		var tgt := to_skel * c.target.global_transform
		var pole_pos: Vector3
		var gu := sk.get_bone_global_pose(c.upper)
		if c.pole:
			pole_pos = to_skel * c.pole.global_position
		else:
			pole_pos = gu.origin + c.pole_dir
		_solve(sk, c, tgt, pole_pos)


func _solve(sk: Skeleton3D, c: Chain, tgt: Transform3D, pole_pos: Vector3) -> void:
	var gu := sk.get_bone_global_pose(c.upper)
	var gm := sk.get_bone_global_pose(c.mid)
	var ge := sk.get_bone_global_pose(c.end)
	var a := gu.origin
	var b := gm.origin
	var e := ge.origin
	var w := c.weight
	var t := e.lerp(tgt.origin, w)
	var l1 := a.distance_to(b)
	var l2 := b.distance_to(e)
	var to_t := t - a
	var d := clampf(to_t.length(), 0.01, (l1 + l2) * 0.999)
	var dir := to_t.normalized()
	var pole_v := pole_pos - a
	var n := (pole_v - dir * pole_v.dot(dir))
	if n.length() < 0.0001:
		n = (b - a) - dir * (b - a).dot(dir)
	n = n.normalized()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var sin_a := sqrt(1.0 - cos_a * cos_a)
	var b_new := a + dir * l1 * cos_a + n * l1 * sin_a

	var r1 := _arc((b - a).normalized(), (b_new - a).normalized())
	var gu_new := Transform3D(Basis(r1) * gu.basis, a)
	var rel := gu_new * gu.affine_inverse()
	var gm_mid := rel * gm
	var ge_mid := rel * ge
	var r2 := _arc((ge_mid.origin - b_new).normalized(), (t - b_new).normalized())
	var gm_new := Transform3D(Basis(r2) * gm_mid.basis, b_new)
	var ge_new := gm_new * gm_mid.affine_inverse() * ge_mid
	if c.align_end:
		var tb := tgt.basis.orthonormalized()
		var cur := ge_new.basis.get_rotation_quaternion()
		ge_new.basis = Basis(cur.slerp(tb.get_rotation_quaternion(), w))
	sk.set_bone_global_pose(c.upper, gu_new)
	sk.set_bone_global_pose(c.mid, gm_new)
	sk.set_bone_global_pose(c.end, ge_new)


static func _arc(from: Vector3, to: Vector3) -> Quaternion:
	var d := from.dot(to)
	if d > 0.99999:
		return Quaternion.IDENTITY
	if d < -0.99999:
		var axis := from.cross(Vector3.UP)
		if axis.length() < 0.001:
			axis = from.cross(Vector3.RIGHT)
		return Quaternion(axis.normalized(), PI)
	return Quaternion(from, to)
