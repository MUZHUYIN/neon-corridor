class_name MenuRoot
extends Control
## 主菜单 / 选关 / 工坊 / 设置。全部用代码搭 UI，风格统一走 UI 工厂。

signal start_run(stage_idx: int, endless: bool)

var page := "main"
var content: VBoxContainer
var _bar_label: Label
var _footer: Control = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	UI.full_rect(self)
	var bg := ColorRect.new()
	bg.color = UI.C_BG
	add_child(bg)
	UI.full_rect(bg)
	var glow := ColorRect.new()
	glow.color = Color(0.06, 0.10, 0.18, 0.9)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(glow)
	UI.pin(glow, 0, 0, 640, 76)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	add_child(head)
	UI.pin(head, 18, 12, 604, 28)
	var title := UI.lbl("霓虹回廊", 20, UI.C_ACCENT)
	head.add_child(title)
	var sub := UI.lbl("NEON CORRIDOR", 10, UI.C_DIM)
	sub.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	head.add_child(sub)
	head.add_child(UI.hspace(20))
	var fill := Control.new()
	fill.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(fill)
	var gj := HBoxContainer.new()
	gj.add_theme_constant_override("separation", 5)
	gj.add_child(UI.icon("icon_m_gear", 1.3))
	_bar_label = UI.lbl("0", 14, UI.C_YELLOW)
	gj.add_child(_bar_label)
	head.add_child(gj)

	content = VBoxContainer.new()
	add_child(content)
	content.anchor_left = 0.0
	content.anchor_top = 0.0
	content.anchor_right = 1.0
	content.anchor_bottom = 1.0
	content.offset_left = 26.0
	content.offset_top = 72.0
	content.offset_right = -26.0
	content.offset_bottom = -14.0
	content.add_theme_constant_override("separation", 8)

	Bus.gears_changed.connect(func(_n: int) -> void: _refresh_bar())
	_refresh_bar()
	_rebuild()


func _refresh_bar() -> void:
	if _bar_label != null:
		_bar_label.text = str(Save.gears())


func _clear() -> void:
	for c in content.get_children():
		c.queue_free()
	if _footer != null and is_instance_valid(_footer):
		_footer.queue_free()
	_footer = null


## 底部固定栏：统计信息 + 退出游戏（之前作为 VBox 子项被挤出了屏幕）
func _add_footer(info: String) -> void:
	_footer = Control.new()
	# 不吃鼠标事件：否则这条 640x38 的 Control 会挡住任何落在 y314~352 的按钮
	# （内部的"退出游戏"按钮不受影响，子节点照样能收到点击）
	_footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_footer)
	UI.pin(_footer, 0, 314, 640, 38)
	var sep := ColorRect.new()
	sep.color = Color(0.18, 0.20, 0.30, 0.9)
	UI.pin(sep, 20, 0, 600, 1)
	_footer.add_child(sep)
	var l := UI.lbl(info, 11, UI.C_DIM)
	UI.pin(l, 22, 10, 400, 20)
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_footer.add_child(l)
	var b := UI.btn("退出游戏", 12, 116)
	UI.pin_ne(b, 22, 5, 116, 28)
	_footer.add_child(b)
	b.pressed.connect(func() -> void:
		Audio.play_ui()
		Game.quit())


func _rebuild() -> void:
	_clear()
	match page:
		"main":
			_page_main()
		"stages":
			_page_stages()
		"workshop":
			_page_workshop()
		"save":
			_page_save()
		"settings":
			_page_settings()
	_refresh_bar()


