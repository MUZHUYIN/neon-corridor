extends Node
## 全部游戏数据表。加武器/敌人/关卡 = 加一行数据，不用改系统代码。

enum AI { CHASE, RANGED, EXPLODE, SPLIT, SUMMON }

const MAX_WEAPONS := 3

# ---------------------------------------------------------------- 武器
const WEAPONS := [
	{
		"id": "pistol", "name": "脉冲手枪", "icon": "icon_w_pistol",
		"desc": "节奏稳定的能量弹，射程与手感都很均衡。",
		"cd": 0.40, "dmg": 7.0, "count": 1, "spread": 0.0, "speed": 400.0,
		"proj": "proj_pistol", "pierce": 0, "life": 1.0, "knock": 70.0,
		"sfx": "sfx_shoot_pistol", "recoil": 1.8, "extra": [0, 0, 1, 1, 1],
		"evo_with": "firerate", "evo_name": "湮灭脉冲",
		"evo_desc": "三连发，弹丸穿透 2 个敌人",
		"evo": {"count": 3, "pierce": 2, "dmg": 9.0, "cd": 0.30, "spread": 0.10, "spread_fan": true},
	},
	{
		"id": "shotgun", "name": "散射霰弹", "icon": "icon_w_shotgun",
		"desc": "贴脸伤害爆表，远距离衰减明显。",
		"cd": 1.05, "dmg": 5.0, "count": 5, "spread": 0.55, "speed": 330.0,
		"proj": "proj_shotgun", "pierce": 0, "life": 0.46, "knock": 180.0,
		"sfx": "sfx_shoot_shotgun", "recoil": 5.0, "extra": [0, 1, 1, 2, 2],
		"evo_with": "damage", "evo_name": "撕裂者",
		"evo_desc": "弹丸数变为 9，附带强力击退",
		"evo": {"count": 9, "spread": 0.8, "dmg": 7.0, "knock": 420.0, "life": 0.46},
	},
	{
		"id": "laser", "name": "穿刺激光", "icon": "icon_w_laser",
		"desc": "瞬间贯穿一整条直线上的敌人。",
		"cd": 0.90, "dmg": 9.5, "count": 1, "spread": 0.0, "speed": 760.0,
		"proj": "proj_laser", "pierce": 99, "life": 0.85, "knock": 40.0,
		"beam": true, "beam_len": 820.0, "beam_width": 15.0,
		"sfx": "sfx_shoot_laser", "recoil": 1.2, "extra": [0, 0, 0, 1, 1],
		"evo_with": "crit", "evo_name": "湮灭射线",
		"evo_desc": "双束并射，暴击必定触发",
		"evo": {"count": 2, "spread": 0.09, "dmg": 13.0, "life": 1.0,
			"always_crit": true, "beam_width": 20.0, "beam_len": 980.0},
	},
	{
		"id": "boomerang", "name": "回旋刃", "icon": "icon_w_boomerang",
		"desc": "飞出去还会飞回来，来回都能造成伤害。",
		"cd": 1.45, "dmg": 14.0, "count": 1, "spread": 0.0, "speed": 300.0,
		"proj": "proj_boomerang", "pierce": 99, "life": 1.3, "knock": 90.0,
		"sfx": "sfx_shoot_boomerang", "recoil": 0.0, "extra": [0, 0, 1, 1, 2],
		"boomerang": true,
		"evo_with": "speed", "evo_name": "量子之轮",
		"evo_desc": "三枚巨轮绕身旋转，持续切割",
		"evo": {"count": 3, "spread": 2.09, "dmg": 16.0, "orbit": true, "life": 2.2},
	},
	{
		"id": "orb", "name": "电弧球", "icon": "icon_w_orb",
		"desc": "缓慢追踪的电浆球，命中时炸开。",
		"cd": 1.55, "dmg": 11.0, "count": 1, "spread": 0.0, "speed": 190.0,
		"proj": "proj_orb", "pierce": 0, "life": 2.6, "knock": 60.0,
		"sfx": "sfx_shoot_orb", "recoil": 0.8, "extra": [0, 0, 1, 1, 1],
		"homing": 2.4, "aoe": 40.0,
		"evo_with": "shield", "evo_name": "湮灭奇点",
		"evo_desc": "爆炸后分裂出 3 颗追踪子弹",
		"evo": {"dmg": 15.0, "aoe": 58.0, "aoe_split": 3, "homing": 3.6},
	},
	{
		"id": "rocket", "name": "微型火箭", "icon": "icon_w_rocket",
		"desc": "高伤害范围的爆炸，清群首选。",
		"cd": 1.85, "dmg": 22.0, "count": 1, "spread": 0.0, "speed": 300.0,
		"proj": "proj_rocket", "pierce": 0, "life": 1.6, "knock": 200.0,
		"sfx": "sfx_shoot_rocket", "recoil": 4.0, "extra": [0, 0, 0, 1, 1],
		"aoe": 44.0,
		"evo_with": "magnet", "evo_name": "饱和轰炸",
		"evo_desc": "三发齐射，爆炸范围大幅提升",
		"evo": {"count": 3, "spread": 0.5, "aoe": 74.0, "dmg": 26.0},
	},
]

