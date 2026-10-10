extends Node3D

## Procedural engine + tyre + wind synthesis driven directly by the bike simulation,
## so sound and motion can never drift apart. Uneven V-twin firing → resonant
## exhaust filter; overrun crackle when the throttle snaps shut at high rpm.

const MIX_RATE := 22050.0

var player: AudioStreamPlayer3D
var playback: AudioStreamGeneratorPlayback
var bike: Moto

var _phase := 0.0
var _alt := false
var _interval := 1.0
var _pulse := 0.0
var _pop := 0.0
var _low := 0.0
var _band := 0.0
var _boom := 0.0
var _hiss := 0.0
var _wind := 0.0
var _tyre_lp := 0.0
var _tyre_bp := 0.0
var _skid_phase := 0.0
var _rpm_s := 0.0
var _load_s := 0.0
var _prev_load := 0.0
var _overrun := 0.0
var _crunch := 0.0
var _gain := 0.0
var last_fill_usec := 0


func _ready() -> void:
	bike = get_parent() as Moto
	player = AudioStreamPlayer3D.new()
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.12
	player.stream = gen
	player.unit_size = 7.0
	player.max_db = 3.0
	player.volume_db = -4.0
	player.attenuation_filter_cutoff_hz = 6000.0
	player.attenuation_filter_db = -18.0
	player.position = Vector3(0.2, 0.6, 0.3)
	add_child(player)
	player.play()
	playback = player.get_stream_playback()


func _process(_dt: float) -> void:
	if playback == null:
		return
	var t0 := Time.get_ticks_usec()
	_fill()
	last_fill_usec = Time.get_ticks_usec() - t0


func _fill() -> void:
	var n := playback.get_frames_available()
	if n <= 0:
		return
	var tun := bike.tuning
	var running := bike.rpm > 300.0
	var target_gain := 1.0 if running else 0.0
	var rpm_target := maxf(bike.rpm, 1.0)
	var load_target := bike.engine_load
	var speed := absf(bike.v)
	var on_ground := bike.is_on_floor()
	var slide := bike.slide_amount if on_ground else 0.0
	var tone := bike.surface.tyre_tone
	var rpm_n := clampf((bike.rpm - tun.idle_rpm) / (tun.redline_rpm - tun.idle_rpm), 0.0, 1.0)
	# overrun: throttle closed fast at high rpm → crackle window
	if _prev_load - load_target > 0.04 and rpm_n > 0.45:
		_overrun = 0.9
	_prev_load = load_target

	var buf := PackedVector2Array()
	buf.resize(n)
	var inv_sr := 1.0 / MIX_RATE
	var wind_amp := clampf(speed / 26.0, 0.0, 1.0)
	wind_amp *= wind_amp * 0.22
	var tyre_amp := clampf(speed / 18.0, 0.0, 1.0) * (0.05 + 0.1 * tone) if on_ground else 0.0
	var skid_amp := slide * clampf(speed / 10.0, 0.0, 1.0) * (1.0 - tone) * 0.16
	var crunch_rate := tone * clampf(speed / 12.0, 0.0, 1.0) * 0.004
	var ov_decay := pow(0.0001, inv_sr / 0.6)

	for i in n:
		_rpm_s += (rpm_target - _rpm_s) * 0.0015
		_load_s += (load_target - _load_s) * 0.002
		_gain += (target_gain - _gain) * 0.0008
		var fire_hz := _rpm_s / 60.0
		_phase += fire_hz * inv_sr * _interval
		if _phase >= 1.0:
			_phase -= 1.0
			_alt = not _alt
			_interval = 0.82 if _alt else 1.22   # 270°/450° V-twin rhythm
			_pulse = 1.0 if _alt else 0.8
			if _overrun > 0.05 and randf() < 0.22 * _overrun:
				_pop = 1.0
		var decay := 1.0 - (55.0 + fire_hz * 0.9) * inv_sr
		_pulse *= decay
		_pop *= 0.9965
		_overrun *= ov_decay
		var noise := randf() * 2.0 - 1.0
		var exc := _pulse * (0.75 + 0.25 * noise) + _pop * noise * 0.9

		# resonant exhaust body: cutoff and drive rise with load and rpm
		var fc := 140.0 + 900.0 * _load_s * (0.4 + rpm_n) + 260.0 * rpm_n
		var f := 2.0 * sin(PI * fc * inv_sr)
		var q := 0.55 - 0.25 * _load_s
		var high := exc - _low - q * _band
		_band += f * high
		_low += f * _band
		_boom += (_low - _boom) * 0.03
		var engine := (_low * (0.55 + 0.6 * _load_s) + _boom * 0.9) * _gain

		_hiss += (noise - _hiss) * 0.08
		var intake := _hiss * _load_s * rpm_n * 0.06 * _gain

		_wind += (noise - _wind) * 0.02
		var wind := _wind * wind_amp * 3.0

		_tyre_lp += (noise - _tyre_lp) * (0.12 + 0.25 * tone)
		_tyre_bp += (_tyre_lp - _tyre_bp) * 0.05
		var tyre := (_tyre_lp - _tyre_bp) * tyre_amp
		if randf() < crunch_rate:
			_crunch = 1.0
		_crunch *= 0.985
		tyre += _crunch * noise * tone * 0.25

		_skid_phase += (820.0 + 60.0 * sin(_skid_phase * 0.0021)) * inv_sr
		var skid := sin(TAU * _skid_phase) * skid_amp * (0.7 + 0.3 * noise)

		var x := engine + intake + wind + tyre + skid
		x = x / (1.0 + absf(x))
		buf[i] = Vector2(x, x)
	playback.push_buffer(buf)
