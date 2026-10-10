class_name PlayerAnim
extends Node3D

## Player presentation: layered AnimationTree (locomotion / upper-body weapon pose /
## one-shots / riding), procedural offsets (strafe hips, recoil, riding body
## language) and IK for riding and the support hand.

const COLORS := {
	"skin_color": Color("9c7a62"),
	"top_color": Color("3d3428"),      # waxed riding jacket
	"bottom_color": Color("2c333d"),   # worn denim
	"boot_color": Color("1d1916"),
	"sleeves": 1.0,
	"grime": 0.45,
	"decay": 0.0,
	"seed": 3.0,
}

var model: CharacterModel
var weapon_root: Node3D           ## parent of the in-hand weapon (right hand)
var weapon_nodes: Dictionary = {}  ## id -> Node3D
var support_target: Node3D
var right_target: Node3D
var _recoil := FeelMath.Spring.new(6.0, 0.45)
var _flinch := FeelMath.Spring.new(5.0, 0.5)
var _ride_blend := 0.0
var hips_twist := 0.0
var _loco_scale := 1.0


func setup() -> void:
	model = CharacterModel.new()
	model.name = "Model"
	add_child(model)
	model.setup(COLORS)
	_build_tree()
	_build_gear()


func _build_tree() -> void:
	var M := CharacterModel
	var bt := AnimationNodeBlendTree.new()
	var loco := AnimationNodeBlendSpace1D.new()
	loco.add_blend_point(M.anim(&"Idle"), 0.0, -1, &"Idle")
	loco.add_blend_point(M.anim(&"Walk"), 1.8, -1, &"Walk")
	loco.add_blend_point(M.anim(&"Jog_Fwd"), 4.2, -1, &"Jog_Fwd")
	loco.add_blend_point(M.anim(&"Sprint"), 6.2, -1, &"Sprint")
	loco.min_space = 0.0
	loco.max_space = 6.5
	loco.sync = true
	bt.add_node(&"loco", loco)
	bt.add_node(&"loco_ts", AnimationNodeTimeScale.new())
	bt.connect_node(&"loco_ts", 0, &"loco")

	var aim := AnimationNodeBlendSpace1D.new()
	aim.add_blend_point(M.anim(&"Pistol_Aim_Down"), -1.0, -1, &"Pistol_Aim_Down")
	aim.add_blend_point(M.anim(&"Pistol_Aim_Neutral"), 0.0, -1, &"Pistol_Aim_Neutral")
	aim.add_blend_point(M.anim(&"Pistol_Aim_Up"), 1.0, -1, &"Pistol_Aim_Up")
	aim.min_space = -1.0
	aim.max_space = 1.0
	bt.add_node(&"aim_bs", aim)
	bt.add_node(&"gun_idle", M.anim(&"Pistol_Idle"))
	bt.add_node(&"gun_aim", AnimationNodeBlend2.new())
	bt.connect_node(&"gun_aim", 0, &"gun_idle")
	bt.connect_node(&"gun_aim", 1, &"aim_bs")
	bt.add_node(&"melee_idle", M.anim(&"Sword_Idle"))
	bt.add_node(&"upper_sel", AnimationNodeBlend2.new())
	bt.connect_node(&"upper_sel", 0, &"gun_aim")
	bt.connect_node(&"upper_sel", 1, &"melee_idle")
	var upper_mix := AnimationNodeBlend2.new()
	model.upper_filter(upper_mix)
	bt.add_node(&"upper_mix", upper_mix)
	bt.connect_node(&"upper_mix", 0, &"loco_ts")
	bt.connect_node(&"upper_mix", 1, &"upper_sel")

	var prev := &"upper_mix"
	prev = _shot(bt, prev, &"reload", &"Pistol_Reload", true, 0.12, 0.2)
	prev = _shot(bt, prev, &"m1", &"Sword_Attack", false, 0.06, 0.18)
	prev = _shot(bt, prev, &"m2", &"Punch_Cross", false, 0.06, 0.18)
	prev = _shot(bt, prev, &"m3", &"Sword_Attack", false, 0.06, 0.22)
	prev = _shot(bt, prev, &"hit", &"Hit_Chest", true, 0.04, 0.15)
	prev = _shot(bt, prev, &"interact", &"PickUp_Table", false, 0.12, 0.2)
	prev = _shot(bt, prev, &"roll", &"Roll", false, 0.05, 0.16)

	bt.add_node(&"driving", M.anim(&"Driving"))
	bt.add_node(&"ride", AnimationNodeBlend2.new())
	bt.connect_node(&"ride", 0, prev)
	bt.connect_node(&"ride", 1, &"driving")

	var life := AnimationNodeTransition.new()
	life.add_input("alive")
	life.add_input("dead")
	life.xfade_time = 0.2
	bt.add_node(&"life", life)
	bt.add_node(&"death", M.anim(&"Death01"))
	bt.connect_node(&"life", 0, &"ride")
	bt.connect_node(&"life", 1, &"death")
	bt.connect_node(&"output", 0, &"life")
	model.make_tree(bt)
	model.set_param("upper_mix/blend_amount", 1.0)
	model.set_param("life/transition_request", "alive")


