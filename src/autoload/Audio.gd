extends Node
## 音效对象池 + BGM 交叉淡入。音频设备异常时静默降级，绝不影响玩法。

const DIR := "res://assets/audio/"
const VOICES := 14
const THROTTLE := 0.045

var _pool: Array = []
var _next := 0
var _bgm_a: AudioStreamPlayer
var _bgm_b: AudioStreamPlayer
var _bgm_drive: AudioStreamPlayer
var _bgm_cur: AudioStreamPlayer = null
var _bgm_layered := false
var _intensity := 0.0
var _intensity_t := 0.0
var _bgm_tween: Tween = null
var _active_bgm := ""
var _cache: Dictionary = {}
var _ok := true
var _last_play: Dictionary = {}
var _duck := 0.0
var _bgm_scale := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if DisplayServer.get_name() == "headless":
		_ok = false
	for i in VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_pool.append(p)
	_bgm_a = AudioStreamPlayer.new()
	_bgm_b = AudioStreamPlayer.new()
	_bgm_drive = AudioStreamPlayer.new()
	_bgm_a.volume_db = -80.0
	_bgm_b.volume_db = -80.0
	_bgm_drive.volume_db = -80.0
	add_child(_bgm_a)
	add_child(_bgm_b)
	add_child(_bgm_drive)
	_apply_volumes()


func _apply_volumes() -> void:
	var m := float(Save.setting("vol_master", 0.75))
	var s := float(Save.setting("vol_sfx", 0.80))
	for p in _pool:
		p.volume_db = _db(m * s)
	_apply_bgm_volumes()


func refresh_volumes() -> void:
	_apply_volumes()


func _db(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return linear_to_db(clampf(linear, 0.0, 1.0))


func _stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := DIR + name + ".wav"
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamWAV and name.begins_with("bgm"):
		# 只有 BGM 需要循环。音效如果被设成循环，会永远占住声音通道变成噪音墙。
		# 注意：Godot 默认用 QOA 压缩导入 wav，data.size() 不是采样帧数，
		# 必须用 get_length()*mix_rate 才能得到正确的循环终点。
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * float(w.mix_rate))
	elif s is AudioStreamWAV:
		(s as AudioStreamWAV).loop_mode = AudioStreamWAV.LOOP_DISABLED
	_cache[name] = s
	return s


func play(name: String, pitch: float = 1.0, pitch_var: float = 0.06, vol: float = 1.0) -> void:
	if not _ok:
		return
	# 同类音效节流：连射时不再糊成噪声墙
	var now := Time.get_ticks_msec() / 1000.0
	var last := float(_last_play.get(name, -10.0))
	if now - last < THROTTLE:
		return
	_last_play[name] = now
	var s := _stream(name)
	if s == null:
		return
	var p: AudioStreamPlayer = _pool[_next]
	_next = (_next + 1) % VOICES
	p.stream = s
	p.pitch_scale = clampf(pitch + randf_range(-pitch_var, pitch_var), 0.35, 2.5)
	var m := float(Save.setting("vol_master", 0.75)) * float(Save.setting("vol_sfx", 0.80))
	p.volume_db = _db(m * vol)
	p.play()


## 重要音效出现时把 BGM 压下去，避免一起糊成噪音
func duck(strength: float = 0.45, dur: float = 0.8) -> void:
	if not _ok:
		return
	_duck = maxf(_duck, strength)
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(_set_bgm_scale, 1.0 - _duck, 1.0, dur + 0.35)


func _apply_bgm_volumes() -> void:
	var m := float(Save.setting("vol_master", 0.75)) 		* float(Save.setting("vol_bgm", 0.42)) * _bgm_scale
	if _bgm_cur != null:
		_bgm_cur.volume_db = _db(m)
	if _bgm_drive != null and _bgm_drive.playing:
		var dv: float = m * (_intensity if _bgm_layered else 0.0)
		_bgm_drive.volume_db = _db(dv) if dv > 0.004 else -80.0