func _page_main() -> void:
	# 注意：VBox 本身已有 8px 间距，这里再插 vspace 会让实际间距翻倍，
	# 4 个按钮时就会把最后一项挤出屏幕（曾经把"设置"挤到屏幕外并与页脚重叠）
	var t := UI.lbl("在最深处的反应堆里，活下来。", 13, UI.C_TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(t)
	content.add_child(UI.vspace(6))
	var rows := [["开始游戏", "stages"], ["工坊（永久强化）", "workshop"],
		["存档", "save"], ["设置", "settings"]]
	for r in rows:
		var b := UI.btn(String(r[0]), 15, 260)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var target := String(r[1])
		b.pressed.connect(func() -> void:
			Audio.play_ui()
			page = target
			_rebuild())
		content.add_child(b)
	var s: Dictionary = Save.slot_summary(Save.active_slot)
	_add_footer("槽位 %d　齿轮 %d　解锁 %d 关　击杀 %d　通关 %d　游玩 %d 次　（自动保存）" % [
		int(s["index"]) + 1, int(s["gears"]), int(s["stages"]),
		int(s["kills"]), int(s["bosses"]), int(s["runs"])])


func _page_stages() -> void:
	content.add_child(_header("选择关卡", "main"))
	# ---- 难度选择 ----
	var drow := HBoxContainer.new()
	drow.add_theme_constant_override("separation", 6)
	drow.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var cur_d := int(Save.setting("difficulty", 1))
	var dl := UI.lbl("难度", 12, UI.C_DIM)
	dl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drow.add_child(dl)
	for i in DB.DIFFICULTY.size():
		var d: Dictionary = DB.DIFFICULTY[i]
		var sel := i == cur_d
		var b := UI.btn(("▶ " if sel else "") + String(d["name"]), 12, 92)
		if sel:
			b.add_theme_color_override("font_color", UI.C_ACCENT)
		b.pressed.connect(func() -> void:
			Audio.play_ui()
			Save.set_setting("difficulty", i)
			_rebuild())
		drow.add_child(b)
	content.add_child(drow)
	var dd := UI.lbl(String(DB.DIFFICULTY[cur_d]["desc"]), 10, UI.C_DIM)
	dd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(dd)
	content.add_child(UI.vspace(4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	content.add_child(row)
	var unlocked: Array = Save.data.get("unlocked", [0])
	var all_clear := unlocked.has(1) and unlocked.has(2) and unlocked.has(3)
	for i in DB.STAGES.size():
		var d: Dictionary = DB.STAGES[i]
		var open := unlocked.has(i)
		var c := UI.card(146, 168, open)
		row.add_child(c["root"])
		var box: VBoxContainer = c["box"]
		var nm := UI.lbl("%d. %s" % [i + 1, d["name"]], 13, UI.C_ACCENT if open else UI.C_DIM)
		box.add_child(nm)
		var desc := UI.lbl(String(d["desc"]), 10, UI.C_DIM)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size = Vector2(126, 44)
		box.add_child(desc)
		var best: Dictionary = Save.best(i)
		var rec := "—"
		if not best.is_empty():
			rec = "%d 击杀 / Lv.%d" % [int(best.get("kills", 0)), int(best.get("level", 1))]
		box.add_child(UI.lbl("最佳：" + rec, 10, UI.C_YELLOW))
		box.add_child(UI.vspace(6))
		var b := UI.btn("进入" if open else "未解锁", 12)
		b.disabled = not open
		if open:
			b.pressed.connect(func() -> void:
				Audio.play_ui()
				start_run.emit(i, false))
		box.add_child(b)
	# 无尽模式
	var ec := UI.card(146, 168, all_clear)
	ec["root"].size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(ec["root"])
	var eb: VBoxContainer = ec["box"]
	eb.add_child(UI.lbl("∞  无尽回廊", 13, UI.C_PINK if all_clear else UI.C_DIM))
	var ed := UI.lbl("通关三关后解锁。敌人永无止境，只看你能撑多久。", 10, UI.C_DIM)
	ed.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ed.custom_minimum_size = Vector2(126, 44)
	eb.add_child(ed)
	var ebest: Dictionary = Save.best(-1)
	eb.add_child(UI.lbl("最佳：" + ("—" if ebest.is_empty() else "%d 击杀" % int(ebest.get("kills", 0))), 10, UI.C_YELLOW))
	eb.add_child(UI.vspace(6))
	var ebtn := UI.btn("进入" if all_clear else "未解锁", 12)
	ebtn.disabled = not all_clear
	if all_clear:
		ebtn.pressed.connect(func() -> void:
			Audio.play_ui()
			start_run.emit(0, true))
	eb.add_child(ebtn)


func _page_workshop() -> void:
	content.add_child(_header("工坊 - 用齿轮换永久强化", "main"))
	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(cols)
	var col_boxes: Array = []
	for c in 2:
		var col := VBoxContainer.new()
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 6)
		cols.add_child(col)
		col_boxes.append(col)
	for i in DB.WORKSHOP.size():
		var item: Dictionary = DB.WORKSHOP[i]
		var id := String(item["id"])
		var lv := Save.workshop_level(id)
		var costs: Array = item["costs"]
		var rowc := UI.card(286, 58, lv > 0)
		rowc["root"].size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_boxes[i % 2].add_child(rowc["root"])
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		rowc["box"].add_child(hb)
		hb.add_child(UI.icon(String(item["icon"]), 1.4))
		var txt := VBoxContainer.new()
		txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		txt.add_theme_constant_override("separation", 1)
		hb.add_child(txt)
		txt.add_child(UI.lbl(String(item["name"]), 11, UI.C_TEXT))
		var sub := UI.lbl("Lv.%d/5　%s" % [lv, item["desc"]], 9, UI.C_DIM)
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		txt.add_child(sub)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 2)
		for k in 5:
			var pip := ColorRect.new()
			pip.custom_minimum_size = Vector2(9, 6)
			pip.color = UI.C_ACCENT if k < lv else Color(0.16, 0.16, 0.26)
			pips.add_child(pip)
		txt.add_child(pips)
		var buy := UI.btn("满级" if lv >= 5 else "%d 齿轮" % int(costs[lv]), 10, 74)
		if lv >= 5:
			buy.disabled = true
		else:
			buy.disabled = Save.gears() < int(costs[lv])
			buy.pressed.connect(func() -> void:
				Audio.play_ui()
				var cur := Save.workshop_level(id)
				if cur < 5:
					var cost2 := int(costs[cur])
					if Save.gears() >= cost2:
						Save.add_gears(-cost2)
						Save.set_workshop_level(id, cur + 1)
						_rebuild())
		hb.add_child(buy)


func _page_save() -> void:
	content.add_child(_header("存档", "main"))
	# 说明与"清空全部"放同一行，否则 VBox 的间距会把底部按钮挤出可视区
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	content.add_child(top)
	var tip := UI.lbl("每个槽位是一份独立进度；设置（音量 / 难度 / 全屏）为全局共享，重开不会动它。", 10, UI.C_DIM)
	tip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	top.add_child(tip)
	var allb := UI.btn("清空全部", 10, 90)
	allb.pressed.connect(func() -> void:
		Audio.play_ui()
		_ask_confirm("清空全部存档？",
			"三个槽位的进度（齿轮 / 工坊 / 解锁 / 记录 / 统计）都会被清空，设置保留。此操作不可撤销。", true,
			func() -> void:
				Save.reset_all_progress()
				_rebuild()))
	top.add_child(allb)
	for i in Save.SLOT_COUNT:
		_build_slot_row(i)


func _build_slot_row(i: int) -> void:
	var s: Dictionary = Save.slot_summary(i)
	var used := bool(s["used"])
	var active := bool(s["active"])
	var c := UI.card(560, 58, active)
	content.add_child(c["root"])
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	c["box"].add_child(hb)

	var title_col := VBoxContainer.new()
	title_col.custom_minimum_size = Vector2(104, 0)
	title_col.add_theme_constant_override("separation", 1)
	hb.add_child(title_col)
	title_col.add_child(UI.lbl("槽位 %d%s" % [i + 1, "　◀ 当前" if active else ""], 12,
		UI.C_ACCENT if active else UI.C_TEXT))
	title_col.add_child(UI.lbl("使用中" if used else "空", 9, UI.C_DIM))

	var info := UI.lbl("", 10, UI.C_DIM)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if used:
		info.text = "齿轮 %d　解锁 %d 关　工坊 %d 级\n%d 局 · %d 击杀 · %d Boss" % [
			int(s["gears"]), int(s["stages"]), int(s["workshop_total"]),
			int(s["runs"]), int(s["kills"]), int(s["bosses"])]
	elif active:
		info.text = "空槽位（当前）—— 点「开始新游戏」在这里开一份全新进度"
	else:
		info.text = "空槽位 —— 可以在这里开一份全新进度"
	hb.add_child(info)

	if not used:
		# 空槽只有一个动作：在这里开新进度（无论它是不是当前槽）
		var nb := UI.btn("开始新游戏", 10, 96)
		nb.pressed.connect(func() -> void:
			Audio.play_ui()
			Save.start_new_game(i)
			_rebuild())
		hb.add_child(nb)
	else:
		if not active:
			var enter := UI.btn("进入", 10, 60)
			enter.pressed.connect(func() -> void:
				Audio.play_ui()
				Save.switch_slot(i)
				_rebuild())
			hb.add_child(enter)
		var ng := UI.btn("重开", 10, 60)
		ng.pressed.connect(func() -> void:
			Audio.play_ui()
			_ask_confirm("清空槽位 %d？" % [i + 1],
				"该槽位的进度会被清空（齿轮 / 工坊 / 解锁 / 记录 / 统计），槽位会变回「空」，设置保留。此操作不可撤销。",
				true,
				func() -> void:
					Save.reset_slot(i)
					_rebuild()))
		hb.add_child(ng)


## 二次确认弹窗（危险操作一律走这里）
func _ask_confirm(title: String, detail: String, danger: bool, cb: Callable) -> void:
	var ov := ColorRect.new()
	ov.color = Color(0, 0, 0, 0.74)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(ov)
	UI.full_rect(ov)
	var c := UI.card(440, 150, true)
	UI.pin(c["root"], 100, 105, 440, 150)
	ov.add_child(c["root"])
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	c["box"].add_child(v)
	var t := UI.lbl(title, 14, UI.C_PINK if danger else UI.C_TEXT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var d := UI.lbl(detail, 10, UI.C_DIM)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.custom_minimum_size = Vector2(400, 46)
	v.add_child(d)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 12)
	v.add_child(row)
	var ok := UI.btn("确定", 12, 110)
	ok.add_theme_color_override("font_color", UI.C_PINK)
	row.add_child(ok)
	var no := UI.btn("取消", 12, 110)
	row.add_child(no)
	ok.pressed.connect(func() -> void:
		Audio.play_ui()
		ov.queue_free()
		if cb.is_valid():
			cb.call())
	no.pressed.connect(func() -> void:
		Audio.play_ui()
		ov.queue_free())


func _page_settings() -> void:
	content.add_child(_header("设置", "main"))
	var rows := [
		["vol_master", "主音量"], ["vol_bgm", "背景音乐"], ["vol_sfx", "音效"],
	]
	for r in rows:
		var key := String(r[0])
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 12)
		var l := UI.lbl(String(r[1]), 12)
		l.custom_minimum_size = Vector2(110, 0)
		hb.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = float(Save.setting(key, 0.8))
		s.custom_minimum_size = Vector2(280, 18)
		s.value_changed.connect(func(v: float) -> void:
			Save.data["settings"][key] = v
			Save.save_game()
			Audio.refresh_volumes())
		hb.add_child(s)
		var vl := UI.lbl("%d%%" % int(float(Save.setting(key, 0.8)) * 100.0), 11, UI.C_DIM)
		s.value_changed.connect(func(v: float) -> void: vl.text = "%d%%" % int(v * 100.0))
		hb.add_child(vl)
		content.add_child(hb)
	content.add_child(UI.vspace(8))
	var checks := [
		["autofire", "自动开火（按住鼠标才射击的开关）"],
		["shake", "画面震动"],
		["show_fps", "显示帧率"],
		["fullscreen", "全屏（F11）"],
	]
	for c in checks:
		var key := String(c[0])
		var cb := CheckBox.new()
		cb.text = String(c[1])
		cb.button_pressed = bool(Save.setting(key, false))
		cb.add_theme_font_size_override("font_size", 12)
		cb.toggled.connect(func(on: bool) -> void:
			Audio.play_ui()
			Save.set_setting(key, on)
			if key == "fullscreen":
				Game.apply_settings()
			elif key == "show_fps":
				Bus.shake.emit(0.0, 0.01))
		content.add_child(cb)
	content.add_child(UI.vspace(10))
	var tips := UI.lbl("操作：WASD 移动　鼠标瞄准　空格冲刺　E / Q 主动技能　ESC 暂停　F11 全屏\n主动技能通过升级三选一获得（困难难度开局自带一个）", 10, UI.C_DIM)
	tips.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(tips)


func _header(text: String, back_to: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	var b := UI.btn("← 返回", 11, 76)
	b.pressed.connect(func() -> void:
		Audio.play_ui()
		page = back_to
		_rebuild())
	hb.add_child(b)
	var t := UI.lbl(text, 14, UI.C_ACCENT)
	t.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hb.add_child(t)
	return hb