func _shot(bt: AnimationNodeBlendTree, prev: StringName, n: StringName, anim_name: StringName, upper: bool, fi: float, fo: float) -> StringName:
	var o := CharacterModel.one_shot(fi, fo)
	if upper:
		model.upper_filter(o)
	bt.add_node(n, o)
	var ts := StringName(String(n) + "_ts")
	bt.add_node(ts, AnimationNodeTimeScale.new())
	bt.add_node(StringName(String(n) + "_anim"), CharacterModel.anim(anim_name))
	bt.connect_node(ts, 0, StringName(String(n) + "_anim"))
	bt.connect_node(n, 0, prev)
	bt.connect_node(n, 1, ts)
	return n


func _build_gear() -> void:
	var sk := model.skeleton
	# helmet: open-face, matte, with goggles strap — silhouette reads "rider"
	var head := model.bone_rest_origin("DEF-head")
	var helm := Node3D.new()
	MeshKit.sphere(helm, 0.15, Vector3(0, 0.0, 0), Palette.pbr(Color("2b2d2a"), 0.55, 0.1), Vector3(1.0, 0.95, 1.08))
	MeshKit.box(helm, Vector3(0.25, 0.03, 0.2), Vector3(0, -0.06, -0.02), Palette.pbr(Color("2b2d2a"), 0.55, 0.1))
	MeshKit.box(helm, Vector3(0.22, 0.045, 0.05), Vector3(0, 0.02, 0.115), Palette.pbr(Color("3a3226"), 0.6, 0.0))
	MeshKit.box(helm, Vector3(0.17, 0.04, 0.02), Vector3(0, 0.02, 0.137), Palette.pbr(Color("1a2124"), 0.15, 0.6))
	model.attach_rigid("DEF-head", helm, Transform3D(Basis.IDENTITY, head + Vector3(0, 0.135, 0.01)))
	# backpack on the upper spine
	var spine := model.bone_rest_origin("DEF-spine.003")
	var pack := Node3D.new()
	MeshKit.box(pack, Vector3(0.27, 0.34, 0.13), Vector3.ZERO, Palette.mat(&"canvas"))
	MeshKit.box(pack, Vector3(0.24, 0.14, 0.06), Vector3(0, -0.1, -0.1), Palette.mat(&"canvas"))
	MeshKit.cyl(pack, 0.06, 0.32, Vector3(0, 0.23, 0.0), Palette.pbr(Color("3f4232"), 0.9, 0.0), Vector3(0, 0, 90), 10)
	model.attach_rigid("DEF-spine.003", pack, Transform3D(Basis.IDENTITY, spine + Vector3(0, -0.02, -0.17)))
	# weapon socket in the right hand (T-pose: arm along -X, palm down)
	var hand := model.bone_rest_origin("DEF-hand.R")
	weapon_root = Node3D.new()
	weapon_root.name = "WeaponSocket"
	model.attach_rigid("DEF-hand.R", weapon_root, Transform3D(Basis(Vector3.UP, PI * 0.5), hand + Vector3(-0.075, -0.025, 0.0)))
	support_target = Node3D.new()
	support_target.name = "SupportTarget"
	add_child(support_target)
	right_target = Node3D.new()
	right_target.name = "RightTarget"
	add_child(right_target)
	model.ik.add_chain(&"support", "DEF-upper_arm.L", "DEF-forearm.L", "DEF-hand.L", support_target, null, Vector3(0.6, -0.8, -0.2)).align_end = false
	model.ik.add_chain(&"right", "DEF-upper_arm.R", "DEF-forearm.R", "DEF-hand.R", right_target, null, Vector3(-0.6, -0.8, -0.2)).align_end = false


