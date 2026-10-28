extends Node
## 永久存档：**3 个存档槽** + 全局设置。原子写入 + 损坏降级 + 旧档自动迁移。
##
## 关键设计：`data` 始终指向**当前槽位**的进度字典（并把全局 settings 挂在里面），
## 因此其余所有代码里的 Save.data["stats"] / Save.setting() 等用法完全不用改。

const PATH := "user://save.json"
const TMP := "user://save.tmp"
const BACKUP := "user://save.bak.json"
const VERSION := 5
const SLOT_COUNT := 3

var data: Dictionary = {}        ## 当前槽位进度（含 settings 引用）
var settings: Dictionary = {}    ## 全局设置，所有槽共享
var slots: Array = []            ## 每个槽的进度字典
var active_slot := 0
var readonly := false


func _ready() -> void:
	load_game()


func default_settings() -> Dictionary:
	return {
		"vol_master": 0.75, "vol_bgm": 0.42, "vol_sfx": 0.80,
		"autofire": true, "shake": true, "fullscreen": false, "show_fps": false,
		"difficulty": 1,
	}


func empty_slot() -> Dictionary:
	return {
		"used": false, "gears": 0, "workshop": {}, "unlocked": [0],
		"endless_unlocked": false, "best": {},
		"stats": {"runs": 0, "kills": 0, "bosses": 0, "playtime": 0.0},
	}


func fresh_slot() -> Dictionary:
	var s := empty_slot()
	s["used"] = true
	return s


## 完整根结构（兼容旧调用）
func defaults() -> Dictionary:
	var sl: Array = []
	for i in SLOT_COUNT:
		sl.append(fresh_slot() if i == 0 else empty_slot())
	return {"version": VERSION, "active_slot": 0,
		"settings": default_settings(), "slots": sl}


func load_game() -> void:
	settings = default_settings()
	slots = []
	for i in SLOT_COUNT:
		slots.append(empty_slot())
	active_slot = 0
	if FileAccess.file_exists(PATH):
		var f := FileAccess.open(PATH, FileAccess.READ)
		if f != null:
			var raw := f.get_as_text()
			f.close()
			var parsed: Variant = JSON.parse_string(raw)
			if typeof(parsed) == TYPE_DICTIONARY and parsed.has("version"):
				_ingest(parsed)
			else:
				# 损坏的存档：备份后重建
				var b := FileAccess.open(BACKUP, FileAccess.WRITE)
				if b != null:
					b.store_string(raw)
					b.close()
				push_warning("save corrupted, backed up and reset")
				slots[0] = fresh_slot()
	if not bool((slots[0] as Dictionary).get("used", false)):
		slots[0] = fresh_slot()
	# 顺序很关键：必须先 _bind() 让 data 指向当前槽位，
	# 否则 _normalize() 作用在空字典上、等于没做 —— 结果是解锁列表保持
	# JSON 里的 float（[0.0,1.0,2.0]），而 Array.has(0) 比对 int 会失败，
	# 选关界面就全部显示"未解锁"。
	_bind()
	_normalize()
	_prune_empty_used()
	save_game()


func _ingest(p: Dictionary) -> void:
	var ver := int(p.get("version", 1))
	if p.has("settings") and typeof(p["settings"]) == TYPE_DICTIONARY:
		_merge(settings, p["settings"])
	# 旧版本的音量迁移（以前写在 _normalize 里，但那时"版本号"在 data 根上，
	# 现在版本号在文件根、data 指向槽位，所以必须挪到这里）
	if ver < 3:
		settings["vol_master"] = 0.75
		settings["vol_bgm"] = 0.30
		settings["vol_sfx"] = 0.80
	if ver < 4:
		if float(settings.get("vol_bgm", 0.42)) < 0.42:
			settings["vol_bgm"] = 0.42
	if ver < 5 or not p.has("slots"):
		# v4 及更早是单档结构：整份搬进 0 号槽
		var s := fresh_slot()
		for k in ["gears", "workshop", "unlocked", "endless_unlocked", "best", "stats"]:
			if p.has(k):
				s[k] = p[k]
		slots[0] = _merge(empty_slot(), s)
		slots[0]["used"] = true
		active_slot = 0
		return
	var sl: Array = p.get("slots", [])
	for i in SLOT_COUNT:
		if i < sl.size() and typeof(sl[i]) == TYPE_DICTIONARY:
			slots[i] = _merge(empty_slot(), sl[i])
	active_slot = clampi(int(p.get("active_slot", 0)), 0, SLOT_COUNT - 1)


