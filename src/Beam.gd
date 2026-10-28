class_name Beam
extends Node2D
## 瞬时激光束：从枪口到命中点画一条分层光带，短时间内淡出。
## 之前的"激光"其实是一颗飞得很快的子弹，看起来和普通子弹没区别。

var p0 := Vector2.ZERO
var p1 := Vector2.ZERO
var tint := Color("34f0ff")
var width := 15.0
var life := 0.18
var t := 0.0
var impact := true


static func spawn(parent: Node, from: Vector2, to: Vector2, tint_: Color,
		width_: float, life_: float = 0.18, impact_: bool = true) -> Beam:
	var b := Beam.new()
	b.p0 = from
	b.p1 = to
	b.tint = tint_
	b.width = width_
	b.life = maxf(0.05, life_)
	b.impact = impact_
	b.z_index = 2
	parent.add_child(b)
	return b


func _process(delta: float) -> void:
	t += delta
	if t >= life:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var k: float = clampf(1.0 - t / life, 0.0, 1.0)
	var w: float = width * (0.35 + 0.65 * k)
	# 外层辉光 → 中层主色 → 白色核心
	draw_line(p0, p1, Color(tint.r, tint.g, tint.b, 0.14 * k), w * 3.0, true)
	draw_line(p0, p1, Color(tint.r, tint.g, tint.b, 0.42 * k), w * 1.6, true)
	draw_line(p0, p1, Color(tint.r, tint.g, tint.b, 0.85 * k), w, true)
	draw_line(p0, p1, Color(1, 1, 1, 0.95 * k), maxf(1.5, w * 0.30), true)
	# 枪口闪光
	draw_circle(p0, w * 1.1, Color(tint.r, tint.g, tint.b, 0.65 * k))
	draw_circle(p0, w * 0.5, Color(1, 1, 1, 0.9 * k))
	if impact:
		draw_circle(p1, w * 2.6, Color(tint.r, tint.g, tint.b, 0.30 * k))
		draw_circle(p1, w * 1.3, Color(tint.r, tint.g, tint.b, 0.75 * k))
		draw_circle(p1, w * 0.55, Color(1, 1, 1, 0.95 * k))
