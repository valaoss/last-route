class_name RegionPanel
extends MenuPanel

## Garage map board: the region's six gauges, the day, and what each one is
## doing to the town right now.

var region: RegionState
var region_name := "Karaçam"
var report := {}            ## {key: delta} from the last night, shown as arrows


func refresh() -> void:
	clear_body()
	body.add_child(label("%s  ·  Gün %d" % [region_name.to_upper(), region.day], 26, AMBER))
	for k in RegionState.KEYS:
		var val := region.get_value(k)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var name_l := label(RegionState.NAMES[k], 15, INK, false)
		name_l.custom_minimum_size = Vector2(170, 0)
		row.add_child(name_l)
		var bar := ProgressBar.new()
		bar.custom_minimum_size = Vector2(250, 12)
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.show_percentage = false
		bar.max_value = 100.0
		bar.value = val
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(1, 1, 1, 0.08)
		var fg := StyleBoxFlat.new()
		fg.bg_color = BAD if k in ["threat", "hostility"] else GOOD
		bar.add_theme_stylebox_override("background", bg)
		bar.add_theme_stylebox_override("fill", fg)
		row.add_child(bar)
		var d: float = report.get(k, 0.0)
		row.add_child(label("%d%s" % [roundi(val), ("  (%+d)" % roundi(d)) if absf(d) >= 0.5 else ""], 15, DIM, false))
		body.add_child(row)
	body.add_child(label(hints(region), 14, DIM))
	close_row()


## Plain-language consequences of the current values.
static func hints(r: RegionState) -> String:
	var out := PackedStringArray()
	out.append("Dinlenince öldürdüğün zombilerin ~%%%d'i geri döner." % roundi(r.revive_share() * 100.0))
	out.append("Aranmış yerlerin ~%%%d'i bir gecede yeniden dolar." % roundi(r.refill_chance() * 100.0))
	out.append("Haydut devriyesi: %s." % ("kuzey yolunda dolaşıyor" if r.raiders_patrol() else "dağıldı"))
	if r.get_value("infrastructure") >= 50.0:
		out.append("Elektrik var: dükkân tabelaları yanıyor, telsize yeni insanlar ulaşıyor.")
	if r.get_value("route") >= 40.0:
		out.append("Ana cadde işaretli güvenli rota.")
	if r.get_value("threat") < 45.0:
		out.append("Çarşıda cesetler yakılıyor; duman uzaktan görünür.")
	return "\n".join(out)