# ---------------------------------------------------------------- 被动
const PASSIVES := [
	{"id": "speed", "name": "推进器", "icon": "icon_p_speed", "desc": "移动速度 +8%", "per": 0.08},
	{"id": "firerate", "name": "超频回路", "icon": "icon_p_firerate", "desc": "射击速度 +9%", "per": 0.09},
	{"id": "damage", "name": "增幅核心", "icon": "icon_p_damage", "desc": "全部伤害 +11%", "per": 0.11},
	{"id": "crit", "name": "弱点分析", "icon": "icon_p_crit", "desc": "暴击率 +6%，暴击伤害 +10%", "per": 0.06},
	{"id": "regen", "name": "纳米修复", "icon": "icon_p_regen", "desc": "每秒回复 0.6 生命", "per": 0.6},
	{"id": "magnet", "name": "磁力场", "icon": "icon_p_magnet", "desc": "拾取范围 +22%", "per": 0.22},
	{"id": "shield", "name": "护盾发生器", "icon": "icon_p_shield", "desc": "最大生命 +14", "per": 14.0},
	{"id": "xp", "name": "经验解析", "icon": "icon_p_xp", "desc": "经验获取 +10%", "per": 0.10},
]

# ---------------------------------------------------------------- 敌人
const ENEMIES := [
	{"id": "grunt", "name": "游荡者", "sprite": "enemy_grunt", "hp": 16.0, "speed": 54.0,
	 "dmg": 7.0, "xp": 1, "r": 9.0, "ai": AI.CHASE, "gears": 1, "eye": true},
	{"id": "darter", "name": "疾影", "sprite": "enemy_darter", "hp": 11.0, "speed": 78.0,
	 "dmg": 5.0, "xp": 1, "r": 9.0, "ai": AI.CHASE, "gears": 1, "eye": true},
	{"id": "runner", "name": "游猎者", "sprite": "enemy_darter", "hp": 26.0, "speed": 62.0,
	 "dmg": 8.0, "xp": 2, "r": 10.0, "ai": AI.CHASE, "gears": 2, "eye": true},
	{"id": "lancer", "name": "投矛者", "sprite": "enemy_lancer", "hp": 26.0, "speed": 38.0,
	 "dmg": 7.0, "xp": 2, "r": 10.0, "ai": AI.RANGED, "gears": 2,
	 "shoot_cd": 2.0, "shoot_range": 210.0, "eproj": "eproj_shard", "eproj_speed": 190.0},
	{"id": "bomber", "name": "爆裂虫", "sprite": "enemy_bomber", "hp": 22.0, "speed": 48.0,
	 "dmg": 20.0, "xp": 2, "r": 10.0, "ai": AI.EXPLODE, "gears": 2, "boom_r": 46.0},
	{"id": "splitter", "name": "分裂体", "sprite": "enemy_splitter", "hp": 34.0, "speed": 48.0,
	 "dmg": 9.0, "xp": 3, "r": 11.0, "ai": AI.CHASE, "gears": 3, "split_into": "grunt", "split_n": 2},
	{"id": "flyer", "name": "浮游炮", "sprite": "enemy_flyer", "hp": 20.0, "speed": 66.0,
	 "dmg": 8.0, "xp": 2, "r": 11.0, "ai": AI.CHASE, "gears": 2},
	{"id": "tank", "name": "重甲机兵", "sprite": "enemy_tank", "hp": 92.0, "speed": 32.0,
	 "dmg": 14.0, "xp": 5, "r": 14.0, "ai": AI.CHASE, "gears": 5, "armor": 3.0},
	{"id": "summoner", "name": "召唤者", "sprite": "enemy_summoner", "hp": 48.0, "speed": 34.0,
	 "dmg": 6.0, "xp": 6, "r": 12.0, "ai": AI.SUMMON, "gears": 6,
	 "summon_cd": 5.5, "summon_kind": "grunt", "summon_n": 3, "keep_dist": 190.0},
]

