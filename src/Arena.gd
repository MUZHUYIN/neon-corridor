class_name Arena
extends Node2D
## 关卡背景：程序化地面 / 围墙 / 立柱 / 杂物。立柱同时是碰撞体（圆形，手写推挤）。

const CELL := 64.0
const WALL := 28.0

var theme := 0
var layout := "open"
var arena_size := Vector2(2048, 1408)
var pillars: Array = []
var crates: Array = []
var _rng := RandomNumberGenerator.new()
var _seed := 0
var _floor := "floor_0_0"
var _wall_h := "wall_h_0_0"
var _wall_v := "wall_v_0"


func setup(theme_idx: int, sz: Vector2, seed_val: int, layout_: String = "open") -> void:
	theme = theme_idx
	layout = layout_
	arena_size = sz
	_seed = seed_val
	_rng.seed = seed_val
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_floor = "floor_%d_0" % theme
	_wall_h = "wall_h_%d_%d" % [theme, _rng.randi_range(0, 1)]
	_wall_v = "wall_v_%d" % theme
	_generate()
	queue_redraw()


## 沿直线摆一串圆形柱，视觉上就是一堵墙（碰撞仍然是圆）
func _wall_line(a: Vector2, b: Vector2, r: float) -> void:
	var d := b - a
	var steps := maxi(1, int(d.length() / (r * 1.75)))
	for i in steps + 1:
		var p := a + d * (float(i) / float(steps))
		pillars.append({"pos": p, "r": r})


func _gen_cross() -> void:
	var c := arena_size * 0.5
	var m := 150.0
	_wall_line(Vector2(WALL + 130.0, c.y - 78.0), Vector2(c.x - m, c.y - 78.0), 26.0)
	_wall_line(Vector2(c.x + m, c.y - 78.0), Vector2(arena_size.x - WALL - 130.0, c.y - 78.0), 26.0)
	_wall_line(Vector2(WALL + 130.0, c.y + 78.0), Vector2(c.x - m, c.y + 78.0), 26.0)
	_wall_line(Vector2(c.x + m, c.y + 78.0), Vector2(arena_size.x - WALL - 130.0, c.y + 78.0), 26.0)
	_wall_line(Vector2(c.x - 78.0, WALL + 130.0), Vector2(c.x - 78.0, c.y - m), 26.0)
	_wall_line(Vector2(c.x - 78.0, c.y + m), Vector2(c.x - 78.0, arena_size.y - WALL - 130.0), 26.0)
	_wall_line(Vector2(c.x + 78.0, WALL + 130.0), Vector2(c.x + 78.0, c.y - m), 26.0)
	_wall_line(Vector2(c.x + 78.0, c.y + m), Vector2(c.x + 78.0, arena_size.y - WALL - 130.0), 26.0)
	for i in 4:
		var a := TAU * (float(i) / 4.0) + 0.78
		pillars.append({"pos": c + Vector2(cos(a), sin(a)) * 420.0, "r": 30.0})


func _gen_ring() -> void:
	var c := arena_size * 0.5
	var gaps := [3, 4, 13, 14]
	for i in 18:
		if gaps.has(i):
			continue
		var a := TAU * (float(i) / 18.0)
		pillars.append({"pos": c + Vector2(cos(a), sin(a)) * 350.0, "r": 27.0})
	for i in 4:
		var a2 := TAU * (float(i) / 4.0) + 0.4
		pillars.append({"pos": c + Vector2(cos(a2), sin(a2)) * 165.0, "r": 24.0})
	pillars.append({"pos": c + Vector2(620.0, -420.0), "r": 32.0})
	pillars.append({"pos": c + Vector2(-620.0, 420.0), "r": 32.0})


