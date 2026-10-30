extends "res://scripts/network/network_enemy.gd"
## Network adapter only. Enemy source brains and assets own every boss attack.
var boss_index := 0
var assist := false

func configure_boss(player_target: WarfarePlayer, selection: int, secondary := false) -> bool:
	boss_index = clampi(selection, 0, 5)
	assist = secondary
	var source_id := 12 if secondary else int(MatchRules.BOSS_SOURCE_IDS[boss_index])
	return configure_original(player_target, source_id)

func network_state() -> Dictionary:
	var state := super.network_state()
	state.boss_index = boss_index
	state.assist = assist
	return state