# 精英词缀
const ELITES := [
	{"id": "rage", "name": "狂暴", "hp": 1.9, "speed": 1.35, "dmg": 1.3, "scale": 1.12, "xp": 3.0},
	{"id": "shielded", "name": "护盾", "hp": 2.6, "speed": 0.9, "dmg": 1.0, "scale": 1.15, "xp": 3.5},
	{"id": "mutant", "name": "畸变", "hp": 2.2, "speed": 1.1, "dmg": 1.2, "scale": 1.3, "xp": 4.0},
]

# ---------------------------------------------------------------- BOSS
const BOSSES := [
	{"id": "boss_0", "name": "锈蚀之心", "sprite": "boss_0", "hp": 2100.0, "speed": 34.0,
	 "dmg": 16.0, "r": 34.0, "gears": 140, "patterns": ["radial", "charge", "radial"]},
	{"id": "boss_1", "name": "数据吞噬者", "sprite": "boss_1", "hp": 2700.0, "speed": 42.0,
	 "dmg": 18.0, "r": 34.0, "gears": 220, "patterns": ["spiral", "summon", "radial", "charge"]},
	{"id": "boss_2", "name": "熔核暴君", "sprite": "boss_2", "hp": 3400.0, "speed": 46.0,
	 "dmg": 20.0, "r": 36.0, "gears": 340, "patterns": ["radial", "spiral", "charge", "ring_wall"]},
]

# ---------------------------------------------------------------- 升级池按关卡解锁
const WEAPON_MIN_STAGE := {"pistol": 0, "shotgun": 0, "laser": 0, "boomerang": 1, "orb": 1, "rocket": 2}
const PASSIVE_MIN_STAGE := {"speed": 0, "damage": 0, "magnet": 0, "shield": 0,
	"firerate": 1, "crit": 1, "regen": 1, "xp": 2}

# ---------------------------------------------------------------- 主动技能
## 设计约束：长冷却、偏保命不偏输出。技能一旦能当输出循环用，
## 游戏就会从"走位生存"变成"等 CD 放技能"，张力消失。
const SKILLS := [
	{"id": "shockwave", "name": "冲击波", "icon": "icon_s_shock",
	 "desc": "以自身为中心爆开环形冲击：伤害并击退周围敌人、清空敌方子弹，自身短暂无敌。",
	 "cd": 11.0, "dmg": 40.0, "radius": 190.0, "knock": 520.0, "iframe": 0.55},
	{"id": "shieldfield", "name": "护盾力场", "icon": "icon_s_shield",
	 "desc": "获得可吸收 90 点伤害的护盾，持续 8 秒。",
	 "cd": 16.0, "amount": 90.0, "duration": 8.0},
	{"id": "phase", "name": "相位突进", "icon": "icon_s_phase",
	 "desc": "3 秒内无敌、穿透敌人，移动速度 +30%。",
	 "cd": 20.0, "duration": 3.0, "speed": 0.30},
	{"id": "slowfield", "name": "时滞场", "icon": "icon_s_slow",
	 "desc": "周围敌人减速 65%，持续 4.5 秒。",
	 "cd": 18.0, "radius": 270.0, "slow": 0.35, "duration": 4.5},
]
const MAX_SKILLS := 2
## 开局自带技能的难度（索引对应 DIFFICULTY；-1 = 不带）
const SKILL_START_DIFFICULTY := {"easy": -1, "normal": -1, "hard": 0}

