class_name MeshKit
extends RefCounted

## Small helpers to assemble props from primitives with consistent materials.

static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, rot_deg: Vector3, mat: Material, shadows := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.rotation_degrees = rot_deg
	mi.material_override = mat
	if not shadows:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi

static func box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO, shadows := true) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _add(parent, m, pos, rot_deg, mat, shadows)

static func cyl(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO, segments := 16, top_radius := -1.0) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.bottom_radius = radius
	m.top_radius = radius if top_radius < 0.0 else top_radius
	m.height = height
	m.radial_segments = segments
	m.rings = 1
	return _add(parent, m, pos, rot_deg, mat)

static func sphere(parent: Node3D, radius: float, pos: Vector3, mat: Material, scale := Vector3.ONE, segments := 16) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = segments
	m.rings = segments / 2
	var mi := _add(parent, m, pos, Vector3.ZERO, mat)
	mi.scale = scale
	return mi

static func capsule(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO, scale := Vector3.ONE) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 16
	m.rings = 6
	var mi := _add(parent, m, pos, rot_deg, mat)
	mi.scale = scale
	return mi

static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, mat: Material, rot_deg := Vector3.ZERO) -> MeshInstance3D:
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = 28
	m.ring_segments = 10
	return _add(parent, m, pos, rot_deg, mat)

## Cylinder spanning two points (pipes, struts, fork legs).
static func strut(parent: Node3D, a: Vector3, b: Vector3, radius: float, mat: Material) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = radius
	m.bottom_radius = radius
	m.height = a.distance_to(b)
	m.radial_segments = 10
	m.rings = 1
	var mi := MeshInstance3D.new()
	mi.mesh = m
	mi.material_override = mat
	parent.add_child(mi)
	var up := (b - a).normalized()
	var side := up.cross(Vector3.FORWARD)
	if side.length() < 0.01:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	var fwd := side.cross(up)
	mi.transform = Transform3D(Basis(side, up, fwd), (a + b) * 0.5)
	return mi

static func static_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, surface := &"", rot_deg := Vector3.ZERO) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg
	if surface != &"":
		body.set_meta(&"surface", surface)
	parent.add_child(body)
	var cs := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = size
	cs.shape = sh
	body.add_child(cs)
	box(body, size, Vector3.ZERO, mat)
	return body
