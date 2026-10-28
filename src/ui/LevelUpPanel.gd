class_name LevelUpPanel
extends Control
## 升级三选一 / 宝箱四选一。

signal chosen(c: Dictionary)

var _box: HBoxContainer
var _title: Label


func _ready() -> void:
	UI.full_rect(self)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := UI.dimmer(0.78)
	add_child(dim)
	UI.full_rect(dim)
	_title = UI.lbl("等级提升！选择一项强化", 16, UI.C_ACCENT)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_title)
	UI.pin(_title, 0, 62, 640, 24)
	_box = HBoxContainer.new()
	_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_box.add_theme_constant_override("separation", 10)
	add_child(_box)
	UI.pin(_box, 0, 92, 640, 172)
	var hint := UI.lbl("点击卡片选择　（数字键 1-4 也可）", 10, UI.C_DIM)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(hint)
	UI.pin(hint, 0, 328, 640, 18)


func show_choices(choices: Array, player) -> void:
	for c in _box.get_children():
		c.queue_free()
	var n: int = maxi(1, choices.size())
	var cw: float = clampf(560.0 / float(n) - 10.0, 96.0, 172.0)
	for i in choices.size():
		var ch: Dictionary = choices[i]
		var info := DB.describe_choice(ch, player)
		var card := UI.card(cw, 156, String(ch["type"]) == "evolve")
		_box.add_child(card["root"])
		var box: VBoxContainer = card["box"]
		var tag := UI.lbl("%s　[%d]" % [info["tag"], i + 1], 10, info["color"])
		box.add_child(tag)
		var ic := CenterContainer.new()
		ic.custom_minimum_size = Vector2(0, 40)
		ic.add_child(UI.icon(String(info["icon"]), 2.0))
		box.add_child(ic)
		var nm := UI.lbl(String(info["name"]), 12, UI.C_TEXT)
		nm.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(nm)
		var ds := UI.lbl(String(info["desc"]), 9, UI.C_DIM)
		ds.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ds.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		ds.size_flags_vertical = Control.SIZE_EXPAND_FILL
		box.add_child(ds)
		var btn := UI.btn("选择", 11)
		var cap := ch
		btn.pressed.connect(func() -> void:
			Audio.play_ui()
			chosen.emit(cap))
		box.add_child(btn)
	_title.text = "等级提升！选择一项强化" if choices.size() == 3 else "宝箱！从 %d 项中选一项" % choices.size()
	visible = true


func _unhandled_input(e: InputEvent) -> void:
	if not visible or not (e is InputEventKey) or not e.pressed or e.echo:
		return
	var k: int = e.keycode
	if k >= KEY_1 and k <= KEY_4:
		var idx: int = k - KEY_1
		var cards := _box.get_children()
		if idx < cards.size():
			var box: VBoxContainer = cards[idx].get_child(1)
			for ch in box.get_children():
				if ch is Button:
					(ch as Button).emit_signal("pressed")
					get_viewport().set_input_as_handled()
					return