# ---------------------------------------------------------------- 环境危害
const HAZARDS := {
	"laser_gate": {"warn": 0.95, "active": 1.6, "dmg": 14.0, "width": 7.0},
	"storm_zone": {"warn": 1.1, "active": 5.5, "dmg": 6.5, "radius": 98.0, "slow": 0.55},
	"lava_vent": {"warn": 1.25, "active": 0.75, "dmg": 20.0, "radius": 54.0, "burn": 2.6, "burn_dmg": 5.0},
	"laser_arm": {"dmg": 13.0, "width": 6.0, "spin": 0.55},
	"corro": {"dmg": 4.0, "radius": 34.0, "life": 1.8},
}

# ---------------------------------------------------------------- 难度
## 倍率说明：ehp 敌人生命 / edmg 敌人伤害 / erate 刷怪速度 / max_alive 同屏上限
##          elite 精英率 / hazard 环境危害频率 / taken 玩家受伤 / gears 齿轮收益
const DIFFICULTY := [
	{"id": "easy", "name": "简单", "desc": "敌人更少、更软，环境干扰更轻。先熟悉玩法。",
	 "ehp": 0.72, "edmg": 0.60, "erate": 0.68, "max_alive": 120, "elite": 0.55,
	 "hazard": 0.70, "taken": 0.75, "gears": 0.75},
	{"id": "normal", "name": "普通", "desc": "标准体验。",
	 "ehp": 1.00, "edmg": 1.00, "erate": 1.00, "max_alive": 165, "elite": 1.00,
	 "hazard": 1.00, "taken": 1.00, "gears": 1.00},
	{"id": "hard", "name": "困难", "desc": "敌人更多更硬，危害更频繁，但齿轮收益高 50%。",
	 "ehp": 1.35, "edmg": 1.35, "erate": 1.28, "max_alive": 215, "elite": 1.55,
	 "hazard": 1.35, "taken": 1.28, "gears": 1.50},
]


func difficulty(idx: int) -> Dictionary:
	return DIFFICULTY[clampi(idx, 0, DIFFICULTY.size() - 1)]


# ---------------------------------------------------------------- 每局随机修正
const RUN_MODS := [
	{"id": "hunt", "name": "猎杀", "desc": "精英出现率 +80%，齿轮 +50%", "elite": 0.80, "gears": 0.50},
	{"id": "frail", "name": "贫血", "desc": "最大生命 -25%，伤害 +30%", "hp": -0.25, "dmg": 0.30},
	{"id": "swift", "name": "疾行", "desc": "敌人移速 +20%，刷怪 -20%", "espeed": 0.20, "erate": -0.20},
	{"id": "swarm", "name": "蜂群", "desc": "刷怪 +50%，敌人生命 -30%", "erate": 0.50, "ehp": -0.30},
	{"id": "glass", "name": "玻璃大炮", "desc": "受伤 +50%，暴击率 +25%", "taken": 0.50, "crit": 0.25},
	{"id": "rich", "name": "富矿", "desc": "齿轮 +100%，敌人生命 +25%", "gears": 1.00, "ehp": 0.25},
	{"id": "fog", "name": "迷雾", "desc": "视野收紧，敌人生命 -20%", "zoom": 0.18, "ehp": -0.20},
	{"id": "wall", "name": "铁壁", "desc": "敌人生命 +40%，刷怪 -25%", "ehp": 0.40, "erate": -0.25},
	{"id": "blood", "name": "血怒", "desc": "伤害 +20%，受伤 +25%", "dmg": 0.20, "taken": 0.25},
]

