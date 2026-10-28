class_name Hud
extends Control
## 战斗 HUD。全部用显式锚点/偏移摆放，避免容器布局意外。

var world = null
var hp_bar: Dictionary
var xp_bar: Dictionary
var dash_bar: Dictionary
var hp_label: Label
var lv_label: Label
var timer_label: Label
var gear_label: Label
var kill_label: Label
var boss_root: Control
var boss_bar: Dictionary
var boss_name: Label
var wave_label: Label
var weapon_row: HBoxContainer
var passive_row: HBoxContainer
var dash_label: Label
var vignette: ColorRect
var heal_flash: ColorRect
var _heal_t := 0.0
var fps_label: Label
var hint_label: Label
var shield_row: Control
var shield_bar: Dictionary
var skill_slots: Array = []
var minimap: Minimap = null
var _hint_t := 0.0
var _wave_t := 0.0
var _sig := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	UI.full_rect(self)

	vignette = ColorRect.new()
	vignette.color = Color(0.8, 0.05, 0.1, 0.0)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	UI.full_rect(vignette)

	heal_flash = ColorRect.new()
	heal_flash.color = Color(0.20, 0.95, 0.45, 0.0)
	heal_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(heal_flash)
	UI.full_rect(heal_flash)

	# ---------------- 左上：血 / 经验 / 冲刺
	var tl := Control.new()
	UI.pin(tl, 8, 6, 300, 58)
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tl)
	var tlv := VBoxContainer.new()
	tl.add_child(tlv)
	UI.full_rect(tlv)
	tlv.add_theme_constant_override("separation", 2)

	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 6)
	tlv.add_child(hp_row)
	hp_row.add_child(UI.icon("icon_m_heart", 1.0))
	hp_bar = UI.bar(150, 12, "ui_bar_hp")
	hp_row.add_child(hp_bar["root"])
	hp_label = UI.lbl("100/100", 10, UI.C_TEXT)
	hp_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hp_row.add_child(hp_label)

	var xp_row := HBoxContainer.new()
	xp_row.add_theme_constant_override("separation", 6)
	tlv.add_child(xp_row)
	lv_label = UI.lbl("Lv.1", 11, UI.C_ACCENT)
	lv_label.custom_minimum_size = Vector2(36, 0)
	xp_row.add_child(lv_label)
	xp_bar = UI.bar(150, 10, "ui_bar_xp")
	xp_row.add_child(xp_bar["root"])

	var dash_row := HBoxContainer.new()
	dash_row.add_theme_constant_override("separation", 6)
	tlv.add_child(dash_row)
	dash_label = UI.lbl("就绪", 9, UI.C_DIM)
	dash_label.custom_minimum_size = Vector2(36, 0)
	dash_row.add_child(dash_label)
	dash_bar = UI.bar(150, 6, "ui_bar_xp")
	dash_row.add_child(dash_bar["root"])

	var sh_row := HBoxContainer.new()
	sh_row.add_theme_constant_override("separation", 6)
	tlv.add_child(sh_row)
	shield_row = sh_row
	var sh_spacer := Control.new()
	sh_spacer.custom_minimum_size = Vector2(36, 0)
	sh_row.add_child(sh_spacer)
	shield_bar = UI.bar(150, 6, "ui_bar_xp")
	(shield_bar["fill"] as TextureRect).modulate = Color(0.55, 0.82, 1.45)
	sh_row.add_child(shield_bar["root"])
	shield_row.visible = false

	# ---------------- 右上：计时 / 击杀 / 齿轮 / FPS
	var tr := Control.new()
	UI.pin_ne(tr, 8, 6, 190, 62)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tr)
	var trv := VBoxContainer.new()
	tr.add_child(trv)
	UI.full_rect(trv)
	trv.add_theme_constant_override("separation", 2)
	timer_label = UI.lbl("0:00 / 4:00", 13, UI.C_TEXT)
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trv.add_child(timer_label)
	kill_label = UI.lbl("击杀 0", 10, UI.C_DIM)
	kill_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trv.add_child(kill_label)
	var grow := HBoxContainer.new()
	grow.alignment = BoxContainer.ALIGNMENT_END
	grow.add_theme_constant_override("separation", 4)
	grow.add_child(UI.icon("icon_m_gear", 1.0))
	gear_label = UI.lbl("0", 11, UI.C_YELLOW)
	grow.add_child(gear_label)
	trv.add_child(grow)
	fps_label = UI.lbl("", 9, UI.C_DIM)
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	trv.add_child(fps_label)

	# ---------------- 左下：武器 / 被动
	# 右移给小地图让出左下角
	var bl := Control.new()
	UI.pin_sw(bl, 112, 6, 340, 60)
	bl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bl)
	var blv := VBoxContainer.new()
	bl.add_child(blv)
	UI.full_rect(blv)
	blv.alignment = BoxContainer.ALIGNMENT_END
	blv.add_theme_constant_override("separation", 3)
	weapon_row = HBoxContainer.new()
	weapon_row.add_theme_constant_override("separation", 6)
	blv.add_child(weapon_row)
	passive_row = HBoxContainer.new()
	passive_row.add_theme_constant_override("separation", 4)
	blv.add_child(passive_row)

	# ---------------- Boss 血条
	boss_root = Control.new()
	boss_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_root.visible = false
	add_child(boss_root)
	UI.full_rect(boss_root)
	boss_name = UI.lbl("BOSS", 11, UI.C_PINK)
	boss_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.pin(boss_name, 0, 52, 640, 16)
	boss_root.add_child(boss_name)
	var bwrap := Control.new()
	UI.pin(bwrap, 150, 70, 340, 12)
	bwrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boss_root.add_child(bwrap)
	boss_bar = UI.bar(340, 12, "ui_bar_boss")
	UI.pin(boss_bar["root"], 0, 0, 340, 12)
	bwrap.add_child(boss_bar["root"])

	# ---------------- 首次游玩提示
	hint_label = UI.lbl("WASD 移动　·　鼠标瞄准　·　自动开火　·　空格冲刺　·　E / Q 技能", 11, UI.C_DIM)
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# 上移，避免压到左下角的小地图
	UI.pin(hint_label, 0, 266, 640, 18)
	hint_label.modulate.a = 0.0
	add_child(hint_label)
	_hint_t = 11.0 if int(Save.data.get("stats", {}).get("runs", 0)) == 0 else 0.0
	hint_label.modulate.a = 1.0 if _hint_t > 0.0 else 0.0



	# ---------------- 中央提示
	wave_label = UI.lbl("", 16, UI.C_YELLOW)
	wave_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	UI.pin(wave_label, 0, 100, 640, 24)
	wave_label.modulate.a = 0.0
	add_child(wave_label)

	# ---------------- 小地图（左下角） ----------------
	# 原来 140x96 放屏幕下方中间太挡视野，缩到 96x66 收进左下角
	var mm := Minimap.new()
	UI.pin(mm, 8, 288, 96, 66)
	mm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mm)
	minimap = mm

	# ---------------- 技能槽（右下） ----------------
	var sk_wrap := Control.new()
	UI.pin(sk_wrap, 470, 300, 162, 52)
	sk_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(sk_wrap)
	var sk_row := HBoxContainer.new()
	sk_row.alignment = BoxContainer.ALIGNMENT_END
	sk_row.add_theme_constant_override("separation", 6)
	UI.full_rect(sk_row)
	sk_wrap.add_child(sk_row)
	for i in 2:
		skill_slots.append(_make_skill_slot(sk_row, ["E", "Q"][i]))

	Bus.player_hp_changed.connect(_on_hp)
	Bus.level_changed.connect(_on_level)
	Bus.kill_count.connect(func(n: int) -> void: kill_label.text = "击杀 %d" % n)
	Bus.boss_spawned.connect(_on_boss)
	Bus.boss_hp_changed.connect(_on_boss_hp)
	Bus.boss_died.connect(func() -> void: boss_root.visible = false)
	Bus.player_healed.connect(func(_n: float) -> void: _heal_t = 0.4)
	Bus.player_shield_changed.connect(_on_shield)
	Bus.wave_phase.connect(show_wave)
	Bus.upgrade_taken.connect(func(_id: String) -> void: _sig = "")


