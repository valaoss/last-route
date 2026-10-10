class_name WeaponModels
extends RefCounted

## Procedural weapon meshes. Forward is -Z, the firing-hand grip is the origin.
## Each model exposes "Muzzle" and "Support" (off-hand) markers; shotgun has "Pump".

static func build(w: WeaponData) -> Node3D:
	var root := Node3D.new()
	root.name = String(w.id)
	match w.kind:
		WeaponData.Kind.PISTOL: _pistol(root)
		WeaponData.Kind.CARBINE: _carbine(root)
		WeaponData.Kind.SHOTGUN: _shotgun(root)
		WeaponData.Kind.MELEE: _pipe(root)
	for c in root.get_children():
		if c is GeometryInstance3D:
			(c as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	MeshMerger.merge_rigid(root)
	return root


static func _marker(root: Node3D, n: String, pos: Vector3) -> void:
	var m := Marker3D.new()
	m.name = n
	m.position = pos
	root.add_child(m)


static func _pistol(r: Node3D) -> void:
	var metal := Palette.mat(&"gun_metal")
	var poly := Palette.mat(&"gun_polymer")
	MeshKit.box(r, Vector3(0.032, 0.034, 0.2), Vector3(0, 0.055, -0.07), metal)          # slide
	MeshKit.box(r, Vector3(0.03, 0.026, 0.17), Vector3(0, 0.03, -0.06), poly)            # frame
	MeshKit.box(r, Vector3(0.03, 0.115, 0.048), Vector3(0, -0.025, 0.012), poly, Vector3(-14, 0, 0))  # grip
	MeshKit.box(r, Vector3(0.008, 0.012, 0.012), Vector3(0, 0.078, -0.16), metal)        # front sight
	MeshKit.box(r, Vector3(0.022, 0.01, 0.01), Vector3(0, 0.078, 0.02), metal)          # rear sight
	MeshKit.box(r, Vector3(0.012, 0.02, 0.05), Vector3(0, 0.005, -0.04), metal)          # trigger guard
	_marker(r, "Muzzle", Vector3(0, 0.055, -0.175))
	_marker(r, "Support", Vector3(-0.03, -0.03, 0.0))


static func _carbine(r: Node3D) -> void:
	var metal := Palette.mat(&"gun_metal")
	var poly := Palette.mat(&"gun_polymer")
	MeshKit.box(r, Vector3(0.05, 0.075, 0.36), Vector3(0, 0.045, -0.1), metal)           # receiver
	MeshKit.box(r, Vector3(0.056, 0.06, 0.24), Vector3(0, 0.04, -0.38), poly)            # handguard
	MeshKit.cyl(r, 0.012, 0.22, Vector3(0, 0.05, -0.6), metal, Vector3(90, 0, 0), 8)      # barrel
	MeshKit.cyl(r, 0.018, 0.05, Vector3(0, 0.05, -0.72), metal, Vector3(90, 0, 0), 8)     # muzzle device
	MeshKit.box(r, Vector3(0.035, 0.11, 0.05), Vector3(0, -0.035, 0.0), poly, Vector3(-18, 0, 0))   # pistol grip
	MeshKit.box(r, Vector3(0.032, 0.15, 0.06), Vector3(0, -0.06, -0.15), metal, Vector3(12, 0, 0))   # magazine
	MeshKit.box(r, Vector3(0.04, 0.05, 0.24), Vector3(0, 0.03, 0.2), poly, Vector3(4, 0, 0))         # stock
	MeshKit.box(r, Vector3(0.045, 0.1, 0.03), Vector3(0, 0.02, 0.32), poly)                          # butt
	MeshKit.box(r, Vector3(0.022, 0.03, 0.08), Vector3(0, 0.098, -0.08), metal)                      # sight
	_marker(r, "Muzzle", Vector3(0, 0.05, -0.75))
	_marker(r, "Support", Vector3(0, 0.0, -0.36))


static func _shotgun(r: Node3D) -> void:
	var metal := Palette.mat(&"gun_metal")
	var wood := Palette.mat(&"gun_wood")
	MeshKit.box(r, Vector3(0.05, 0.07, 0.24), Vector3(0, 0.045, -0.06), metal)           # receiver
	MeshKit.cyl(r, 0.016, 0.52, Vector3(0, 0.068, -0.44), metal, Vector3(90, 0, 0), 10)   # barrel
	MeshKit.cyl(r, 0.014, 0.4, Vector3(0, 0.035, -0.38), metal, Vector3(90, 0, 0), 10)    # tube mag
	var pump := Node3D.new()
	pump.name = "Pump"
	pump.position = Vector3(0, 0.035, -0.36)
	r.add_child(pump)
	MeshKit.cyl(pump, 0.026, 0.17, Vector3.ZERO, wood, Vector3(90, 0, 0), 12)
	MeshKit.box(r, Vector3(0.036, 0.1, 0.05), Vector3(0, -0.03, 0.04), wood, Vector3(-20, 0, 0))  # grip
	MeshKit.box(r, Vector3(0.042, 0.075, 0.3), Vector3(0, 0.0, 0.22), wood, Vector3(9, 0, 0))     # stock
	MeshKit.box(r, Vector3(0.046, 0.11, 0.03), Vector3(0, -0.02, 0.37), Palette.mat(&"rubber"))   # pad
	_marker(r, "Muzzle", Vector3(0, 0.068, -0.71))
	_marker(r, "Support", Vector3(0, 0.0, -0.36))


static func _pipe(r: Node3D) -> void:
	MeshKit.cyl(r, 0.021, 0.78, Vector3(0, 0, -0.27), Palette.mat(&"rust_metal"), Vector3(90, 0, 0), 10)
	MeshKit.cyl(r, 0.026, 0.16, Vector3(0, 0, 0.02), Palette.mat(&"bike_seat"), Vector3(90, 0, 0), 10)   # taped grip
	MeshKit.cyl(r, 0.034, 0.05, Vector3(0, 0, -0.64), Palette.mat(&"rust_metal"), Vector3(90, 0, 0), 10)  # elbow joint
	_marker(r, "Muzzle", Vector3(0, 0, -0.66))
	_marker(r, "Support", Vector3(0, 0, 0.1))