# ---------------------------------------------------------------- 局内事件
const EVENTS := [
	{"id": "airdrop", "name": "补给空投", "desc": "空投已抵达"},
	{"id": "elite_squad", "name": "精英小队", "desc": "检测到 6 个精英信号"},
	{"id": "bounty", "name": "猎杀悬赏", "desc": "标记目标已出现"},
	{"id": "calm", "name": "静默期", "desc": "10 秒内不再刷新敌人"},
	{"id": "surge", "name": "能量涌动", "desc": "敌人攻势短暂加强"},
]

# ---------------------------------------------------------------- 关卡
const STAGES := [
	{
		"name": "霓虹走廊", "theme": 0, "bgm": "bgm_stage1",
		"desc": "废弃的运输通道，成群的低级守卫。",
		"layout": "cross", "tagline": "开阔的十字通道",
		"flags": {},
		"hazards": [{"kind": "laser_gate", "from": 45.0, "every": 24.0}],
		"duration": 240.0, "hp_mult": 1.0, "rate_mult": 1.0, "elite_at": 165.0,
		"phases": [
			{"t": 0.0, "rate": 1.0, "pool": ["grunt"]},
			{"t": 30.0, "rate": 1.3, "pool": ["grunt", "darter"]},
			{"t": 65.0, "rate": 1.6, "pool": ["grunt", "darter", "flyer"]},
			{"t": 100.0, "rate": 1.9, "pool": ["grunt", "darter", "lancer", "flyer"]},
			{"t": 140.0, "rate": 2.2, "pool": ["darter", "lancer", "bomber", "splitter"]},
			{"t": 175.0, "rate": 2.6, "pool": ["grunt", "bomber", "splitter", "tank"]},
			{"t": 205.0, "rate": 3.2, "pool": ["bomber", "splitter", "tank", "summoner"], "elite": 0.22},
			{"t": 228.0, "rate": 0.4, "pool": ["grunt"], "phase": "喘口气，补给来了"},
		],
	},
	{
		"name": "数据荒原", "theme": 1, "bgm": "bgm_stage2",
		"desc": "失控的数据碎片在这里聚成实体。",
		"layout": "ring", "tagline": "环形竞技场 · 敌人会传送 · 死亡留腐蚀区",
		"flags": {"corrosive_death": true, "teleport": true},
		"hazards": [{"kind": "storm_zone", "from": 30.0, "every": 15.0}],
		"duration": 240.0, "hp_mult": 1.32, "rate_mult": 1.00, "elite_at": 150.0,
		"phases": [
			{"t": 0.0, "rate": 1.2, "pool": ["grunt", "runner"]},
			{"t": 30.0, "rate": 1.6, "pool": ["grunt", "runner", "flyer"]},
			{"t": 65.0, "rate": 1.9, "pool": ["runner", "flyer", "lancer", "bomber"]},
			{"t": 100.0, "rate": 2.3, "pool": ["flyer", "lancer", "bomber", "splitter", "runner"]},
			{"t": 135.0, "rate": 2.3, "pool": ["bomber", "splitter", "tank", "summoner"]},
			{"t": 170.0, "rate": 2.7, "pool": ["runner", "splitter", "tank", "summoner", "flyer"], "elite": 0.16},
			{"t": 205.0, "rate": 3.1, "pool": ["splitter", "tank", "summoner", "bomber"], "elite": 0.30},
			{"t": 228.0, "rate": 0.5, "pool": ["grunt"], "phase": "喘口气，补给来了"},
		],
	},
	{
		"name": "核心反应堆", "theme": 2, "bgm": "bgm_stage3",
		"desc": "整座设施的熔核。撑住，暴君就在里面。",
		"layout": "open", "tagline": "熔岩喷口 · 旋转激光臂 · 敌人带护盾且残血自爆",
		"flags": {"shielded": true, "death_explode": true},
		"hazards": [{"kind": "lava_vent", "from": 25.0, "every": 12.0},
			{"kind": "laser_arm", "from": 20.0, "every": 0.0}],
		"duration": 240.0, "hp_mult": 1.85, "rate_mult": 1.30, "elite_at": 130.0,
		"phases": [
			{"t": 0.0, "rate": 1.4, "pool": ["grunt", "darter", "flyer"]},
			{"t": 30.0, "rate": 1.9, "pool": ["darter", "flyer", "bomber"]},
			{"t": 65.0, "rate": 2.3, "pool": ["flyer", "bomber", "lancer", "splitter"]},
			{"t": 100.0, "rate": 2.8, "pool": ["bomber", "splitter", "tank", "lancer"]},
			{"t": 135.0, "rate": 2.9, "pool": ["splitter", "tank", "summoner", "flyer"], "elite": 0.18},
			{"t": 170.0, "rate": 3.4, "pool": ["tank", "summoner", "splitter", "bomber"], "elite": 0.32},
			{"t": 205.0, "rate": 3.8, "pool": ["tank", "summoner", "splitter", "bomber", "darter"], "elite": 0.45},
			{"t": 228.0, "rate": 0.6, "pool": ["grunt"], "phase": "喘口气，暴君要来了"},
		],
	},
]

