class_name Minimap
extends Control
## 小地图：只显示"需要找的东西"——自己、Boss、悬赏目标、特殊道具、环境危害。
## 刻意不画普通敌人：190 个点在 140×96 的图上只会变成噪音。

const TEX_SCALE := 0.0625   # 竞技场 2048×1408 -> 128×88 静态底图

var world = null
var _static: ImageTexture = null


func bind(w) -> void:
	world = w
	_build_static()


func _process(_d: float) -> void:
	if world != null and is_instance_valid(world):
		queue_redraw()


func _stamp_circle(img: Image, c: Vector2, r: float, col: Color) -> void:
	var x0 := maxi(0, int(c.x - r))
	var x1 := mini(img.get_width() - 1, int(c.x + r))
	var y0 := maxi(0, int(c.y - r))
	var y1 := mini(img.get_height() - 1, int(c.y + r))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c) <= r:
				img.set_pixel(x, y, col)


## 静态底图只画一次（地面 + 立柱），之后每帧只叠动态点
func _build_static() -> void:
	if world == null or not is_instance_valid(world):
		return
	var asz: Vector2 = world.arena.arena_size
	var iw := maxi(8, int(round(asz.x * TEX_SCALE)))
	var ih := maxi(8, int(round(asz.y * TEX_SCALE)))
	var img := Image.create(iw, ih, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.06, 0.055, 0.12, 0.88))
	for q in world.arena.pillars:
		var c: Vector2 = q["pos"] * TEX_SCALE
		var r: float = maxf(0.9, float(q["r"]) * TEX_SCALE)
		_stamp_circle(img, c, r, Color(0.62, 0.50, 0.86, 0.98))
	_static = ImageTexture.create_from_image(img)


func _draw() -> void:
	if world == null or not is_instance_valid(world) or _static == null:
		return
	var asz: Vector2 = world.arena.arena_size
	var k := Vector2(size.x / asz.x, size.y / asz.y)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.03, 0.025, 0.06, 0.86))
	draw_texture_rect(_static, Rect2(Vector2.ZERO, size), false)
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.30, 0.58, 0.88, 0.8), false, 1.0)

	# 环境危害（岩浆口 / 激光门等）—— 躲它们比找它们重要
	var hl = world.hazard_layer()
	if hl != null and is_instance_valid(hl):
		for hz in hl.get_children():
			if is_instance_valid(hz) and hz.visible:
				draw_circle(hz.global_position * k, 1.7, Color(1.0, 0.42, 0.26, 0.75))

	# 特殊道具
	var pl_ = world.pickup_layer
	if pl_ != null and is_instance_valid(pl_):
		for p in pl_.get_children():
			if not is_instance_valid(p):
				continue
			match String(p.kind):
				"chest":
					draw_circle(p.global_position * k, 2.2, Color("ffb04a"))
				"shield":
					draw_circle(p.global_position * k, 1.7, Color("6ec8ff"))
				"pulse":
					draw_circle(p.global_position * k, 1.7, Color("b47aff"))
				"timechip":
					draw_circle(p.global_position * k, 1.7, Color("5ce8ff"))
				"rage":
					draw_circle(p.global_position * k, 1.7, Color("ff6a4a"))

	# 悬赏目标
	if world.bounty_target != null and is_instance_valid(world.bounty_target):
		var blink: float = 0.45 + 0.55 * (0.5 + 0.5 * sin(Time.get_ticks_msec() / 150.0))
		draw_circle(world.bounty_target.global_position * k, 2.8, Color(1.0, 0.90, 0.30, blink))

	# Boss
	if world.boss != null and is_instance_valid(world.boss):
		var bp: Vector2 = world.boss.global_position * k
		var pulse: float = 3.0 + 1.2 * sin(Time.get_ticks_msec() / 170.0)
		draw_circle(bp, pulse + 1.8, Color(1.0, 0.20, 0.15, 0.35))
		draw_circle(bp, pulse, Color(1.0, 0.34, 0.22))

	# 自己
	var pp: Vector2 = world.player.global_position * k
	var aim: Vector2 = world.player.aim
	if aim.length() > 0.1:
		draw_line(pp, pp + aim.normalized() * 7.0, Color(0.75, 1.0, 1.0, 0.9), 1.0)
	draw_circle(pp, 3.0, Color(0.30, 0.92, 1.0))
	draw_circle(pp, 1.5, Color.WHITE)