## 清掉"使用中但完全没有进度"的残留槽位。
## 旧版「重开」用的是 fresh_slot()，会把槽位标成 used=true 但进度全 0，
## 界面上仍显示「进入 / 重开」，玩家会以为没清干净。这里让它回到「空」。
func _prune_empty_used() -> void:
	for s in slots:
		var d: Dictionary = s
		if not bool(d.get("used", false)):
			continue
		if int(d.get("gears", 0)) > 0:
			continue
		if int((d.get("stats", {}) as Dictionary).get("runs", 0)) > 0:
			continue
		if not (d.get("workshop", {}) as Dictionary).is_empty():
			continue
		if not (d.get("best", {}) as Dictionary).is_empty():
			continue
		if (d.get("unlocked", []) as Array).size() > 1:
			continue
		d["used"] = false


## 所有槽位都要归一化（JSON 里数字都是 float）
func _normalize() -> void:
	for s in slots:
		_normalize_slot(s)


## 统一转成 int，避免 Array.has() / 字典取值时 float 与 int 比对失败
func _normalize_slot(d: Dictionary) -> void:
	var u: Array = d.get("unlocked", [0])
	var nu: Array = []
	for v in u:
		var iv := int(v)
		if not nu.has(iv):
			nu.append(iv)
	if nu.is_empty():
		nu = [0]
	nu.sort()
	d["unlocked"] = nu
	var ws: Dictionary = d.get("workshop", {})
	var nw := {}
	for k in ws.keys():
		nw[String(k)] = int(ws[k])
	d["workshop"] = nw
	d["gears"] = int(d.get("gears", 0))
	var st: Dictionary = d.get("stats", {})
	var nst := {}
	for k in st.keys():
		nst[String(k)] = st[k]
	for k in ["runs", "kills", "bosses"]:
		nst[k] = int(nst.get(k, 0))
	d["stats"] = nst


func _merge(dst: Dictionary, src: Dictionary) -> Dictionary:
	for k in src.keys():
		if dst.has(k) and typeof(dst[k]) == TYPE_DICTIONARY and typeof(src[k]) == TYPE_DICTIONARY:
			_merge(dst[k], src[k])
		else:
			dst[k] = src[k]
	return dst


## 让 data 指向当前槽位；settings 挂进去，这样 data["settings"] 照常可用
func _bind() -> void:
	data = slots[active_slot]
	data["settings"] = settings


func save_game() -> void:
	if readonly:
		return
	var s: Dictionary = slots[active_slot]
	for k in data.keys():
		if k != "settings":
			s[k] = data[k]
	s["used"] = true
	# 序列化前把 settings 从槽位里剥掉，避免每份进度都重复存一份设置
	var out_slots: Array = []
	for i in SLOT_COUNT:
		var src: Dictionary = slots[i]
		var cp := {}
		for k in src.keys():
			if k != "settings":
				cp[k] = src[k]
		out_slots.append(cp)
	var root := {
		"version": VERSION,
		"active_slot": active_slot,
		"settings": settings,
		"slots": out_slots,
	}
	var f := FileAccess.open(TMP, FileAccess.WRITE)
	if f == null:
		push_warning("cannot open save tmp")
		return
	f.store_string(JSON.stringify(root, "  "))
	f.close()
	var abs_tmp := ProjectSettings.globalize_path(TMP)
	var abs_dst := ProjectSettings.globalize_path(PATH)
	var d := DirAccess.open("user://")
	if d != null:
		d.remove("save.json")
	DirAccess.rename_absolute(abs_tmp, abs_dst)