func _make_skill_slot(parent: Node, key_text: String) -> Dictionary:
	var slot := Control.new()
	slot.custom_minimum_size = Vector2(46, 46)
	var bg := UI.nine("ui_card", 8)
	slot.add_child(bg)
	UI.full_rect(bg)
	var key := UI.lbl(key_text, 9, UI.C_ACCENT)
	slot.add_child(key)
	UI.pin(key, 3, 1, 16, 12)
	var ic := UI.icon("icon_s_shock", 1.4)
	ic.visible = false
	slot.add_child(ic)
	UI.pin(ic, 9, 9, 28, 28)
	var empty := UI.lbl("空", 10, UI.C_DIM)
	empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slot.add_child(empty)
	UI.pin(empty, 0, 15, 46, 16)
	var cd := ColorRect.new()
	cd.color = Color(0.02, 0.02, 0.06, 0.72)
	cd.visible = false
	cd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(cd)
	cd.anchor_left = 0.0
	cd.anchor_top = 0.0
	cd.anchor_right = 1.0
	cd.anchor_bottom = 0.0
	cd.offset_left = 0.0
	cd.offset_top = 0.0
	cd.offset_right = 0.0
	cd.offset_bottom = 46.0
	parent.add_child(slot)
	return {"root": slot, "icon": ic, "empty": empty, "cd": cd, "sid": ""}


