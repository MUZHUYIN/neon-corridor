class_name Hazard
extends Node2D
## 环境危害：巡逻激光门 / 数据风暴区 / 熔岩喷口 / 旋转激光臂 / 腐蚀区。
## 全部走手写碰撞，不依赖物理引擎。

var kind := "laser_gate"
var cfg: Dictionary = {}
var world = null
var t := 0.0
var phase := 0          # 0 预警(telegraph) 1 生效 2 燃烧/消退
var p0 := Vector2.ZERO
var p1 := Vector2.ZERO
var radius := 60.0
var dmg := 10.0
var slow := 1.0
var life := 6.0
var angle := 0.0
var spin := 0.0
var dead := false
var permanent := false
var _was_warned := false


static func spawn(parent: Node, kind_: String, pos: Vector2, extra: Dictionary = {}) -> Hazard:
	var h := Hazard.new()
	h.kind = kind_
	h.cfg = DB.hazard(kind_)
	h.position = pos
	h.z_index = 4
	match kind_:
		"laser_gate":
			var arena: Vector2 = Game.world.arena.arena_size
			var horiz: bool = float(extra.get("horiz", 1.0)) > 0.5
			if horiz:
				h.p0 = Vector2(0, pos.y)
				h.p1 = Vector2(arena.x, pos.y)
			else:
				h.p0 = Vector2(pos.x, 0)
				h.p1 = Vector2(pos.x, arena.y)
			h.dmg = float(h.cfg["dmg"])
			h.radius = float(h.cfg["width"])
			h.life = float(h.cfg["warn"]) + float(h.cfg["active"])
		"storm_zone":
			h.dmg = float(h.cfg["dmg"])
			h.radius = float(h.cfg["radius"])
			h.slow = float(h.cfg["slow"])
			h.life = float(h.cfg["warn"]) + float(h.cfg["active"])
		"lava_vent":
			h.dmg = float(h.cfg["dmg"])
			h.radius = float(h.cfg["radius"])
			h.life = float(h.cfg["warn"]) + float(h.cfg["active"]) + float(h.cfg["burn"])
		"laser_arm":
			h.dmg = float(h.cfg["dmg"])
			h.radius = float(h.cfg["width"])
			h.spin = float(h.cfg["spin"]) * (1.0 if float(extra.get("dir", 1.0)) > 0 else -1.0)
			h.angle = float(extra.get("angle", 0.0))
			h.permanent = true
			h.life = 9999.0
		"corro":
			h.dmg = float(h.cfg["dmg"])
			h.radius = float(h.cfg["radius"])
			h.life = float(h.cfg["life"])
	parent.add_child(h)
	return h


func world_node():
	return Game.world


func _physics_process(delta: float) -> void:
	if dead:
		return
	t += delta
	var wd = world_node()
	if wd == null:
		return
	if kind == "laser_arm":
		angle += spin * delta
		var c: Vector2 = wd.arena.arena_size * 0.5
		position = c
		var reach: float = wd.arena.arena_size.length()
		p0 = c
		p1 = c + Vector2(cos(angle), sin(angle)) * reach
		phase = 1
		_damage_player(wd)
		queue_redraw()
		return

	if kind == "laser_gate":
		var warn: float = float(cfg["warn"])
		var act: float = float(cfg["active"])
		phase = 0 if t < warn else (1 if t < warn + act else 2)
		if phase == 0 and not _was_warned:
			Audio.play("sfx_warn", 0.9, 0.03, 0.35)
			_was_warned = true
		if phase == 0:
			# 预警期间缓慢移动，给玩家躲避余地
			pass
	elif kind == "storm_zone":
		var warn2: float = float(cfg["warn"])
		phase = 0 if t < warn2 else (1 if t < warn2 + float(cfg["active"]) else 2)
	elif kind == "lava_vent":
		var warn3: float = float(cfg["warn"])
		var act3: float = float(cfg["active"])
		phase = 0 if t < warn3 else (1 if t < warn3 + act3 else 2)
		if phase == 1 and _was_warned == false:
			_was_warned = true
			Audio.play("sfx_explode", 1.2, 0.05, 0.5)
			Fx.spawn(wd.fx_layer, "vfx_explosion", position, 1.4, 18.0, Color(1.6, 0.9, 0.5))
			wd.shake(4.0, 0.25)
	elif kind == "corro":
		phase = 1 if t < float(cfg["life"]) - 0.4 else 2

	if phase == 1 or (phase == 2 and kind == "lava_vent"):
		_damage_player(wd)
	if t >= life:
		dead = true
		queue_free()
		return
	queue_redraw()