func _generate() -> void:
	pillars.clear()
	crates.clear()
	match layout:
		"cross":
			_gen_cross()
			for i in 12:
				crates.append({
					"pos": Vector2(_rng.randf_range(WALL + 40.0, arena_size.x - WALL - 40.0),
								   _rng.randf_range(WALL + 40.0, arena_size.y - WALL - 40.0)),
					"rot": 0.0})
			return
		"ring":
			_gen_ring()
			for i in 14:
				crates.append({
					"pos": Vector2(_rng.randf_range(WALL + 40.0, arena_size.x - WALL - 40.0),
								   _rng.randf_range(WALL + 40.0, arena_size.y - WALL - 40.0)),
					"rot": 0.0})
			return
	var n := 6 + theme * 2
	var tries := 0
	while pillars.size() < n and tries < 200:
		tries += 1
		var r: float = _rng.randf_range(22.0, 40.0)
		var p := Vector2(
			_rng.randf_range(WALL + 120.0, arena_size.x - WALL - 120.0),
			_rng.randf_range(WALL + 120.0, arena_size.y - WALL - 120.0))
		# 出生点周围留白
		if p.distance_to(arena_size * 0.5) < 190.0:
			continue
		var ok := true
		for q in pillars:
			if p.distance_to(q["pos"]) < r + float(q["r"]) + 90.0:
				ok = false
				break
		if ok:
			pillars.append({"pos": p, "r": r})
	for i in 10 + theme * 4:
		crates.append({
			"pos": Vector2(_rng.randf_range(WALL + 40.0, arena_size.x - WALL - 40.0),
						   _rng.randf_range(WALL + 40.0, arena_size.y - WALL - 40.0)),
			"rot": _rng.randf_range(0.0, TAU),
		})


func _draw() -> void:
	var base := Art.tile_tex(_floor)
	var variants: Array = [
		Art.tile_tex("floor_%d_1" % theme),
		Art.tile_tex("floor_%d_2" % theme),
		Art.tile_tex("floor_%d_3" % theme),
	]
	var r := RandomNumberGenerator.new()
	r.seed = _seed + 7717
	var cols := int(ceil(arena_size.x / CELL))
	var rows := int(ceil(arena_size.y / CELL))
	for j in rows:
		for i in cols:
			var p := Vector2(float(i) * CELL, float(j) * CELL)
			var v := r.randf()
			if v < 0.11:
				draw_texture(variants[r.randi_range(0, 2)], p)
			else:
				draw_texture(base, p)
	# 杂物
	for p2 in crates:
		draw_texture(Art.tile_tex("crate_%d" % theme), p2["pos"] - Vector2(16, 16))
	# 立柱
	for q in pillars:
		var s: float = float(q["r"]) / 18.0
		draw_set_transform(q["pos"], 0.0, Vector2(s, s))
		draw_texture(Art.tile_tex("pillar_%d" % theme), Vector2(-24, -24))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# 围墙（逐块）
	var wh := Art.tile_tex(_wall_h)
	var wv := Art.tile_tex(_wall_v)
	var n := int(arena_size.x / 64.0) + 1
	for i in n:
		var x := float(i) * 64.0
		draw_texture(wh, Vector2(x, 0))
		draw_texture(wh, Vector2(x, arena_size.y - 32.0))
	var m := int(arena_size.y / 64.0) + 1
	for j2 in m:
		var y := float(j2) * 64.0
		draw_texture(wv, Vector2(0, y))
		draw_texture(wv, Vector2(arena_size.x - 32.0, y))


func inner_rect() -> Rect2:
	return Rect2(Vector2(WALL, WALL), arena_size - Vector2(WALL, WALL) * 2.0)


## 把圆形实体推出立柱与边界，返回修正后的位置
func resolve(pos: Vector2, r: float) -> Vector2:
	var p := pos
	for q in pillars:
		var c: Vector2 = q["pos"]
		var rr: float = float(q["r"]) + r
		var d := p - c
		var dl := d.length()
		if dl < rr and dl > 0.001:
			p = c + d / dl * rr
		elif dl <= 0.001:
			p = c + Vector2(rr, 0)
	var inner := inner_rect()
	p.x = clampf(p.x, inner.position.x + r, inner.end.x - r)
	p.y = clampf(p.y, inner.position.y + r, inner.end.y - r)
	return p