# ---------------------------------------------------------------- 槽位管理
func slot_summary(i: int) -> Dictionary:
	i = clampi(i, 0, SLOT_COUNT - 1)
	var s: Dictionary = slots[i]
	var st: Dictionary = s.get("stats", {})
	var ul: Array = s.get("unlocked", [])
	var ws: Dictionary = s.get("workshop", {})
	var ws_total := 0
	for k in ws.keys():
		ws_total += int(ws[k])
	return {
		"index": i, "used": bool(s.get("used", false)), "active": i == active_slot,
		"gears": int(s.get("gears", 0)), "stages": ul.size(),
		"runs": int(st.get("runs", 0)), "kills": int(st.get("kills", 0)),
		"bosses": int(st.get("bosses", 0)), "workshop_total": ws_total,
	}


## 切到某个槽（空槽会自动开新档）
func switch_slot(i: int) -> void:
	if i < 0 or i >= SLOT_COUNT or i == active_slot:
		return
	if not bool((slots[i] as Dictionary).get("used", false)):
		slots[i] = fresh_slot()
	active_slot = i
	_bind()
	save_game()
	Bus.gears_changed.emit(gears())


## 清空该槽进度（**保留全局设置**）。
## 清空后槽位回到"空"状态——而不是"用过但进度为 0"，
## 否则界面仍会显示「进入 / 重开」，玩家会以为没清干净。
func reset_slot(i: int) -> void:
	if i < 0 or i >= SLOT_COUNT:
		return
	slots[i] = empty_slot()
	if i == active_slot:
		# 当前槽被清空：若还有别的已用槽就切过去，否则保持一个空的当前槽
		var other := -1
		for k in SLOT_COUNT:
			if k != i and bool((slots[k] as Dictionary).get("used", false)):
				other = k
				break
		if other >= 0:
			active_slot = other
		_bind()
	save_game()
	Bus.gears_changed.emit(gears())


## 在指定槽位开一份全新进度并切过去（空槽专用入口）
func start_new_game(i: int) -> void:
	if i < 0 or i >= SLOT_COUNT:
		return
	slots[i] = fresh_slot()
	active_slot = i
	_bind()
	save_game()
	Bus.gears_changed.emit(gears())


func erase_slot(i: int) -> void:
	if i < 0 or i >= SLOT_COUNT:
		return
	slots[i] = empty_slot()
	if i == active_slot:
		_bind()
	save_game()
	Bus.gears_changed.emit(gears())


func reset_all_progress() -> void:
	for i in SLOT_COUNT:
		slots[i] = fresh_slot() if i == 0 else empty_slot()
	active_slot = 0
	_bind()
	save_game()
	Bus.gears_changed.emit(gears())


# ---------------------------------------------------------------- 设置 / 进度
func setting(key: String, fallback: Variant = null) -> Variant:
	return data["settings"].get(key, fallback)


func set_setting(key: String, value: Variant) -> void:
	data["settings"][key] = value
	save_game()


func gears() -> int:
	return int(data["gears"])


func add_gears(n: int) -> void:
	data["gears"] = max(0, int(data["gears"]) + n)
	Bus.gears_changed.emit(int(data["gears"]))
	save_game()


func workshop_level(id: String) -> int:
	return int(data["workshop"].get(id, 0))


func set_workshop_level(id: String, lv: int) -> void:
	data["workshop"][id] = lv
	save_game()


func unlock_stage(idx: int) -> void:
	var u: Array = data["unlocked"]
	if not u.has(idx):
		u.append(idx)
		u.sort()
		data["unlocked"] = u
		save_game()


func is_unlocked(idx: int) -> bool:
	return data["unlocked"].has(idx)


func record_best(stage_idx: int, entry: Dictionary) -> void:
	var key := "endless" if stage_idx < 0 else "stage%d" % stage_idx
	var cur: Dictionary = data["best"].get(key, {})
	if cur.is_empty() or int(entry.get("score", 0)) > int(cur.get("score", 0)):
		data["best"][key] = entry
	save_game()


func best(stage_idx: int) -> Dictionary:
	var key := "endless" if stage_idx < 0 else "stage%d" % stage_idx
	return data["best"].get(key, {})