func _damage_player(wd) -> void:
	var pl = wd.player
	if pl == null or not is_instance_valid(pl) or pl.dead:
		return
	var hit := false
	match kind:
		"laser_gate", "laser_arm":
			var d: float = _dist_to_segment(pl.global_position, p0, p1)
			hit = d < radius + Player.RADIUS
		_:
			hit = pl.global_position.distance_to(global_position) < radius + Player.RADIUS
	if not hit:
		return
	if slow < 1.0 and kind == "storm_zone":
		pl.apply_slow(slow, 0.3)
	if kind == "laser_arm" or phase == 1:
		pl.take_damage(dmg, global_position)
	elif phase == 2 and kind == "lava_vent":
		pl.take_damage(float(cfg.get("burn_dmg", 6.0)), global_position)


static func _dist_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var den := ab.length_squared()
	if den < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / den, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _draw() -> void:
	var local0 := p0 - position
	var local1 := p1 - position
	match kind:
		"laser_gate":
			if phase == 0:
				var a := 0.22 + 0.18 * sin(t * 22.0)
				draw_line(local0, local1, Color(1.0, 0.25, 0.3, a), 2.0, true)
			elif phase == 1:
				draw_line(local0, local1, Color(1.0, 0.15, 0.25, 0.30), 26.0, true)
				draw_line(local0, local1, Color(1.0, 0.35, 0.35, 0.72), 12.0, true)
				draw_line(local0, local1, Color(1.0, 0.92, 0.9, 1.0), 4.0, true)
			else:
				draw_line(local0, local1, Color(1.0, 0.3, 0.3, maxf(0.0, 0.25 * (1.0 - (t - float(cfg["warn"]) - float(cfg["active"])) * 4.0))), 3.0, true)
		"laser_arm":
			draw_line(local0, local1, Color(1.0, 0.4, 0.15, 0.28), 24.0, true)
			draw_line(local0, local1, Color(1.0, 0.6, 0.2, 0.7), 10.0, true)
			draw_line(local0, local1, Color(1.0, 0.95, 0.85, 1.0), 3.5, true)
		"storm_zone":
			var active := phase == 1
			var col := Color(0.62, 0.35, 1.0, 0.30 if active else 0.12)
			if active:
				draw_circle(Vector2.ZERO, radius, col)
				draw_circle(Vector2.ZERO, radius * (0.55 + 0.1 * sin(t * 3.0)), Color(0.75, 0.5, 1.0, 0.16))
			for k in 3:
				var rr := radius * (0.4 + 0.28 * k) + 4.0 * sin(t * 2.2 + k)
				draw_arc(Vector2.ZERO, rr, t * (1.2 + k * 0.5), t * (1.2 + k * 0.5) + PI * 1.1, 26,
					Color(0.72, 0.45, 1.0, 0.55 if active else 0.25), 2.0, true)
			draw_arc(Vector2.ZERO, radius, 0, TAU, 44, Color(0.8, 0.55, 1.0, 0.75 if active else 0.4), 2.0, true)
		"lava_vent":
			if phase == 0:
				var k := t / maxf(float(cfg["warn"]), 0.01)
				draw_arc(Vector2.ZERO, radius * (1.35 - 0.35 * k), 0, TAU, 40, Color(1.0, 0.45, 0.2, 0.75), 2.5, true)
				draw_circle(Vector2.ZERO, radius * k * 0.9, Color(1.0, 0.35, 0.15, 0.22))
			elif phase == 1:
				var k2 := (t - float(cfg["warn"])) / maxf(float(cfg["active"]), 0.01)
				draw_circle(Vector2.ZERO, radius * (1.0 + 0.25 * k2), Color(1.0, 0.55, 0.18, 0.85 - 0.5 * k2))
				draw_circle(Vector2.ZERO, radius * 0.55 * (1.0 + 0.4 * k2), Color(1.0, 0.95, 0.7, 0.9 - 0.6 * k2))
			else:
				var fl := 0.5 + 0.5 * sin(t * 16.0)
				draw_circle(Vector2.ZERO, radius * 0.85, Color(0.85, 0.28, 0.10, 0.30 + 0.18 * fl))
				draw_arc(Vector2.ZERO, radius * 0.85, 0, TAU, 34, Color(1.0, 0.5, 0.2, 0.6), 1.5, true)
		"corro":
			var fade := 1.0 - t / maxf(float(cfg["life"]), 0.01)
			draw_circle(Vector2.ZERO, radius, Color(0.45, 0.85, 0.30, 0.20 * fade + 0.06))
			draw_arc(Vector2.ZERO, radius, 0, TAU, 32, Color(0.6, 1.0, 0.4, 0.55 * fade), 1.5, true)