## 障碍绕行：dir 方向被立柱挡住时返回沿柱面切线的方向。
## 敌人原本是纯直线追踪，撞上柱子就顶在那里不动（"被障碍挡住"的根因）。
var pathing_enabled := true
var flow_enabled := true


# ---------------------------------------------------------------- 流场寻路
## 纯直线追踪遇到长墙时，敌人会一直顶着墙——即使绕过去就有路。
## 这里从玩家位置做一次 BFS，得到全场的"往哪走"方向场，
## 敌人只需查表。O(格子数)/次重建，与敌人数无关（190 个敌人也只算一次）。
const FLOW_CELL := 36.0
const _DX := [1, -1, 0, 0, 1, 1, -1, -1]
const _DZ := [0, 0, 1, -1, 1, -1, 1, -1]

var _fw := 0
var _fh := 0
var _blocked := PackedByteArray()
var _dist := PackedInt32Array()
var _flow := PackedVector2Array()
var _flow_ready := false
var _flow_at := Vector2(-99999.0, -99999.0)
var _flow_usec := 0
var _flow_builds := 0


func _flow_init() -> void:
	_fw = int(ceil(arena_size.x / FLOW_CELL))
	_fh = int(ceil(arena_size.y / FLOW_CELL))
	var n := _fw * _fh
	_blocked.resize(n)
	_dist.resize(n)
	_flow.resize(n)
	_blocked.fill(0)
	# 把每根柱子的包围盒"盖章"进网格，而不是逐格做碰撞检测
	for q in pillars:
		var c: Vector2 = q["pos"]
		# 膨胀量必须很小：+11 会把 150px 的通道口封死，
		# 导致墙对面的格子全被判为"不可达"（实测 9/12 敌人卡死的原因）
		var rr: float = float(q["r"]) + 2.0
		var x0 := clampi(int((c.x - rr) / FLOW_CELL), 0, _fw - 1)
		var x1 := clampi(int((c.x + rr) / FLOW_CELL), 0, _fw - 1)
		var z0 := clampi(int((c.y - rr) / FLOW_CELL), 0, _fh - 1)
		var z1 := clampi(int((c.y + rr) / FLOW_CELL), 0, _fh - 1)
		for z in range(z0, z1 + 1):
			for x in range(x0, x1 + 1):
				var p := Vector2((float(x) + 0.5) * FLOW_CELL, (float(z) + 0.5) * FLOW_CELL)
				if p.distance_to(c) <= rr:
					_blocked[z * _fw + x] = 1


func flow_target() -> Vector2:
	if not _flow_ready:
		return Vector2.INF
	return _flow_at


