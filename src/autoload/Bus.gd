extends Node
## 全局信号总线：让系统之间不直接互相引用。

signal player_hp_changed(hp: float, max_hp: float)
signal player_died
signal player_damaged(amount: float)
signal player_healed(amount: float)
signal player_shield_changed(shield: float, max_shield: float)
signal xp_gained(amount: int)
signal level_changed(level: int, cur: int, need: int)
signal level_up(choices: Array)
signal upgrade_taken(id: String)
signal enemy_died(pos: Vector2, kind: String, is_elite: bool, is_boss: bool)
signal gears_changed(total: int)
signal boss_spawned(boss)
signal boss_hp_changed(hp: float, max_hp: float)
signal boss_died
signal stage_time(stage_idx: int, elapsed: float, total: float)
signal wave_phase(text: String)
signal kill_count(n: int)
signal run_finished(result: Dictionary)
signal shake(amount: float, dur: float)
signal game_state_changed(state: int)
