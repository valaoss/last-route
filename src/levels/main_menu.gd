extends Control

## Prototype hub: choose a feel test and the control options.

const TRACK := "res://src/levels/test_track.tscn"
const ARENA := "res://src/levels/combat_arena.tscn"
const GAS_RUN := "res://src/levels/gas_run.tscn"
const HOOD := "res://src/levels/neighborhood.tscn"


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("1b1c1a")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var v := VBoxContainer.new()
	v.set_anchors_preset(Control.PRESET_CENTER)
	v.custom_minimum_size = Vector2(420, 0)
	v.position = Vector2(-210, -220)
	v.add_theme_constant_override("separation", 12)
	add_child(v)
	var title := Label.new()
	title.text = "LAST ROUTE"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color("e6dfcf"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var sub := Label.new()
	sub.text = "P3 · derinlik: bölge, gün, tezgâh"
	sub.add_theme_color_override("font_color", Color("e8b04a"))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var save := SaveSystem.load_data()
	if not save.is_empty():
		v.add_child(_button("Devam et", func(): _continue(save)))
	v.add_child(_button("Karaçam mahallesi · yeni oyun", func(): SaveSystem.pending = {}; get_tree().change_scene_to_file(HOOD)))
	v.add_child(_button("Sürüş test pisti", func(): get_tree().change_scene_to_file(TRACK)))
	v.add_child(_button("Savaş arenası", func(): get_tree().change_scene_to_file(ARENA)))
	v.add_child(_button("Senaryo · Benzinlik kaçışı (yeni)", func(): SaveSystem.pending = {}; get_tree().change_scene_to_file(GAS_RUN)))
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
	var touch := CheckBox.new()
	touch.text = "Dokunmatik kontrolleri göster"
	touch.button_pressed = GameSettings.show_touch_ui
	touch.toggled.connect(func(on): GameSettings.show_touch_ui = on; GameSettings.save_settings())
	v.add_child(touch)
	var cmd := OS.get_cmdline_user_args()
	if "--track" in cmd:
		get_tree().change_scene_to_file.call_deferred(TRACK)
	elif "--arena" in cmd:
		get_tree().change_scene_to_file.call_deferred(ARENA)
	elif "--gasrun" in cmd:
		get_tree().change_scene_to_file.call_deferred(GAS_RUN)
	elif "--hood" in cmd:
		get_tree().change_scene_to_file.call_deferred(HOOD)


func _continue(save: Dictionary) -> void:
	var path := SaveSystem.level_path(save)
	if path == "":
		return
	SaveSystem.pending = save
	get_tree().change_scene_to_file(path)


func _button(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_size_override("font_size", 20)
	b.pressed.connect(cb)
	return b
