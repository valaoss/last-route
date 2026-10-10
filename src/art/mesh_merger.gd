class_name MeshMerger
extends RefCounted

## Bakes the many small static MeshInstance3Ds under a root into few meshes per
## chunk. Everything on the shared world shader collapses into ONE mesh per
## (chunk, shadow mode): each source's colour/roughness/grime/etc. travel in
## CUSTOM0..2 and the shader reads them (vertex_params). Other materials merge
## per (material, chunk, shadow). Colliders are untouched. Nodes tagged with
## meta "no_merge" (or under one) are left alone.

const WORLD_SHADER := "res://src/art/world_surface.gdshader"
const CUSTOM_FLAGS := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
	| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT)


static func merge(root: Node3D, chunk := 96.0) -> Dictionary:
	var groups := {}
	var count := 0
	var world_mat: ShaderMaterial
	for mi: MeshInstance3D in root.find_children("*", "MeshInstance3D", true, false):
		if not _mergeable(mi, root):
			continue
		var mat: Material = mi.material_override
		if mat == null:
			mat = mi.mesh.surface_get_material(0)
		var xf := mi.global_transform
		var is_world: bool = mat is ShaderMaterial and mat.shader != null and mat.shader.resource_path == WORLD_SHADER
		if is_world and world_mat == null:
			world_mat = mat.duplicate()
			world_mat.set_shader_parameter(&"vertex_params", true)
		var key := ["world" if is_world else mat, floori(xf.origin.x / chunk), floori(xf.origin.z / chunk), mi.cast_shadow]
		if not groups.has(key):
			groups[key] = []
		groups[key].append([mi.mesh, xf, _params(mat) if is_world else []])
		mi.get_parent().remove_child(mi)
		mi.free()
		count += 1
	for key in groups:
		var out := MeshInstance3D.new()
		out.name = "Merged_%d" % root.get_child_count()
		out.mesh = _bake(groups[key], key[0] is String)
		out.material_override = world_mat if key[0] is String else key[0]
		out.cast_shadow = key[3]
		root.add_child(out)
	return {"sources": count, "meshes": groups.size()}


## Collapses the leaf MeshInstance3D children of every node under `root` into
## one mesh per parent (one surface per material), in the parent's space. For
## articulated props (the bike): parts that move together share a draw per material.
static func merge_rigid(root: Node3D) -> int:
	var removed := 0
	var parents: Array = [root] + root.find_children("*", "Node3D", true, false).filter(func(n): return not n is GeometryInstance3D)
	for parent: Node3D in parents:
		var groups := {}
		var parts := []
		for c in parent.get_children():
			var mi := c as MeshInstance3D
			if mi == null or mi.get_child_count() > 0 or mi.has_meta(&"no_merge") or not mi.visible or mi.mesh == null or mi.mesh.get_surface_count() != 1:
				continue
			var mat: Material = mi.material_override if mi.material_override else mi.mesh.surface_get_material(0)
			if not groups.has(mat):
				groups[mat] = []
			groups[mat].append([mi.mesh, mi.transform, []])
			parts.append(mi)
		if parts.size() < 2:
			continue
		var am := ArrayMesh.new()
		for mat in groups:
			_bake(groups[mat], false, am)
			am.surface_set_material(am.get_surface_count() - 1, mat)
		var out := MeshInstance3D.new()
		out.name = "RigidMerged"
		out.mesh = am
		parent.add_child(out)
		for mi in parts:
			parent.remove_child(mi)
			mi.free()
		removed += parts.size() - 1
	return removed


static func _mergeable(mi: MeshInstance3D, root: Node3D) -> bool:
	if mi.mesh == null or mi.mesh.get_surface_count() != 1 or not mi.is_visible_in_tree() or mi.skin != null:
		return false
	if mi.mesh is ArrayMesh and mi.mesh.surface_get_primitive_type(0) != Mesh.PRIMITIVE_TRIANGLES:
		return false
	var n: Node = mi
	while n != root and n != null:
		if n.has_meta(&"no_merge"):
			return false
		n = n.get_parent()
	return true


## World-shader params of one material: [linear colour, (rough, metal, grime, streaks), (cracks, puddles, moss)].
static func _params(m: ShaderMaterial) -> Array:
	var c: Color = _p(m, &"base_color", Color(0.5, 0.5, 0.5))
	return [c.srgb_to_linear(), Color(_p(m, &"roughness_base", 0.9), _p(m, &"metallic_base", 0.0), _p(m, &"grime_amount", 0.5), _p(m, &"streak_amount", 0.4)),
		Color(_p(m, &"cracks", 0.0), _p(m, &"puddles", 0.0), _p(m, &"moss_top", 0.0), 0.0)]


static func _p(m: ShaderMaterial, n: StringName, fallback: Variant) -> Variant:
	var v: Variant = m.get_shader_parameter(n)
	return fallback if v == null else v


static func _bake(items: Array, world: bool, into: ArrayMesh = null) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var idx := PackedInt32Array()
	var cu := [PackedFloat32Array(), PackedFloat32Array(), PackedFloat32Array()]
	for it in items:
		var a: Array = (it[0] as Mesh).surface_get_arrays(0)
		var xf: Transform3D = it[1]
		var nb := xf.basis.inverse().transposed()
		var base := verts.size()
		var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = a[Mesh.ARRAY_NORMAL]
		var uv: Variant = a[Mesh.ARRAY_TEX_UV]
		for i in v.size():
			verts.append(xf * v[i])
			norms.append((nb * n[i]).normalized() if n.size() > i else Vector3.UP)
			uvs.append(uv[i] if uv is PackedVector2Array and uv.size() > i else Vector2.ZERO)
		if world:
			var o := xf.origin
			var h := fposmod(sin(o.x * 12.9898 + o.z * 78.233 + o.y * 37.719) * 43758.5453, 1.0)
			var par: Array = it[2]
			var vals := [Color(par[0].r, par[0].g, par[0].b, h), par[1], par[2]]
			for k in 3:
				var c: Color = vals[k]
				var quad := PackedFloat32Array([c.r, c.g, c.b, c.a])
				for i in v.size():
					cu[k].append_array(quad)
		var ix: Variant = a[Mesh.ARRAY_INDEX]
		if ix is PackedInt32Array and not ix.is_empty():
			for k in ix:
				idx.append(base + k)
		else:
			for k in v.size():
				idx.append(base + k)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = idx
	var flags := 0
	if world:
		arrays[Mesh.ARRAY_CUSTOM0] = cu[0]
		arrays[Mesh.ARRAY_CUSTOM1] = cu[1]
		arrays[Mesh.ARRAY_CUSTOM2] = cu[2]
		flags = CUSTOM_FLAGS
	var am := into if into else ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
	return am
