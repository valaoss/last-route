extends Node

## Procedurally synthesised one-shot sounds (no external assets) + a positional
## voice pool. Every shot/impact is layered: transient, body, low thump, tail.

const SR := 22050
const VOICES := 24

var bank: Dictionary = {}          # name -> Array[AudioStreamWAV] (variations)
var _voices: Array[AudioStreamPlayer3D] = []
var _flat: AudioStreamPlayer
var _vi := 0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 7331
	for i in VOICES:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = 8.0
		p.max_distance = 140.0
		p.attenuation_filter_cutoff_hz = 5000.0
		p.attenuation_filter_db = -14.0
		add_child(p)
		_voices.append(p)
	_flat = AudioStreamPlayer.new()
	add_child(_flat)
	_build_bank()


func play_at(name: StringName, pos: Vector3, volume_db := 0.0, pitch_var := 0.06) -> void:
	if not bank.has(name):
		return
	var arr: Array = bank[name]
	var p := _voices[_vi]
	_vi = (_vi + 1) % VOICES
	p.stream = arr[_rng.randi() % arr.size()]
	p.global_position = pos
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + _rng.randf_range(-pitch_var, pitch_var)
	p.play()


func play_ui(name: StringName, volume_db := -6.0) -> void:
	if not bank.has(name):
		return
	var arr: Array = bank[name]
	_flat.stream = arr[0]
	_flat.volume_db = volume_db
	_flat.play()


# ------------------------------------------------------------------ bank

func _build_bank() -> void:
	bank[&"pistol"] = [_gunshot(0.004, 0.06, 140.0, 0.5, 0.55, 2600.0), _gunshot(0.004, 0.065, 150.0, 0.52, 0.5, 2400.0)]
	bank[&"carbine"] = [_gunshot(0.003, 0.08, 110.0, 0.75, 0.65, 3200.0), _gunshot(0.003, 0.085, 105.0, 0.8, 0.62, 3000.0)]
	bank[&"shotgun"] = [_gunshot(0.006, 0.16, 70.0, 1.3, 1.0, 1700.0)]
	bank[&"dry_fire"] = [_click(0.03, 3500.0, 0.5)]
	bank[&"reload_out"] = [_click(0.05, 1800.0, 0.6)]
	bank[&"reload_in"] = [_clack()]
	bank[&"pump"] = [_pump()]
	bank[&"swing"] = [_whoosh(0.22), _whoosh(0.26)]
	bank[&"melee_hit"] = [_thud(0.18, 90.0, 0.9), _thud(0.2, 80.0, 1.0)]
	bank[&"flesh_hit"] = [_thud(0.09, 160.0, 0.55), _thud(0.1, 140.0, 0.6)]
	bank[&"hit_tick"] = [_tick(2200.0, 0.04)]
	bank[&"kill_tick"] = [_tick(1300.0, 0.09)]
	bank[&"step"] = [_step(0.0), _step(1.0), _step(2.0)]
	bank[&"groan"] = [_groan(0, 95.0, 1.4), _groan(1, 82.0, 1.8), _groan(2, 110.0, 1.2), _groan(3, 74.0, 2.0)]
	bank[&"screech"] = [_groan(4, 180.0, 0.6, true), _groan(5, 160.0, 0.7, true)]
	bank[&"bike_impact"] = [_thud(0.5, 55.0, 1.0)]
	bank[&"hurt"] = [_thud(0.15, 120.0, 0.5)]
	bank[&"car_alarm"] = [_siren(3.2)]
	bank[&"pickup"] = [_clack()]
	bank[&"lure_beep"] = [_tick(3100.0, 0.14)]


