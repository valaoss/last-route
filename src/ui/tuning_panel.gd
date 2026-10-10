class_name TuningPanel
extends PanelContainer

## Live feel tuning (F1). Every exported MotoTuning value gets a slider; changes
## apply immediately and can be saved to user:// (and to res://config in dev).

var bike: Moto


func setup(b: Moto) -> void:
	bike = b
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_bottom = 1.0
	offset_left = -440
	offset_top = 60
	offset_bottom = -20
	offset_right = -20
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.08, 0.075, 0.88)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	add_theme_stylebox_override("panel", sb)
	var v := VBoxContainer.new()
	add_child(v)
	var title := Label.new()
	title.text = "Sürüş hissi ayarları"
	title.add_theme_font_size_override("font_size", 18)
	v.add_child(title)
	_options(v)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for p in bike.tuning.get_property_list():
		if p.usage & PROPERTY_USAGE_GROUP:
			var g := Label.new()
			g.text = p.name
			g.add_theme_color_override("font_color", Color("e8b04a"))
			list.add_child(g)
			continue
		if not (p.usage & PROPERTY_USAGE_SCRIPT_VARIABLE) or not (p.usage & PROPERTY_USAGE_EDITOR):
			continue
		if p.type != TYPE_FLOAT and p.type != TYPE_INT:
			continue
		list.add_child(_row(p.name, p.type == TYPE_INT))
	var h := HBoxContainer.new()
	v.add_child(h)
	var save := Button.new()
	save.text = "Kaydet"
	save.pressed.connect(_save)
	h.add_child(save)
	var reset := Button.new()
	reset.text = "Varsayılan"
	reset.pressed.connect(func():
		bike.tuning = MotoTuning.new()
		get_tree().reload_current_scene())
	h.add_child(reset)


func _options(v: VBoxContainer) -> void:
	var scheme := OptionButton.new()
	scheme.add_item("Kontrol A · Arcade")
	scheme.add_item("Kontrol B · Asistanlı")
	scheme.selected = GameSettings.control_scheme
	scheme.item_selected.connect(func(i): GameSettings.control_scheme = i; GameSettings.save_settings())
	v.add_child(scheme)
	var aa := OptionButton.new()
	for n in ["Aim assist: Kapalı", "Aim assist: Düşük", "Aim assist: Orta"]:
		aa.add_item(n)
	aa.selected = GameSettings.aim_assist
	aa.item_selected.connect(func(i): GameSettings.aim_assist = i; GameSettings.save_settings())
	v.add_child(aa)
	var shake := CheckBox.new()
	shake.text = "Kamera sarsıntısı"
	shake.button_pressed = GameSettings.camera_shake
	shake.toggled.connect(func(on): GameSettings.camera_shake = on; GameSettings.save_settings())
	v.add_child(shake)
	var fov := CheckBox.new()
	fov.text = "Hızla FOV artışı"
	fov.button_pressed = GameSettings.speed_fov
	fov.toggled.connect(func(on): GameSettings.speed_fov = on; GameSettings.save_settings())
	v.add_child(fov)


func _row(prop: String, is_int: bool) -> Control:
	var t := bike.tuning
	var val: float = t.get(prop)
	var h := HBoxContainer.new()
	var l := Label.new()
	l.text = prop
	l.custom_minimum_size = Vector2(170, 0)
	l.add_theme_font_size_override("font_size", 12)
	h.add_child(l)
	var s := HSlider.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.min_value = 0.0
	s.max_value = maxf(absf(val) * 3.0, 1.0)
	s.step = 1.0 if is_int else s.max_value / 300.0
	s.value = val
	h.add_child(s)
	var num := Label.new()
	num.custom_minimum_size = Vector2(56, 0)
	num.add_theme_font_size_override("font_size", 12)
	num.text = str(snappedf(val, 0.001))
	h.add_child(num)
	s.value_changed.connect(func(x):
		bike.tuning.set(prop, int(x) if is_int else x)
		num.text = str(snappedf(x, 0.001)))
	return h


func _save() -> void:
	ResourceSaver.save(bike.tuning, "user://moto_tuning.tres")
	if OS.has_feature("editor") or OS.is_debug_build():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://config"))
		ResourceSaver.save(bike.tuning, "res://config/moto_tuning.tres")
