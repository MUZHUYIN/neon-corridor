extends Node
## 统一 UI 工厂：字体、九宫格面板、按钮、图标、颜色常量。所有界面都走这里，风格才统一。

const C_BG := Color("0a0a14")
const C_TEXT := Color("dfe6ff")
const C_DIM := Color("8c92b8")
const C_ACCENT := Color("34f0ff")
const C_PINK := Color("ff3e82")
const C_YELLOW := Color("ffe460")
const C_GREEN := Color("58f08e")
const C_RED := Color("ff4c3a")

var _theme: Theme = null


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func theme() -> Theme:
	if _theme != null:
		return _theme
	_theme = Theme.new()
	if Art.font != null:
		_theme.default_font = Art.font
	_theme.default_font_size = 12
	return _theme


func install(root: Window) -> void:
	root.theme = theme()


# ---------------------------------------------------------------- widgets
func lbl(text: String, size: int = 12, col: Color = C_TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	return l


func rich(text: String, size: int = 12) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.text = text
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_color_override("default_color", C_TEXT)
	return r


func nine(name: String, margin: int = 10) -> NinePatchRect:
	var n := NinePatchRect.new()
	n.texture = Art.tex(name)
	n.patch_margin_left = margin
	n.patch_margin_right = margin
	n.patch_margin_top = margin
	n.patch_margin_bottom = margin
	return n


func panel(margin_fill: bool = true, dark: bool = false) -> NinePatchRect:
	var n := nine("ui_panel_dark" if dark else "ui_panel", 10)
	if margin_fill:
		full_rect(n)
		n.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return n


func _stylebox(name: String) -> StyleBoxTexture:
	var sb := StyleBoxTexture.new()
	sb.texture = Art.tex(name)
	sb.set_texture_margin_all(8.0)
	sb.content_margin_left = 10.0
	sb.content_margin_right = 10.0
	sb.content_margin_top = 5.0
	sb.content_margin_bottom = 5.0
	return sb


func btn(text: String, size: int = 12, min_w: float = 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_stylebox_override("normal", _stylebox("ui_btn"))
	b.add_theme_stylebox_override("hover", _stylebox("ui_btn_hi"))
	b.add_theme_stylebox_override("pressed", _stylebox("ui_btn_dn"))
	b.add_theme_stylebox_override("focus", _stylebox("ui_btn_dn"))
	b.add_theme_color_override("font_color", C_TEXT)
	b.add_theme_color_override("font_hover_color", C_ACCENT)
	b.add_theme_color_override("font_pressed_color", C_ACCENT)
	b.add_theme_color_override("font_disabled_color", Color("555a7a"))
	if min_w > 0.0:
		b.custom_minimum_size = Vector2(min_w, 0.0)
	b.mouse_entered.connect(func() -> void: Audio.play("sfx_ui_hover", 1.0, 0.02, 0.4))
	return b


func icon(name: String, scale: float = 1.0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Art.tex(name)
	t.custom_minimum_size = Art.size_of(name) * scale
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


func sprite_box(name: String, scale: float = 1.0, frame: int = 0) -> TextureRect:
	var t := TextureRect.new()
	t.texture = Art.tex(name, frame)
	t.custom_minimum_size = Art.size_of(name) * scale
	t.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	t.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return t


## 两段式进度条：返回 {root, fill}，用 set_bar() 更新
func bar(w: float, h: float, fill_name: String) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(w, h)
	root.size = Vector2(w, h)
	# 关键：条放在 HBox 里时会被同行更高的元素（图标/文字）撑高，
	# 而填充高度是按 h 算的 —— 结果就是"只显示上半部分"。
	root.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	root.clip_contents = false
	var bg := TextureRect.new()
	bg.texture = Art.tex("ui_bar_bg")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.stretch_mode = TextureRect.STRETCH_SCALE
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(bg)
	var fill := TextureRect.new()
	fill.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	fill.texture = Art.tex(fill_name)
	fill.position = Vector2(2, 2)
	fill.size = Vector2(maxf(0.0, w - 4), h - 4)
	fill.stretch_mode = TextureRect.STRETCH_SCALE
	fill.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(fill)
	root.set_meta("w", w)
	root.set_meta("h", h)
	return {"root": root, "fill": fill}


func set_bar(bar_dict: Dictionary, ratio: float, max_w: float = -1.0) -> void:
	var root: Control = bar_dict["root"]
	var fill: TextureRect = bar_dict["fill"]
	var w: float = max_w if max_w > 0.0 else float(root.get_meta("w"))
	var h: float = float(root.get_meta("h"))
	fill.size = Vector2(maxf(0.0, (w - 4) * clampf(ratio, 0.0, 1.0)), h - 4)


## 卡片：九宫格底 + 竖排内容区
func card(w: float, h: float, sel: bool = false, pad: int = 10) -> Dictionary:
	var root := Control.new()
	root.custom_minimum_size = Vector2(w, h)
	var bg := nine("ui_card_sel" if sel else "ui_card", 10)
	root.add_child(bg)
	_anchors_full(bg)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	root.add_child(box)
	box.anchor_left = 0.0
	box.anchor_top = 0.0
	box.anchor_right = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = pad
	box.offset_top = pad - 2
	box.offset_right = -float(pad)
	box.offset_bottom = -float(pad) + 2
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 5)
	return {"root": root, "box": box}


## 明确用锚点+偏移摆放控件，避免容器布局的意外
func pin(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 0.0
	c.anchor_bottom = 0.0
	c.offset_left = x
	c.offset_top = y
	c.offset_right = x + w
	c.offset_bottom = y + h


## 贴右上角：rx 是距右边缘的距离
func pin_ne(c: Control, rx: float, y: float, w: float, h: float) -> void:
	c.anchor_left = 1.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 0.0
	c.offset_left = -rx - w
	c.offset_top = y
	c.offset_right = -rx
	c.offset_bottom = y + h


## 贴左下角：ry 是距下边缘的距离
func pin_sw(c: Control, x: float, ry: float, w: float, h: float) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 1.0
	c.anchor_right = 0.0
	c.anchor_bottom = 1.0
	c.offset_left = x
	c.offset_top = -ry - h
	c.offset_right = x + w
	c.offset_bottom = -ry


## 居中：cw/ch 为控件尺寸
func pin_center(c: Control, cw: float, ch: float) -> void:
	c.anchor_left = 0.5
	c.anchor_top = 0.5
	c.anchor_right = 0.5
	c.anchor_bottom = 0.5
	c.offset_left = -cw * 0.5
	c.offset_top = -ch * 0.5
	c.offset_right = cw * 0.5
	c.offset_bottom = ch * 0.5


## 代码生成准星贴图（32x32 霓虹准星），不依赖素材导入
func make_crosshair() -> ImageTexture:
	var S := 32
	var img := Image.create(S, S, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var cx := S / 2
	var gap := 5
	var arm := 9
	for i in range(gap, gap + arm):
		for d in [-1, 1]:
			for t in [-1, 0]:
				img.set_pixel(cx + t, cx + d * i, Color(0.06, 0.06, 0.10, 0.95))
				img.set_pixel(cx + d * i, cx + t, Color(0.06, 0.06, 0.10, 0.95))
	for i in range(gap, gap + arm):
		for d in [-1, 1]:
			img.set_pixel(cx, cx + d * i, Color(0.20, 0.94, 1.0, 1.0))
			img.set_pixel(cx + d * i, cx, Color(0.20, 0.94, 1.0, 1.0))
	for a in [-1, 0, 1]:
		for b in [-1, 0, 1]:
			img.set_pixel(cx + a, cx + b, Color(1, 1, 1, 1) if (a == 0 and b == 0) else Color(0.20, 0.94, 1.0, 0.9))
	return ImageTexture.create_from_image(img)


func set_crosshair(on: bool) -> void:
	if DisplayServer.get_name() == "headless":
		return
	if on:
		Input.set_custom_mouse_cursor(make_crosshair(), Input.CURSOR_ARROW, Vector2(16, 16))
	else:
		Input.set_custom_mouse_cursor(null, Input.CURSOR_ARROW)


func vspace(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(1, h)
	return c


func hspace(w: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 1)
	return c


func _anchors_full(c: Control) -> void:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0


func full_rect(c: Control) -> Control:
	c.anchor_left = 0.0
	c.anchor_top = 0.0
	c.anchor_right = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = 0.0
	c.offset_top = 0.0
	c.offset_right = 0.0
	c.offset_bottom = 0.0
	return c


## 全屏半透明遮罩
func dimmer(alpha: float = 0.72) -> ColorRect:
	var r := ColorRect.new()
	r.color = Color(0.02, 0.02, 0.05, alpha)
	_anchors_full(r)
	r.mouse_filter = Control.MOUSE_FILTER_STOP
	return r
