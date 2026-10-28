class_name PausePanel
extends Control

signal resume_pressed
signal restart_pressed
signal menu_pressed

var tip: Label


func _ready() -> void:
	UI.full_rect(self)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UI.dimmer(0.75)
	add_child(dim)
	UI.full_rect(dim)
	var vb := VBoxContainer.new()
	add_child(vb)
	UI.full_rect(vb)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 9)
	var t := UI.lbl("暂停", 22, UI.C_ACCENT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var rows := [["继续游戏", "resume"], ["重新开始本关", "restart"], ["返回主菜单", "menu"]]
	for r in rows:
		var b := UI.btn(String(r[0]), 14, 220)
		b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		var act := String(r[1])
		b.pressed.connect(func() -> void:
			Audio.play_ui()
			if act == "resume":
				resume_pressed.emit()
			elif act == "restart":
				restart_pressed.emit()
			else:
				menu_pressed.emit()
		)
		vb.add_child(b)
	tip = UI.lbl("", 10, UI.C_DIM)
	tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(tip)
