extends Node
## 全局状态机 + 当前关卡 + 工坊加成。

const ST_MENU := 0
const ST_STAGE_SELECT := 1
const ST_PLAYING := 2
const ST_PAUSED := 3
const ST_LEVELUP := 4
const ST_RESULT := 5
const ST_WORKSHOP := 6
const ST_SETTINGS := 7

var state: int = ST_MENU
var world = null
var stage_idx := 0
var endless := false
var last_result: Dictionary = {}
var rng := RandomNumberGenerator.new()

var _wcache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	rng.randomize()


func change_state(s: int) -> void:
	state = s
	Bus.game_state_changed.emit(s)


func is_playing() -> bool:
	return state == ST_PLAYING or state == ST_LEVELUP


## 工坊永久加成（每局开局生效）
func workshop_bonus() -> Dictionary:
	var hp_add := 0.0
	var dmg := 0.0
	var spd := 0.0
	var luck := 0.0
	var magnet := 0.0
	var xp := 0.0
	var armor := 0.0
	var revives := 0
	for item in DB.WORKSHOP:
		var lv := Save.workshop_level(item["id"])
		if lv <= 0:
			continue
		match item["id"]:
			"w_hp": hp_add = lv * 12.0
			"w_dmg": dmg = lv * 0.05
			"w_spd": spd = lv * 0.04
			"w_luck": luck = lv * 0.15
			"w_magnet": magnet = lv * 0.15
			"w_xp": xp = lv * 0.07
			"w_armor": armor = lv * 0.06
			"w_revive": revives = int(floor(lv / 2.0))
	return {
		"hp_add": hp_add, "dmg": dmg, "speed": spd, "luck": luck,
		"magnet": magnet, "xp": xp, "armor": armor, "revives": revives,
	}


func apply_settings() -> void:
	var fs := bool(Save.setting("fullscreen", false))
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_FULLSCREEN if fs else DisplayServer.WINDOW_MODE_WINDOWED)
	Audio.refresh_volumes()


func quit() -> void:
	Save.save_game()
	get_tree().quit(0)