func _set_bgm_scale(v: float) -> void:
	_bgm_scale = clampf(v, 0.0, 1.0)
	_apply_bgm_volumes()


## 战斗强度 0~1：驱动"战斗层"的音量。开打时推进得快，打完退得慢。
func set_intensity(v: float) -> void:
	_intensity_t = clampf(v, 0.0, 1.0)


func _process(delta: float) -> void:
	# 插值始终运行（headless 下也能观测），只有音量应用需要音频可用
	var spd: float = 2.4 if _intensity_t > _intensity else 0.30
	_intensity = move_toward(_intensity, _intensity_t, spd * delta)
	if _bgm_layered:
		_apply_bgm_volumes()


## 分层 BGM：base 一直播放，drive 按战斗强度淡入。
## 两条音轨必须**同一帧启动**才能保持同步（由生成端保证等长同速）。
func bgm_layered(base_name: String, drive_name: String, fade: float = 1.0) -> void:
	if not _ok:
		return
	if base_name == _active_bgm and _bgm_layered and _bgm_a.playing:
		return
	var sb := _stream(base_name)
	var sd := _stream(drive_name)
	if sb == null or sd == null:
		push_warning("layered bgm missing: " + base_name)
		return
	_active_bgm = base_name
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = null
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_method(_set_bgm_scale, _bgm_scale, 0.0, fade * 0.55)
	tw.tween_callback(func() -> void:
		_bgm_a.stop()
		_bgm_b.stop()
		_bgm_drive.stop()
		_bgm_a.stream = sb
		_bgm_drive.stream = sd
		_bgm_cur = _bgm_a
		_bgm_layered = true
		_bgm_scale = 0.0
		_intensity = 0.0
		_intensity_t = 0.0
		_bgm_a.play()
		_bgm_drive.play()
		_apply_bgm_volumes())
	tw.tween_method(_set_bgm_scale, 0.0, 1.0, fade * 0.55)
	_bgm_tween = tw


func bgm(name: String, fade: float = 1.2) -> void:
	if not _ok:
		return
	# 已经在放同一首就什么都不做
	if name == _active_bgm and _bgm_cur != null and _bgm_cur.playing:
		return
	var s := _stream(name)
	if s == null:
		push_warning("bgm stream missing: " + name)
		return
	_active_bgm = name
	# 关键：先杀掉上一次的交叉淡入，否则它的回调会把刚启动的新曲一起 stop 掉
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	_bgm_tween = null
	var old := _bgm_cur
	var to := _bgm_b if old == _bgm_a else _bgm_a
	_bgm_cur = to
	_bgm_scale = 1.0
	_bgm_layered = false
	_intensity_t = 0.0
	var m := float(Save.setting("vol_master", 0.75)) * float(Save.setting("vol_bgm", 0.42))
	_bgm_drive.stop()
	to.stream = s
	to.volume_db = -80.0
	to.play()
	var tw := create_tween().set_parallel(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(to, "volume_db", _db(m), fade)
	if old != null and old != to:
		tw.tween_property(old, "volume_db", -80.0, fade)
	_bgm_tween = tw
	var old_ref: AudioStreamPlayer = old
	tw.chain().tween_callback(func() -> void:
		# 只有当它确实还是"被替换掉的那一路"时才停
		if old_ref != null and old_ref != _bgm_cur and old_ref.playing:
			old_ref.stop())


func stop_bgm(fade: float = 0.8) -> void:
	_active_bgm = ""
	if _bgm_tween != null and _bgm_tween.is_valid():
		_bgm_tween.kill()
	var tw := create_tween().set_parallel(true)
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	if _bgm_cur != null:
		tw.tween_property(_bgm_cur, "volume_db", -80.0, fade)
	if _bgm_drive != null and _bgm_drive.playing:
		tw.tween_property(_bgm_drive, "volume_db", -80.0, fade)
	_bgm_cur = null
	_bgm_layered = false
	_intensity_t = 0.0
	_intensity = 0.0


func play_ui() -> void:
	play("sfx_ui_click", 1.0, 0.03, 0.5)
