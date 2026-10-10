class_name MissionDB
extends RefCounted

## Mission chain data. Steps reference named places / loot ids / target ids that
## the level provides, so the data stays independent of map coordinates.
## Step types:
##   goto     {place, r}            reach a place
##   loot     {ids}                 search all listed loot points
##   interact {target}              use a MissionTarget
##   clear    {tag}                 every enemy carrying the tag is dead or fleeing
## Lines are [speaker, text]; speaker "" = the courier's own thought.

const ME := ""
const NILAY := "Telsiz · Nilay"

const CHAIN := [
	{
		"id": "m01", "title": "M01 · Kıvılcım",
		"intro": [[ME, "Jeneratör karbüratörsüz çalışmaz. Kuzeydoğudaki benzinlikte bir tane olmalı."],
			[ME, "Ana cadde barikatlı. Çarşıdan doğuya, dere yolundan dolaşmam lazım."]],
		"steps": [
			{"type": "goto", "place": "station", "r": 30.0, "text": "Kuzeydoğudaki benzinliğe git (dere yolundan dolaş)"},
			{"type": "loot", "ids": ["st_part", "st_fuel"], "text": "Benzinliği ara: karbüratör parçası ve bidon"},
			{"type": "goto", "place": "garage", "r": 8.0, "text": "Garaja dön"},
			{"type": "interact", "target": "generator", "text": "Karbüratörü jeneratöre tak"},
		],
		"outro": [[ME, "Işıklar yandı. Telsizi de besleyebilirim artık."]],
		"flag": "power",
	},
	{
		"id": "m02", "title": "M02 · Sinyal",
		"intro": [],
		"steps": [
			{"type": "interact", "target": "radio", "text": "Garajdaki telsizi dene"},
			{"type": "goto", "place": "tower", "r": 24.0, "text": "Kuzeybatı tepesindeki radyo kulesine çık"},
			{"type": "loot", "ids": ["tw_part"], "text": "Kule kulübesinde yedek anteni bul"},
			{"type": "interact", "target": "tower_panel", "text": "Anteni kuleye tak (ses çıkaracak)"},
		],
		"outro": [[NILAY, "…biri duyuyor mu? Burası Nilay. Ana caddedeki apartmandayım."],
			[NILAY, "Kardeşim yaralı, ateşi düşmüyor. Çarşıdaki eczanede antibiyotik olmalı."]],
		"flag": "radio",
	},
	{
		"id": "m03", "title": "M03 · Ateş",
		"intro": [],
		"steps": [
			{"type": "goto", "place": "pharmacy", "r": 14.0, "text": "Çarşıdaki eczaneye git"},
			{"type": "loot", "ids": ["ph_meds"], "text": "Eczanenin arka odasında antibiyotik bul"},
			{"type": "goto", "place": "apartment", "r": 10.0, "text": "Apartmana götür (barikatın kuzeyi — dolaşman gerek)"},
			{"type": "interact", "target": "apt_door", "text": "İlacı Nilay'ın kapısına bırak"},
		],
		"outro": [[NILAY, "Aldım. Sağ ol… gerçekten."],
			[NILAY, "Barikattaki haydutlar caddeyi kapatıyor. Orayı açarsan herkes için kestirme olur."]],
		"flag": "survivor",
	},
	{
		"id": "m04", "title": "M04 · Kestirme",
		"intro": [],
		"steps": [
			{"type": "goto", "place": "checkpoint", "r": 40.0, "text": "Ana caddedeki haydut barikatına git"},
			{"type": "clear", "tag": "checkpoint", "text": "Barikattaki haydutları temizle — ya da sürüyü üstlerine çek"},
			{"type": "interact", "target": "gate", "text": "Barikattaki aracı it, yolu aç"},
		],
		"outro": [[NILAY, "Caddeden motor sesi geliyor… sen misin? Yol açık!"],
			[NILAY, "Kuzeydeki tamirhanede babamın alet çantası kalmıştı. Garaja bir tezgâh kurabilirsin."]],
		"flag": "shortcut",
	},
	{
		"id": "m05", "title": "M05 · Tezgâh",
		"intro": [],
		"steps": [
			{"type": "goto", "place": "workshop", "r": 14.0, "text": "Kuzey yolundaki tamirhaneye git"},
			{"type": "loot", "ids": ["ws_tools"], "text": "Tamirhanede alet çantasını bul"},
			{"type": "goto", "place": "garage", "r": 8.0, "text": "Garaja dön"},
			{"type": "interact", "target": "workbench", "text": "Tezgâhı kur"},
		],
		"outro": [[ME, "Tezgâh hazır. Hurda ve bezle motoru donatabilirim."],
			[NILAY, "Rotayı sen açtın. Yarın kuzey otoyolunu konuşalım."]],
		"flag": "workbench",
	},
]

## Mission results plus the bike upgrades fitted at the workbench.
const FLAGS := ["power", "radio", "survivor", "shortcut", "workbench", "saddlebags", "muffler", "suspension"]


static func step_types_valid() -> bool:
	for m in CHAIN:
		for s in m.steps:
			if not s.type in ["goto", "loot", "interact", "clear"]:
				return false
	return true