func _on_shield(shield: float, _mx: float) -> void:
	if shield_row == null:
		return
	shield_row.visible = shield > 0.5
	UI.set_bar(shield_bar, clampf(shield / 120.0, 0.0, 1.0))


func _update_skills() -> void:
	if world == null or not is_instance_valid(world):
		return
	var pl = world.player
	if pl == null or not is_instance_valid(pl):
		return
	for i in skill_slots.size():
		var s: Dictionary = skill_slots[i]
		var has: bool = i < pl.skills.size()
		(s["icon"] as TextureRect).visible = has
		(s["empty"] as Label).visible = not has
		var cd_rect: ColorRect = s["cd"]
		cd_rect.visible = false
		if not has:
			continue
		var sid := String(pl.skills[i]["id"])
		if String(s["sid"]) != sid:
			s["sid"] = sid
			(s["icon"] as TextureRect).texture = Art.tex(String(DB.skill(sid)["icon"]))
			(s["empty"] as Label).visible = false
		var cdf := float(pl.skills[i]["cd_left"])
		if cdf > 0.01:
			var total := maxf(0.01, float(DB.skill(sid)["cd"]))
			cd_rect.visible = true
			cd_rect.offset_bottom = 46.0 * clampf(cdf / total, 0.0, 1.0)


func show_wave(text: String) -> void:
	if wave_label == null:
		return
	wave_label.text = text
	wave_label.modulate.a = 1.0
	_wave_t = 2.6


func bind(p_world) -> void:
	world = p_world
	if minimap != null:
		minimap.bind(p_world)
	_sig = ""
	boss_root.visible = false
	wave_label.modulate.a = 0.0
	kill_label.text = "击杀 0"
	gear_label.text = "0"
	if world != null:
		_on_hp(world.player.hp, world.player.max_hp)
		_on_level(world.player.level, world.player.xp, world.player.xp_need)



func _on_hp(hp: float, max_hp: float) -> void:
	if hp_bar.is_empty():
		return
	UI.set_bar(hp_bar, hp / maxf(1.0, max_hp))
	hp_label.text = "%d/%d" % [int(ceil(hp)), int(max_hp)]
	var low := clampf(1.0 - hp / maxf(1.0, max_hp * 0.35), 0.0, 1.0)
	if hp <= 0.0:
		low = 0.0
	vignette.color = Color(0.8, 0.05, 0.1, low * 0.42)