# ---------------------------------------------------------------- 工坊（永久升级）
const WORKSHOP := [
	{"id": "w_hp", "name": "强化装甲板", "icon": "icon_m_heart", "desc": "起始生命 +12", "costs": [20, 45, 90, 170, 300]},
	{"id": "w_dmg", "name": "火药改良", "icon": "icon_p_damage", "desc": "全部伤害 +5%", "costs": [25, 55, 110, 200, 340]},
	{"id": "w_spd", "name": "轻量合金", "icon": "icon_p_speed", "desc": "移动速度 +4%", "costs": [20, 45, 90, 170, 300]},
	{"id": "w_luck", "name": "幸运齿轮", "icon": "icon_m_gear", "desc": "齿轮获取 +15%", "costs": [25, 55, 110, 200, 340]},
	{"id": "w_magnet", "name": "引力线圈", "icon": "icon_p_magnet", "desc": "拾取范围 +15%", "costs": [20, 45, 90, 170, 300]},
	{"id": "w_xp", "name": "数据解析器", "icon": "icon_p_xp", "desc": "经验获取 +7%", "costs": [30, 65, 130, 230, 380]},
	{"id": "w_armor", "name": "复合涂层", "icon": "icon_p_shield", "desc": "受到伤害 -6%", "costs": [30, 65, 130, 230, 380]},
	{"id": "w_revive", "name": "备用机体", "icon": "icon_m_clock", "desc": "每局多 1 次复活（每 2 级）", "costs": [60, 140, 260, 430, 650]},
]

# ---------------------------------------------------------------- 常量
const PICKUP_RADIUS := 34.0
const BASE_HP := 120.0
const BASE_SPEED := 128.0
const DASH_SPEED := 400.0
const DASH_TIME := 0.18
const DASH_CD := 2.2
const MAX_ALIVE := 220

var _w: Dictionary = {}
var _p: Dictionary = {}
var _e: Dictionary = {}
var _s: Dictionary = {}
var _k: Dictionary = {}


func _ready() -> void:
	for x in WEAPONS:
		_w[x["id"]] = x
	for x in PASSIVES:
		_p[x["id"]] = x
	for x in ENEMIES:
		_e[x["id"]] = x
	for x in WORKSHOP:
		_k[x["id"]] = x
	_s = {}


func weapon(id: String) -> Dictionary:
	return _w[id]


func weapon_ok(id: String, stage_idx: int) -> bool:
	return int(WEAPON_MIN_STAGE.get(id, 0)) <= stage_idx


func passive_ok(id: String, stage_idx: int) -> bool:
	return int(PASSIVE_MIN_STAGE.get(id, 0)) <= stage_idx