## 玩家移动超过一格或超时才重建，避免每帧重算
func update_flow(target: Vector2, force: bool = false) -> void:
	if _fw == 0:
		_flow_init()
	if not force and _flow_ready and target.distance_to(_flow_at) < FLOW_CELL:
		return
	_flow_at = target
	_flow_ready = true
	var _t0 := Time.get_ticks_usec()
	_dist.fill(-1)
	var tx := clampi(int(target.x / FLOW_CELL), 0, _fw - 1)
	var tz := clampi(int(target.y / FLOW_CELL), 0, _fh - 1)
	var start := tz * _fw + tx
	if _blocked[start] == 1:
		var found := -1
		for r in range(1, 8):
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					var nx := tx + dx
					var nz := tz + dz
					if nx < 0 or nz < 0 or nx >= _fw or nz >= _fh:
						continue
					if _blocked[nz * _fw + nx] == 0:
						found = nz * _fw + nx
						break
				if found >= 0:
					break
			if found >= 0:
				break
		if found < 0:
			return
		start = found
	var q := PackedInt32Array()
	q.resize(_fw * _fh)
	var qn := 0
	q[qn] = start
	qn += 1
	_dist[start] = 0
	var head := 0
	while head < qn:
		var ci := q[head]
		head += 1
		var cx := ci % _fw
		var cz := ci / _fw
		var nd := _dist[ci] + 1
		for k in 8:
			var nx2 := cx + int(_DX[k])
			var nz2 := cz + int(_DZ[k])
			if nx2 < 0 or nz2 < 0 or nx2 >= _fw or nz2 >= _fh:
				continue
			var ni := nz2 * _fw + nx2
			if _blocked[ni] == 1 or _dist[ni] >= 0:
				continue
			_dist[ni] = nd
			q[qn] = ni
			qn += 1
	# 方向：指向距离更小的邻居，再做两轮 3x3 平滑（粗网格否则会有方格感）
	for z in _fh:
		for x in _fw:
			var ci2 := z * _fw + x
			if _blocked[ci2] == 1 or _dist[ci2] < 0:
				_flow[ci2] = Vector2.ZERO
				continue
			var bd := _dist[ci2]
			var bv := Vector2.ZERO
			for k2 in 8:
				var ax := x + int(_DX[k2])
				var az := z + int(_DZ[k2])
				if ax < 0 or az < 0 or ax >= _fw or az >= _fh:
					continue
				var ai := az * _fw + ax
				if _blocked[ai] == 1 or _dist[ai] < 0:
					continue
				if _dist[ai] < bd:
					bd = _dist[ai]
					bv = Vector2(float(_DX[k2]), float(_DZ[k2]))
			_flow[ci2] = bv.normalized() if bv != Vector2.ZERO else Vector2.ZERO
	# 不做空间平滑：3x3 两轮平滑是这里最贵的一段（约占重建耗时一半），
	# 而 GDScript 逐格开销很大，改用"方向分歧阈值"在 Enemy 侧抑制抖动。
	_flow_builds += 1
	_flow_usec = Time.get_ticks_usec() - _t0


## 查表：该位置应该往哪个方向走（已归一化）。不可达时返回 ZERO。
func flow_at(pos: Vector2) -> Vector2:
	if not _flow_ready:
		return Vector2.ZERO
	var cx := clampi(int(pos.x / FLOW_CELL), 0, _fw - 1)
	var cz := clampi(int(pos.y / FLOW_CELL), 0, _fh - 1)
	return _flow[cz * _fw + cx]


## 该点是否可达（存在通往玩家的通路）
func flow_reaches(pos: Vector2) -> bool:
	if not _flow_ready:
		return false
	var cx := clampi(int(pos.x / FLOW_CELL), 0, _fw - 1)
	var cz := clampi(int(pos.y / FLOW_CELL), 0, _fh - 1)
	return _dist[cz * _fw + cx] >= 0


## 找出前方真正挡路的柱子（无则返回 Vector2.INF）
func blocker_ahead(from: Vector2, dir: Vector2, r: float) -> Vector2:
	var probe: Vector2 = from + dir * (r + 16.0)
	if not hits_pillar(probe, r):
		return Vector2.INF
	var best := Vector2.INF
	var best_d := 1e9
	for q in pillars:
		var c: Vector2 = q["pos"]
		var rr: float = float(q["r"])
		var to_c := c - from
		if to_c.dot(dir) <= 0.0:
			continue
		var d := to_c.length()
		if d > rr + r + 70.0:
			continue
		if d < best_d:
			best_d = d
			best = c
	return best


## 沿柱面切线绕行。side 由调用方**选定一次并坚持**，
## 否则切线会在柱子两侧来回翻转，敌人绕着柱子转圈（实测到达率反而下降）。
func slide_around(from: Vector2, dir: Vector2, blocker: Vector2, side: float,
		r: float) -> Vector2:
	var away := from - blocker
	away = away.normalized() if away.length() > 0.001 else Vector2(1.0, 0.0)
	var tangent := Vector2(-away.y, away.x) * signf(side)
	if tangent.dot(dir) < 0.0:
		tangent = -tangent
	var d: float = (blocker - from).length()
	var push: float = clampf(1.0 - (d - r) / 46.0, 0.45, 0.95)
	return (tangent * push + dir * (1.0 - push)).normalized()


func hits_pillar(pos: Vector2, r: float) -> bool:
	for q in pillars:
		var rr: float = float(q["r"]) + r
		if pos.distance_squared_to(q["pos"]) < rr * rr:
			return true
	return false