func _on_level(level: int, cur: int, need: int) -> void:
	lv_label.text = "Lv.%d" % level
	UI.set_bar(xp_bar, float(cur) / maxf(1.0, float(need)))


func _on_boss(b) -> void:
	if b == null:
		return
	boss_root.visible = true
	boss_name.text = String(b.boss_name)


func _on_boss_hp(hp: float, max_hp: float) -> void:
	UI.set_bar(boss_bar, hp / maxf(1.0, max_hp))


func _process(delta: float) -> void:
	if world == null or not is_instance_valid(world):
		return
	if world.endless:
		timer_label.text = "无尽 %d:%02d" % [int(world.elapsed) / 60, int(world.elapsed) % 60]
	else:
		var total := float(DB.stage(world.stage_idx)["duration"])
		var shown: float = minf(world.elapsed, total)
		if world.elapsed >= total:
			timer_label.text = "BOSS  已用时 %d:%02d" % [int(world.elapsed) / 60, int(world.elapsed) % 60]
		else:
			timer_label.text = "%d:%02d / %d:%02d" % [int(shown) / 60, int(shown) % 60,
				int(total) / 60, int(total) % 60]
	gear_label.text = str(world.gears_earned)
	var pl = world.player
	if pl != null and is_instance_valid(pl):
		var cd: float = maxf(0.0, pl.dash_cd)
		UI.set_bar(dash_bar, 1.0 - cd / DB.DASH_CD)
		dash_label.text = "就绪" if cd <= 0.01 else "%.1fs" % cd
		var sig := ""
		for wp in pl.weapons:
			sig += "%s%d%s|" % [wp["id"], int(wp["lv"]), "E" if bool(wp.get("evolved", false)) else ""]
		for pid in pl.passives.keys():
			sig += "%s%d|" % [pid, int(pl.passives[pid])]
		if sig != _sig:
			_sig = sig
			_refresh_loadout(pl)
	_update_skills()
	if _heal_t > 0.0:
		_heal_t -= delta
		heal_flash.color = Color(0.20, 0.95, 0.45, clampf(_heal_t / 0.4, 0.0, 1.0) * 0.16)
	if _hint_t > 0.0:
		_hint_t -= delta
		hint_label.modulate.a = clampf(_hint_t / 1.5, 0.0, 1.0)
	if _wave_t > 0.0:
		_wave_t -= delta
		if _wave_t < 0.6:
			wave_label.modulate.a = clampf(_wave_t / 0.6, 0.0, 1.0)
	fps_label.visible = bool(Save.setting("show_fps", false))
	if fps_label.visible:
		fps_label.text = "%d FPS  E:%d" % [Engine.get_frames_per_second(), world.enemies.size()]


func _refresh_loadout(pl) -> void:
	for c in weapon_row.get_children():
		c.queue_free()
	for c in passive_row.get_children():
		c.queue_free()
	for wp in pl.weapons:
		var d: Dictionary = DB.weapon(String(wp["id"]))
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 2)
		hb.add_child(UI.icon(String(d["icon"]), 1.2))
		var lv := UI.lbl("E" if bool(wp.get("evolved", false)) else str(int(wp["lv"])), 9,
			UI.C_YELLOW if bool(wp.get("evolved", false)) else UI.C_DIM)
		lv.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		hb.add_child(lv)
		weapon_row.add_child(hb)
	for pid in pl.passives.keys():
		var pd: Dictionary = DB.passive(String(pid))
		var hb2 := HBoxContainer.new()
		hb2.add_theme_constant_override("separation", 1)
		hb2.add_child(UI.icon(String(pd["icon"]), 1.0))
		var l2 := UI.lbl(str(int(pl.passives[pid])), 9, UI.C_DIM)
		l2.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		hb2.add_child(l2)
		passive_row.add_child(hb2)
