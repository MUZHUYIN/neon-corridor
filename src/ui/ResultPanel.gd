class_name ResultPanel
extends Control

signal retry_pressed
signal next_pressed
signal menu_pressed

var title: Label
var body: Label
var next_btn: Button
var retry_btn: Button


func _ready() -> void:
	UI.full_rect(self)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UI.dimmer(0.82)
	add_child(dim)
	UI.full_rect(dim)

	var card := UI.card(400, 232, true, 16)
	add_child(card["root"])
	UI.pin_center(card["root"], 400, 232)
	var box: VBoxContainer = card["box"]
	title = UI.lbl("", 20, UI.C_ACCENT)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	box.add_child(UI.vspace(6))
	body = UI.lbl("", 12, UI.C_TEXT)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(body)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	retry_btn = UI.btn("再来一次", 12, 104)
	retry_btn.pressed.connect(func() -> void:
		Audio.play_ui()
		retry_pressed.emit())
	row.add_child(retry_btn)
	next_btn = UI.btn("下一关", 12, 104)
	next_btn.pressed.connect(func() -> void:
		Audio.play_ui()
		next_pressed.emit())
	row.add_child(next_btn)
	var mb := UI.btn("返回主菜单", 12, 104)
	mb.pressed.connect(func() -> void:
		Audio.play_ui()
		menu_pressed.emit())
	row.add_child(mb)


func show_result(entry: Dictionary, stage_idx: int, endless: bool, has_next: bool) -> void:
	var win := bool(entry.get("win", false))
	title.text = "关卡完成！" if win else "你倒下了"
	title.add_theme_color_override("font_color", UI.C_GREEN if win else UI.C_RED)
	if endless:
		title.text = "无尽结束"
	body.text = "存活 %d:%02d　等级 %d\n击杀 %d　获得齿轮 %d\n%s" % [
		int(entry.get("time", 0)) / 60, int(entry.get("time", 0)) % 60,
		int(entry.get("level", 1)), int(entry.get("kills", 0)), int(entry.get("gears", 0)),
		"齿轮已存入工坊。" if win else "齿轮已存入工坊，去工坊变强再来。"]
	next_btn.visible = win and has_next and not endless
	visible = true
