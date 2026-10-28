extends Node
## 从 atlas.json 读取程序化生成的像素图，按名字提供 Texture / SpriteFrames。

const DIR := "res://assets/art/"
const FONT_PATH := "res://assets/fonts/NotoSansSC-VF.ttf"
const FONT_FALLBACK := "res://assets/fonts/simhei.ttf"

var _pages: Array = []
var _anim: Dictionary = {}
var _cache: Dictionary = {}
var font: FontFile = null


func _ready() -> void:
	var f := FileAccess.open(DIR + "atlas.json", FileAccess.READ)
	if f == null:
		push_error("atlas.json missing - run tools/gen_art.py")
		return
	var meta: Variant = JSON.parse_string(f.get_as_text())
	if typeof(meta) != TYPE_DICTIONARY:
		push_error("atlas.json malformed")
		return
	for p in meta["pages"]:
		var t: Texture2D = load(DIR + String(p))
		_pages.append(t)
	_anim = meta["anim"]
	if ResourceLoader.exists(FONT_PATH):
		font = load(FONT_PATH)
	elif ResourceLoader.exists(FONT_FALLBACK):
		font = load(FONT_FALLBACK)


func has(n: String) -> bool:
	return _anim.has(n)


func region(n: String, i: int = 0) -> Rect2:
	var a: Dictionary = _anim[n]
	var fr: Array = a["frames"]
	var k: int = i % fr.size()
	return Rect2(float(fr[k][0]), float(fr[k][1]), float(a["w"]), float(a["h"]))


func size_of(n: String) -> Vector2:
	var a: Dictionary = _anim[n]
	return Vector2(float(a["w"]), float(a["h"]))


func tex(n: String, i: int = 0) -> AtlasTexture:
	var key := n + "#" + str(i)
	if _cache.has(key):
		return _cache[key]
	var at := AtlasTexture.new()
	at.atlas = _pages[int(_anim[n]["page"])]
	at.region = region(n, i)
	at.filter_clip = true
	_cache[key] = at
	return at


func frames(n: String, fps: float = 8.0, loop: bool = true) -> SpriteFrames:
	var key := "SF|%s|%s|%s" % [n, fps, loop]
	if _cache.has(key):
		return _cache[key]
	var a: Dictionary = _anim[n]
	var count: int = a["frames"].size()
	var sf := SpriteFrames.new()
	sf.remove_animation("default")
	sf.add_animation("anim")
	sf.set_animation_loop("anim", loop)
	sf.set_animation_speed("anim", fps)
	for i in count:
		sf.add_frame("anim", tex(n, i))
	_cache[key] = sf
	return sf


func sprite(n: String, i: int = 0) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex(n, i)
	return s


func anim_node(n: String, fps: float = 8.0, loop: bool = true) -> AnimatedSprite2D:
	var a := AnimatedSprite2D.new()
	a.sprite_frames = frames(n, fps, loop)
	a.animation = "anim"
	return a


## 单帧精灵（无动画），用于静态装饰
func tile_tex(n: String) -> Texture2D:
	return tex(n, 0)
