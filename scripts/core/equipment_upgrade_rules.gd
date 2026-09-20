extends RefCounted
## SW1 table 18 + Weapon.Upgrade/GetDamageUpgradePrice; CoM LoadAvatarElement.
## Catalogs stay at base level. Progress belongs to the save, not these tables.

const SW1 = preload("res://scripts/core/recovered_game_data.gd")
const CoM = preload("res://scripts/core/recovered_com_data.gd")
const COM_MAX_LEVEL := 7


static func weapon_multiplier(level: int) -> float:
	var percent := 100
	for index in range(1, clampi(level, 1, SW1.WEAPON_UPGRADE_ROWS.size())):
		percent += int(SW1.WEAPON_UPGRADE_ROWS[index][1])
	return percent / 100.0


static func weapon_cost(base_price: int, level: int) -> int:
	if level < 1 or level >= SW1.WEAPON_UPGRADE_ROWS.size():
		return 0
	# Original truncates to whole hundreds, using cash price even for mithril guns.
	var amount := base_price * int(SW1.WEAPON_UPGRADE_ROWS[level][0])
	return int(amount / 10000) * 100


static func armor_multiplier(set_id: int, level: int) -> float:
	var increments := str(CoM.ARMOR_SETS[str(set_id)].raw.UpgradePropAddPer).split(";")
	var multiplier := 1.0
	# Source index 0 is displayed as LV 1. Add original-base percentages, no compounding.
	for index in range(clampi(level, 1, COM_MAX_LEVEL)):
		multiplier += float(increments[index])
	return multiplier


static func armor_cost(set_id: int, level: int) -> Dictionary:
	if level < 1 or level >= COM_MAX_LEVEL:
		return {"credits": 0, "mithril": 0}
	var raw: Dictionary = CoM.ARMOR_SETS[str(set_id)].raw
	# Upgrade_Avatar reads the NEXT source level, not the purchase (index 0).
	return {"credits": int(str(raw.BuyMoney).split(";")[level]),
		"mithril": int(str(raw.BuyCrystal).split(";")[level])}
