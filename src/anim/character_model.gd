class_name CharacterModel
extends Node3D

## Wraps the CC0 humanoid (Quaternius UAL mannequin): region-tinted materials,
## layered AnimationTree, procedural modifiers and bone sockets. Used by the
## player and every zombie variant.

const SCENE := preload("res://assets/anims/ual_standard.glb")
const SHADER := preload("res://src/art/character.gdshader")
const LOOPED := [&"Idle", &"Walk", &"Jog_Fwd", &"Sprint", &"Driving", &"Pistol_Idle",
	&"Pistol_Aim_Neutral", &"Pistol_Aim_Up", &"Pistol_Aim_Down", &"Crouch_Idle", &"Crouch_Fwd",
	&"Sword_Idle", &"Walk_Formal", &"Sitting_Idle", &"Idle_Torch", &"Swim_Idle"]
const UPPER_BONES_PREFIX := ["DEF-spine.002", "DEF-spine.003", "DEF-neck", "DEF-head", "DEF-shoulder", "DEF-upper_arm",
	"DEF-forearm", "DEF-hand", "DEF-f_", "DEF-thumb"]

static var _region_mesh: ArrayMesh
static var _loops_set := false

var root: Node3D
var skeleton: Skeleton3D
var anim_player: AnimationPlayer
var tree: AnimationTree
var mesh_instance: MeshInstance3D
var ik: LimbIK
var offsets: PoseOffsets
var material: ShaderMaterial


func setup(colors: Dictionary) -> void:
	root = SCENE.instantiate()
	add_child(root)
	root.rotation.y = PI  # asset faces +Z; gameplay forward is -Z
	skeleton = root.find_child("Skeleton3D", true, false)
	anim_player = root.find_child("AnimationPlayer", true, false)
	mesh_instance = skeleton.find_child("Mannequin", true, false)
	mesh_instance.visibility_range_end = 100.0
	mesh_instance.visibility_range_end_margin = 10.0
	_ensure_loops()
	_apply_material(colors)
	offsets = PoseOffsets.new()
	offsets.name = "PoseOffsets"
	skeleton.add_child(offsets)
	ik = LimbIK.new()
	ik.name = "LimbIK"
	skeleton.add_child(ik)


func _ensure_loops() -> void:
	if _loops_set:
		return
	_loops_set = true
	for n in LOOPED:
		if anim_player.has_animation(n):
			anim_player.get_animation(n).loop_mode = Animation.LOOP_LINEAR


# ------------------------------------------------------------------ material

func _apply_material(colors: Dictionary) -> void:
	if _region_mesh == null:
		_region_mesh = _bake_regions(mesh_instance.mesh)
	mesh_instance.mesh = _region_mesh
	material = ShaderMaterial.new()
	material.shader = SHADER
	mesh_instance.material_override = material
	for k in colors:
		mesh_instance.set_instance_shader_parameter(k, colors[k])


## Bakes a body-region id + rest-pose coordinates into vertex colour so clothing
## zones stay put under skinning: r = region, g = height, b = side, a = depth.
static func _bake_regions(src: Mesh) -> ArrayMesh:
	var out := ArrayMesh.new()
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var cols := PackedColorArray()
		cols.resize(verts.size())
		for i in verts.size():
			var p := verts[i]
			var ax := absf(p.x)
			var region := 1.0  # top
			if p.y > 1.5 and ax < 0.16:
				region = 0.0   # head
			elif ax > 0.62:
				region = 0.0   # hands
			elif ax > 0.43:
				region = 4.0   # forearm
			elif p.y < 0.1:
				region = 3.0   # boots
			elif p.y < 0.915:
				region = 2.0   # legs
			elif p.y < 0.985:
				region = 3.0   # belt
			cols[i] = Color(region / 4.0, clampf(p.y / 1.85, 0.0, 1.0), p.x * 0.5 + 0.5, p.z * 0.5 + 0.5)
		arrays[Mesh.ARRAY_COLOR] = cols
		var fmt: int = src.surface_get_format(s)
		var flags := 0
		if fmt & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS:
			flags |= Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], _source_lods(src, s), flags)
	return out


## The importer's LOD index sets (edge length -> indices); rebuilding the mesh
## would otherwise drop them and every zombie would render at full detail.
static func _source_lods(src: Mesh, s: int) -> Dictionary:
	var lods := {}
	var d := RenderingServer.mesh_get_surface(src.get_rid(), s)
	var wide: bool = d.get("vertex_count", 0) > 65535
	for l in d.get("lods", []):
		var raw: PackedByteArray = l.index_data
		var idx := PackedInt32Array()
		if wide:
			idx = raw.to_int32_array()
		else:
			idx.resize(raw.size() / 2)
			for i in idx.size():
				idx[i] = raw.decode_u16(i * 2)
		lods[float(l.edge_length)] = idx
	return lods


# ------------------------------------------------------------------ helpers

func bone_attachment(bone: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone
	skeleton.add_child(ba)
	return ba


## Attaches `node` to `bone` so that, in the bind (T) pose, it sits at
## `skel_xform` in skeleton space — independent of how the bone is rolled.
func attach_rigid(bone: String, node: Node3D, skel_xform: Transform3D) -> BoneAttachment3D:
	var idx := skeleton.find_bone(bone)
	var ba := bone_attachment(bone)
	ba.add_child(node)
	node.transform = skeleton.get_bone_global_rest(idx).affine_inverse() * skel_xform
	return ba


func bone_rest_origin(bone: String) -> Vector3:
	return skeleton.get_bone_global_rest(skeleton.find_bone(bone)).origin


func make_tree(bt: AnimationNodeBlendTree) -> void:
	tree = AnimationTree.new()
	tree.name = "AnimationTree"
	root.add_child(tree)
	tree.root_node = NodePath("..")
	tree.anim_player = tree.get_path_to(anim_player)
	tree.tree_root = bt
	tree.active = true


func upper_filter(node: AnimationNode) -> void:
	node.filter_enabled = true
	for i in skeleton.get_bone_count():
		var bn := skeleton.get_bone_name(i)
		for prefix in UPPER_BONES_PREFIX:
			if bn.begins_with(prefix):
				node.set_filter_path(NodePath("Rig/Skeleton3D:" + bn), true)
				break


static func anim(n: StringName) -> AnimationNodeAnimation:
	var a := AnimationNodeAnimation.new()
	a.animation = n
	return a


static func one_shot(fade_in := 0.08, fade_out := 0.15) -> AnimationNodeOneShot:
	var o := AnimationNodeOneShot.new()
	o.fadein_time = fade_in
	o.fadeout_time = fade_out
	return o


func fire(shot: StringName) -> void:
	tree.set("parameters/%s/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func abort(shot: StringName) -> void:
	tree.set("parameters/%s/request" % shot, AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)


func is_playing_shot(shot: StringName) -> bool:
	return tree.get("parameters/%s/active" % shot)


func set_param(p: String, v: Variant) -> void:
	tree.set("parameters/" + p, v)


func anim_length(n: StringName) -> float:
	return anim_player.get_animation(n).length if anim_player.has_animation(n) else 1.0


## World-space position of a bone (for hit zones, effects, IK queries).
func bone_global(bone: String) -> Vector3:
	var i := skeleton.find_bone(bone)
	if i < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(i).origin
