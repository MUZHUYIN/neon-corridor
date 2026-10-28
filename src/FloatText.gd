class_name FloatText
extends Node2D
## 飘字：伤害数字 / 拾取提示。

var label: Label
var vel := Vector2.ZERO
var life := 0.7
var t := 0.0


static func spawn(parent: Node, text: String, pos: Vector2, col: Color,
		size: int = 10, vel: Vector2 = Vector2(0, -26), life: float = 0.7) -> FloatText:
	var f := FloatText.new()
	f.position = pos
	f.vel = vel
	f.life = life
	f.z_index = 60
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(-40, -8)
	l.custom_minimum_size = Vector2(80, 0)
	f.label = l
	f.add_child(l)
	parent.add_child(f)
	return f


func _process(delta: float) -> void:
	t += delta
	position += vel * delta
	vel *= 1.0 - 2.2 * delta
	var k := clampf(1.0 - t / life, 0.0, 1.0)
	if label != null:
		label.modulate.a = k
	if t >= life:
		queue_free()
