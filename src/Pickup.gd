class_name Pickup
extends Node2D
## 掉落物：经验宝石 / 齿轮 / 血包 / 宝箱。

var kind := "xp"
var value := 1
var vel := Vector2.ZERO
var attracted := false
var life := 999.0
var t := 0.0
var anim: AnimatedSprite2D
var _rng := RandomNumberGenerator.new()

const RADII := {"xp": 8.0, "gear": 9.0, "hp": 11.0, "chest": 14.0,
	"shield": 12.0, "pulse": 12.0, "timechip": 12.0, "rage": 12.0}
const NAMES := {"xp": "经验", "gear": "齿轮", "hp": "医疗包", "chest": "宝箱",
	"shield": "护盾电池", "pulse": "脉冲炸弹", "timechip": "时缓芯片", "rage": "狂暴剂"}


static func spawn(parent: Node, kind_: String, value_: int, pos: Vector2) -> Pickup:
	var p := Pickup.new()
	p.kind = kind_
	p.value = value_
	p.global_position = pos
	p.z_index = 2
	var a := AnimatedSprite2D.new()
	a.sprite_frames = Art.frames("pickup_" + kind_, 8.0, true)
	a.animation = "anim"
	a.play("anim")
	if kind_ == "chest":
		a.sprite_frames = Art.frames("pickup_chest", 6.0, true)
	p.anim = a
	p.add_child(a)
	parent.add_child(p)
	return p


func radius() -> float:
	return RADII.get(kind, 8.0)


func _ready() -> void:
	_rng.randomize()
	var ang := _rng.randf() * TAU
	vel = Vector2(cos(ang), sin(ang)) * _rng.randf_range(30.0, 80.0)
	if kind == "chest":
		vel = Vector2.ZERO
		life = 40.0


func _process(delta: float) -> void:
	t += delta
	if kind == "chest":
		return
	var world = Game.world
	if world == null:
		return
	var pl = world.player
	# 摩擦
	vel *= 1.0 - 3.0 * delta
	if pl != null and is_instance_valid(pl) and not pl.dead:
		var d: float = global_position.distance_to(pl.global_position)
		var pr: float = pl.pickup_radius()
		if d < pr:
			attracted = true
		if attracted:
			var dir: Vector2 = (pl.global_position - global_position).normalized()
			var sp := clampf(420.0 - d, 120.0, 460.0)
			global_position += dir * sp * delta
	position += vel * delta
	if t > life:
		queue_free()