func _wav(data: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	var peak := 0.0001
	for v in data:
		peak = maxf(peak, absf(v))
	var norm := 0.89 / peak
	for i in data.size():
		bytes.encode_s16(i * 2, int(clampf(data[i] * norm, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = SR
	w.stereo = false
	w.data = bytes
	return w


func _noise() -> float:
	return _rng.randf() * 2.0 - 1.0


## transient (s), body decay (s), thump start Hz, tail (s), tail level, body lowpass Hz
func _gunshot(trans: float, body: float, thump_hz: float, tail: float, tail_lvl: float, body_lp: float) -> AudioStreamWAV:
	var n := int(SR * (tail + 0.25))
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var tlp := 0.0
	var ph := 0.0
	var a_body := exp(-1.0 / (SR * body))
	var a_trans := exp(-1.0 / (SR * trans))
	var a_tail := exp(-1.0 / (SR * tail * 0.35))
	var e_body := 1.0
	var e_trans := 1.0
	var e_tail := 0.0
	var k_lp := 1.0 - exp(-TAU * body_lp / SR)
	var k_tail := 1.0 - exp(-TAU * 700.0 / SR)
	for i in n:
		var t := float(i) / SR
		var w := _noise()
		lp += (w - lp) * k_lp
		lp2 += (lp - lp2) * k_lp
		var crack := (w - lp) * e_trans * 1.2
		var bodyv := lp2 * e_body * 2.2
		var f := thump_hz * exp(-t * 18.0) + 38.0
		ph += f / SR
		var thump := sin(TAU * ph) * exp(-t / (body * 1.8)) * 1.1
		e_tail = minf(e_tail + 1.0 / (SR * 0.03), 1.0) * (a_tail if t > 0.03 else 1.0)
		tlp += (w - tlp) * k_tail
		var tailv := tlp * e_tail * tail_lvl * 1.6
		out[i] = crack + bodyv + thump + tailv
		e_body *= a_body
		e_trans *= a_trans
	# slap-back echo off buildings
	var d := int(SR * 0.16)
	for i in range(n - 1, d, -1):
		out[i] += out[i - d] * 0.22
	return _wav(out)


func _click(len: float, hz: float, lvl: float) -> AudioStreamWAV:
	var n := int(SR * len)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		ph += hz / SR
		out[i] = (sin(TAU * ph) * 0.6 + _noise() * 0.4) * exp(-t * 120.0) * lvl
	return _wav(out)


func _clack() -> AudioStreamWAV:
	var n := int(SR * 0.18)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SR
		var a := exp(-t * 90.0) + (exp(-(t - 0.07) * 110.0) * 0.8 if t > 0.07 else 0.0)
		out[i] = (_noise() * 0.7 + sin(TAU * 900.0 * t) * 0.3) * a
	return _wav(out)


func _pump() -> AudioStreamWAV:
	var n := int(SR * 0.42)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var w := _noise()
		lp += (w - lp) * 0.25
		var a := 0.0
		if t < 0.12:
			a = exp(-t * 40.0) * 0.8 + lp * 0.3
		if t > 0.2:
			a += exp(-(t - 0.2) * 55.0)
		out[i] = (lp * 0.8 + w * 0.2) * a + sin(TAU * 420.0 * t) * a * 0.3
	return _wav(out)


func _whoosh(len: float) -> AudioStreamWAV:
	var n := int(SR * len)
	var out := PackedFloat32Array()
	out.resize(n)
	var low := 0.0
	var band := 0.0
	for i in n:
		var t := float(i) / len / SR
		var fc := 400.0 + 1400.0 * sin(PI * t)
		var f := 2.0 * sin(PI * fc / SR)
		var hp := _noise() - low - 0.6 * band
		band += f * hp
		low += f * band
		out[i] = band * sin(PI * t) * sin(PI * t)
	return _wav(out)


func _thud(len: float, hz: float, crunch: float) -> AudioStreamWAV:
	var n := int(SR * len)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		ph += (hz * (1.0 + 1.5 * exp(-t * 40.0))) / SR
		var w := _noise()
		lp += (w - lp) * 0.3
		out[i] = sin(TAU * ph) * exp(-t * 18.0) + lp * crunch * exp(-t * 35.0) * 1.4
	return _wav(out)


## Two-tone car alarm: square-ish whoop alternating every 0.35 s.
func _siren(len: float) -> AudioStreamWAV:
	var n := int(SR * len)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	for i in n:
		var t := float(i) / SR
		var hz := 1250.0 if int(t / 0.35) % 2 == 0 else 880.0
		ph += TAU * hz / SR
		out[i] = clampf(sin(ph) * 2.5, -1.0, 1.0) * 0.6 * minf(t * 40.0, 1.0) * minf((len - t) * 8.0, 1.0)
	return _wav(out)


func _tick(hz: float, len: float) -> AudioStreamWAV:
	var n := int(SR * len)
	var out := PackedFloat32Array()
	out.resize(n)
	for i in n:
		var t := float(i) / SR
		out[i] = sin(TAU * hz * t) * exp(-t * 60.0)
	return _wav(out)


func _step(seed: float) -> AudioStreamWAV:
	var n := int(SR * 0.14)
	var out := PackedFloat32Array()
	out.resize(n)
	var lp := 0.0
	for i in n:
		var t := float(i) / SR
		var w := _noise()
		lp += (w - lp) * (0.18 + seed * 0.04)
		out[i] = lp * exp(-t * 45.0) + w * 0.15 * exp(-t * 120.0)
	return _wav(out)


## Formant-filtered sawtooth with jittered pitch: wet, breathy zombie vocal.
func _groan(seed: int, f0: float, len: float, scream := false) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 100 + seed
	var n := int(SR * len)
	var out := PackedFloat32Array()
	out.resize(n)
	var ph := 0.0
	var f1a := rng.randf_range(500.0, 700.0)
	var f1b := rng.randf_range(300.0, 420.0)
	var f2a := rng.randf_range(1000.0, 1250.0)
	var f2b := rng.randf_range(700.0, 900.0)
	var s1 := [0.0, 0.0]
	var s2 := [0.0, 0.0]
	var jitter := 0.0
	for i in n:
		var t := float(i) / n
		jitter += (rng.randf_range(-1.0, 1.0) - jitter) * 0.002
		var pitch := f0 * (1.0 + 0.25 * sin(PI * t) * (2.0 if scream else 0.6) + jitter * 0.4)
		ph = fmod(ph + pitch / SR, 1.0)
		var saw := ph * 2.0 - 1.0
		var exc := saw * (0.7 + 0.3 * rng.randf()) + rng.randf_range(-1.0, 1.0) * (0.5 if scream else 0.25)
		var f1 := lerpf(f1a, f1b, t)
		var f2 := lerpf(f2a, f2b, t)
		var y1 := _svf_band(s1, exc, f1, 0.18)
		var y2 := _svf_band(s2, exc, f2, 0.2)
		var env := sin(PI * pow(t, 0.6)) * (1.0 - 0.3 * absf(sin(t * 23.0 + seed)))
		out[i] = (y1 + y2 * 0.7) * env
	return _wav(out)


func _svf_band(state: Array, x: float, fc: float, q: float) -> float:
	var f := 2.0 * sin(PI * fc / SR)
	var low: float = state[0]
	var band: float = state[1]
	var high := x - low - q * band
	band += f * high
	low += f * band
	state[0] = low
	state[1] = band
	return band
