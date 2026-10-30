class_name StoreOffers
extends RefCounted
## Local designated-weapon offers: TimeScript.Update, UIConstant.GetRank* and
## StoreUI.HandleEvent. Caller supplies time, ownership, RNG and persistence.
## No IAP, advertising, server promotions, currency mutations or file access.

enum Status { IDLE, PENDING, ACTIVE }

const SAVE_VERSION := 1
const OFFER_SECONDS := 86400
const CANDIDATES := [
	[2, 5, 8, 10, 23, 28],
	[13, 16, 21, 23, 28, 29, 30, 33, 35, 38],
	[13, 21, 23, 26, 28, 29, 30, 35, 36, 38],
]
const TIME_THRESHOLDS := [3600, 14400, 43200]
const SPEND_THRESHOLDS := [10, 85, 100]

var status: int = Status.IDLE
var weapon_id := -1
var elapsed_seconds := 0.0
var spent_mithril := 0
var created_at := 0
var rank_id := 0

var _threshold_rank := -1
var _rng := RandomNumberGenerator.new()


static func _tier(rank: int) -> int:
	return 0 if rank <= 3 else (1 if rank <= 5 else 2)


static func _gun_id(value: Variant) -> int:
	if value is int:
		return int(value) if int(value) >= 0 and int(value) < 47 else -1
	if value is String:
		var key := str(value)
		if key.begins_with("gun") and key.substr(3).is_valid_int():
			var id := int(key.substr(3))
			if id >= 0 and id < 47 and key == "gun%02d" % id:
				return id
	return -1


static func candidate_ids(rank: int) -> Array[int]:
	var result: Array[int] = []
	if rank < 0 or rank > 11:
		return result
	for id: int in CANDIDATES[_tier(rank)]:
		result.append(id)
	return result


func advance(delta: float, current_rank: int, owned_weapon_ids: Array, now_unix: int, random: RandomNumberGenerator = null) -> Dictionary:
	if not is_finite(delta) or delta < 0.0 or current_rank < 0 or current_rank > 11 or now_unix < 0:
		var invalid := report()
		invalid["event"] = "invalid_input"
		return invalid
	rank_id = current_rank
	# The source captures the timer tier at launch; offer choice/price use current rank.
	if _threshold_rank < 0:
		_threshold_rank = rank_id
	var event := "expired" if expire(now_unix) else "none"
	if status != Status.IDLE:
		var existing := report()
		existing["event"] = event
		return existing
	elapsed_seconds += delta
	var tier := _tier(_threshold_rank)
	# Source comparison is strictly greater, not greater-or-equal.
	if elapsed_seconds > float(TIME_THRESHOLDS[tier]):
		var owned: Dictionary = {}
		for value: Variant in owned_weapon_ids:
			owned[_gun_id(value)] = true
		var available: Array[int] = []
		for id: int in candidate_ids(rank_id):
			if not owned.has(id):
				available.append(id)
		if spent_mithril >= int(SPEND_THRESHOLDS[tier]) or available.is_empty():
			_clear()
			event = "reset"
		else:
			var generator := random if random != null else _rng
			# Unity Random.Range(0, Count-1) accidentally excluded the last candidate.
			# Include every eligible gun, using Godot's inclusive integer upper bound.
			weapon_id = available[generator.randi_range(0, available.size() - 1)]
			created_at = now_unix
			status = Status.PENDING
			event = "offered"
	var result := report()
	result["event"] = event
	return result


func activate(now_unix: int) -> bool:
	if now_unix < 0 or expire(now_unix) or status != Status.PENDING:
		return false
	status = Status.ACTIVE
	return true


func expire(now_unix: int) -> bool:
	if status == Status.IDLE or now_unix < 0:
		return false
	# Unix seconds avoid the source's ambiguous 12-hour date string. Clock rollback
	# never turns a stale offer into an unlimited discount.
	if now_unix < created_at or now_unix - created_at >= OFFER_SECONDS:
		_clear()
		return true
	return false


func quote(gun: Variant, base_mithril: int, current_rank: int = -1) -> Dictionary:
	var id := _gun_id(gun)
	var price_rank := current_rank if current_rank >= 0 and current_rank <= 11 else rank_id
	var base := maxi(0, base_mithril)
	var discounted := id >= 0 and id == weapon_id and status == Status.ACTIVE and base > 0
	var multiplier := (0.5 if price_rank <= 3 else 0.75) if discounted else 1.0
	return {"weapon_id": "gun%02d" % id if id >= 0 else "", "base_mithril": base,
		"mithril": int(float(base) * multiplier), "multiplier": multiplier,
		"discounted": discounted}


func report_purchase(gun: Variant, paid_mithril: int) -> Dictionary:
	# Call only after a successful purchase. State transactions belong to GameState.
	var id := _gun_id(gun)
	if id < 0 or paid_mithril < 0:
		return report()
	if status != Status.IDLE and id == weapon_id:
		_clear()
	else:
		spent_mithril += paid_mithril
	return report()


func report() -> Dictionary:
	var tier := _tier(_threshold_rank if _threshold_rank >= 0 else rank_id)
	return {"status": status, "state": ["idle", "pending", "active"][status],
		"weapon_id": "gun%02d" % weapon_id if weapon_id >= 0 else "", "gun_id": weapon_id,
		"rank_id": rank_id, "elapsed_seconds": elapsed_seconds, "spent_mithril": spent_mithril,
		"seconds_required": int(TIME_THRESHOLDS[tier]), "mithril_threshold": int(SPEND_THRESHOLDS[tier]),
		"progress": clampf(elapsed_seconds / float(TIME_THRESHOLDS[tier]), 0.0, 1.0),
		"created_at": created_at, "expires_at": created_at + OFFER_SECONDS if status != Status.IDLE else 0}


func serialize() -> Dictionary:
	return {"version": SAVE_VERSION, "status": status, "weapon_id": weapon_id,
		"elapsed_seconds": elapsed_seconds, "spent_mithril": spent_mithril,
		"created_at": created_at, "rank_id": rank_id}


func restore(data: Dictionary) -> bool:
	_clear()
	# Timer tier belongs to this session, so transaction rollback must retain it.
	# A fresh instance still captures its launch rank on the first advance().
	rank_id = 0
	if data.is_empty():
		return true
	if data.get("version") != SAVE_VERSION:
		return false
	for key: String in ["status", "weapon_id", "elapsed_seconds", "spent_mithril", "created_at", "rank_id"]:
		var value: Variant = data.get(key)
		if not (value is int or value is float) or not is_finite(float(value)):
			return false
		if key != "elapsed_seconds" and float(value) != floorf(float(value)):
			return false
	var saved_status := int(data.status)
	var saved_id := int(data.weapon_id)
	if saved_status not in [Status.IDLE, Status.PENDING, Status.ACTIVE] or int(data.rank_id) < 0 or int(data.rank_id) > 11:
		return false
	if float(data.elapsed_seconds) < 0.0 or int(data.spent_mithril) < 0 or int(data.created_at) < 0:
		return false
	if saved_status != Status.IDLE and (saved_id < 0 or saved_id >= 47):
		return false
	status = saved_status
	weapon_id = saved_id if status != Status.IDLE else -1
	elapsed_seconds = float(data.elapsed_seconds)
	spent_mithril = int(data.spent_mithril)
	created_at = int(data.created_at) if status != Status.IDLE else 0
	rank_id = int(data.rank_id)
	return true


func _clear() -> void:
	status = Status.IDLE
	weapon_id = -1
	elapsed_seconds = 0.0
	spent_mithril = 0
	created_at = 0