func add_weapon_model(w: WeaponData) -> void:
	var n := WeaponModels.build(w)
	n.visible = false
	weapon_root.add_child(n)
	weapon_nodes[w.id] = n


func show_weapon(id: StringName) -> void:
	for k in weapon_nodes:
		weapon_nodes[k].visible = k == id


func weapon_marker(id: StringName, marker: String) -> Node3D:
	var n: Node3D = weapon_nodes.get(id)
	return n.get_node_or_null(marker) if n else null


func kick(amount_deg: float) -> void:
	_recoil.impulse(deg_to_rad(amount_deg) * 25.0)


func flinch(amount: float) -> void:
	_flinch.impulse(amount * 12.0)


## Called every frame by the player with the current gameplay state.
func update_pose(dt: float, s: Dictionary) -> void:
	var speed: float = s.speed
	var backwards: bool = s.backwards
	model.set_param("loco/blend_position", speed)
	_loco_scale = FeelMath.damp(_loco_scale, -1.0 if backwards else 1.0, 14.0, dt)
	model.set_param("loco_ts/scale", _loco_scale)
	var holding: float = s.upper_weight
	model.set_param("upper_mix/blend_amount", holding)
	model.set_param("upper_sel/blend_amount", 1.0 if s.melee_weapon else 0.0)
	model.set_param("gun_aim/blend_amount", s.aim_weight)
	model.set_param("aim_bs/blend_position", s.aim_pitch)
	_ride_blend = FeelMath.damp(_ride_blend, s.ride, 10.0, dt) if s.ride_snap == false else s.ride
	model.set_param("ride/blend_amount", _ride_blend)

	# --- procedural layers (skeleton space: +Z fwd, +X left, +Y up)
	var rec := _recoil.step(0.0, dt)
	var fl := _flinch.step(0.0, dt)
	hips_twist = FeelMath.damp(hips_twist, s.hips_twist, 12.0, dt)
	var layer := {}
	if absf(hips_twist) > 0.001:
		layer["DEF-hips"] = Quaternion(Vector3.UP, hips_twist)
		layer["DEF-spine.002"] = Quaternion(Vector3.UP, -hips_twist * 0.5)
		layer["DEF-spine.003"] = Quaternion(Vector3.UP, -hips_twist * 0.5)
	var spine_pitch: float = s.get("spine_pitch", 0.0)
	var q_spine := Quaternion(Vector3.RIGHT, -rec * 0.5 + fl * 0.4 + spine_pitch)
	layer["DEF-spine.003"] = q_spine * layer.get("DEF-spine.003", Quaternion.IDENTITY)
	layer["DEF-upper_arm.R"] = Quaternion(Vector3.RIGHT, -rec)
	layer["DEF-upper_arm.L"] = Quaternion(Vector3.RIGHT, -rec * 0.8)
	if s.has("ride_lean"):
		var lean: float = s.ride_lean
		var pitch: float = s.ride_pitch
		layer["DEF-spine.001"] = Quaternion(Vector3.BACK, -lean * 0.15) * Quaternion(Vector3.RIGHT, pitch)
		layer["DEF-neck"] = Quaternion(Vector3.UP, s.ride_look) * Quaternion(Vector3.BACK, lean * 0.45)
	model.offsets.set_layer(&"proc", layer)

	model.ik.set_weight(&"support", s.support_ik)
	model.ik.set_weight(&"right", s.right_ik)
