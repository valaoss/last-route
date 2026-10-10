class_name PoseOffsets
extends SkeletonModifier3D

## Additive, procedural bone rotations applied after animation. Drives aim twist,
## strafing hip counter-rotation, riding lean, zombie posture and hit flinches.
## Rotations are expressed in *skeleton space* axes and applied around the bone.

var _offsets: Dictionary = {}     # bone index -> Quaternion (skeleton-space)
var _layers: Dictionary = {}      # layer name -> {bone index: Quaternion}


func set_layer(layer: StringName, bone_rotations: Dictionary) -> void:
	var sk := get_skeleton()
	var resolved := {}
	for bone_name in bone_rotations:
		var idx := sk.find_bone(bone_name)
		if idx >= 0:
			resolved[idx] = bone_rotations[bone_name]
	_layers[layer] = resolved


func clear_layer(layer: StringName) -> void:
	_layers.erase(layer)


func _process_modification() -> void:
	var sk := get_skeleton()
	if sk == null or _layers.is_empty():
		return
	# combine layers per bone
	_offsets.clear()
	for layer in _layers.values():
		for idx in layer:
			var q: Quaternion = layer[idx]
			_offsets[idx] = q * _offsets.get(idx, Quaternion.IDENTITY)
	# apply parents first so children inherit
	var bones := _offsets.keys()
	bones.sort()
	for idx in bones:
		var q: Quaternion = _offsets[idx]
		if q.is_equal_approx(Quaternion.IDENTITY):
			continue
		var g := sk.get_bone_global_pose(idx)
		g.basis = Basis(q) * g.basis
		sk.set_bone_global_pose(idx, g)