func skill(id: String) -> Dictionary:
	for s in SKILLS:
		if String(s["id"]) == id:
			return s
	return {}


func hazard(kind: String) -> Dictionary:
	return HAZARDS.get(kind, {})


func run_mod(id: String) -> Dictionary:
	for m in RUN_MODS:
		if String(m["id"]) == id:
			return m
	return {}


func passive(id: String) -> Dictionary:
	return _p[id]


func enemy(id: String) -> Dictionary:
	return _e[id]


func workshop_item(id: String) -> Dictionary:
	return _k[id]


func stage(i: int) -> Dictionary:
	return STAGES[clampi(i, 0, STAGES.size() - 1)]


## 把升级选项翻译成 UI 文案
func describe_choice(c: Dictionary, player) -> Dictionary:
	var t := String(c["type"])
	var id := String(c["id"])
	var out := {"tag": "", "name": "", "desc": "", "icon": "", "color": Color("ffffff")}
	match t:
		"weapon_new":
			var d: Dictionary = weapon(id)
			out["tag"] = "新武器"
			out["name"] = String(d["name"])
			out["desc"] = String(d["desc"])
			out["icon"] = String(d["icon"])
			out["color"] = Color("34f0ff")
		"weapon_up":
			var d2: Dictionary = weapon(id)
			var lv := 1
			if player != null:
				for wp in player.weapons:
					if String(wp["id"]) == id:
						lv = int(wp["lv"])
			out["tag"] = "武器强化"
			out["name"] = "%s  Lv.%d→%d" % [d2["name"], lv, lv + 1]
			out["desc"] = String(d2["desc"])
			out["icon"] = String(d2["icon"])
			out["color"] = Color("58f08e")
		"passive":
			var d3: Dictionary = passive(id)
			var plv := 0
			if player != null:
				plv = player.p_lv(id)
			out["tag"] = "被动强化"
			out["name"] = "%s  Lv.%d→%d" % [d3["name"], plv, plv + 1]
			out["desc"] = String(d3["desc"])
			out["icon"] = String(d3["icon"])
			out["color"] = Color("a25eff")
		"skill":
			var sk: Dictionary = skill(id)
			out["tag"] = "主动技能"
			out["name"] = String(sk["name"])
			out["desc"] = String(sk["desc"])
			out["icon"] = String(sk["icon"])
			out["color"] = Color("ff9a30")
		"bonus":
			out["tag"] = "补给"
			out["name"] = "应急补给"
			out["desc"] = "回复 35% 生命，并立刻获得一批齿轮"
			out["icon"] = "icon_m_heart"
			out["color"] = Color("58f08e")
		"evolve":
			var d4: Dictionary = weapon(id)
			out["tag"] = "进化！"
			out["name"] = String(d4["evo_name"])
			out["desc"] = String(d4["evo_desc"])
			out["icon"] = String(d4["icon"])
			out["color"] = Color("ffe460")
	return out


func phase_at(stage_idx: int, t: float) -> Dictionary:
	var st := stage(stage_idx)
	var best: Dictionary = st["phases"][0]
	for p in st["phases"]:
		if t >= float(p["t"]):
			best = p
	return best


func elite_chance(stage_idx: int, t: float) -> float:
	var st := stage(stage_idx)
	var start := float(st["elite_at"])
	if t < start:
		return 0.0
	return clampf((t - start) / 110.0, 0.0, 0.45) + float(stage(stage_idx).get("elite_base", 0.0))


## 每级带来的数值成长
func weapon_dmg(w: Dictionary, lv: int) -> float:
	return float(w["dmg"]) * (1.0 + 0.30 * (lv - 1))


func weapon_cd(w: Dictionary, lv: int) -> float:
	return float(w["cd"]) * (1.0 - 0.055 * (lv - 1))


func weapon_count(w: Dictionary, lv: int) -> int:
	var extra: Array = w.get("extra", [])
	var e := 0
	if lv - 1 < extra.size():
		e = int(extra[lv - 1])
	return int(w["count"]) + e
