extends Node

const Offers = preload("res://scripts/core/store_offers.gd")
var failures: Array[String] = []
var checks := 0


func _ready() -> void:
	_run.call_deferred()


func _check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures.append(message)
		push_error("STORE OFFERS: " + message)


func _run() -> void:
	_check(GameState.save_path != GameState.SAVE_PATH, "use isolated --test-profile before autoload")
	_test_trigger_and_price()
	_test_tiers_and_ownership()
	_test_purchase_and_expiry()
	_test_persistence()
	_test_transaction_rollback()
	print("STORE_OFFERS_TEST_PASS checks=%d" % checks if failures.is_empty() else "STORE_OFFERS_TEST_FAIL: " + str(failures))
	get_tree().quit(0 if failures.is_empty() else 1)


func _test_trigger_and_price() -> void:
	var offers := Offers.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 1029
	_check(offers.advance(3600.0, 0, [], 1000, rng).state == "idle", "offer triggered at equality rather than greater-than")
	var result := offers.advance(0.01, 0, ["gun00"], 1000, rng)
	_check(result.event == "offered" and result.state == "pending", "offer did not trigger")
	var target: String = result.weapon_id
	_check(offers.quote(target, 55).mithril == 55, "pending offer changed purchase price before shop activation")
	_check(offers.activate(1001), "pending offer did not activate")
	_check(offers.quote(target, 55).mithril == 27, "discount must truncate integer price")
	_check(offers.quote(target, 55, 4).mithril == 41, "current-rank discount not used at purchase")
	_check(offers.quote("gun00", 55).mithril == 55 and not offers.quote(target, 0).discounted, "discount affected unrelated/cash purchase")
	offers.advance(50000.0, 0, [], 1002, rng)
	_check(offers.weapon_id == result.gun_id and offers.elapsed_seconds < 3601.0, "active offer rerolled or kept accumulating time")


func _test_tiers_and_ownership() -> void:
	for fixture: Array in [[0, 3600, 10], [4, 14400, 85], [6, 43200, 100], [11, 43200, 100]]:
		var offers := Offers.new()
		offers.report_purchase("gun00", int(fixture[2]))
		var result := offers.advance(float(fixture[1]) + 1.0, int(fixture[0]), [], 100)
		_check(result.event == "reset" and result.spent_mithril == 0 and result.elapsed_seconds == 0.0, "spending threshold must reset offer progress")
		result = offers.advance(float(fixture[1]) + 1.0, int(fixture[0]), [], 101)
		_check(result.event == "offered", "new earning interval did not restart")
	var all_owned := Offers.new()
	_check(all_owned.advance(3601.0, 0, Offers.candidate_ids(0), 100).event == "reset", "all owned candidates should reset without an offer")
	var only_last := Offers.new()
	_check(only_last.advance(3601.0, 0, [2, 5, 8, 10, 23], 100).gun_id == 28, "only remaining candidate lost")
	var seen: Dictionary = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = 441
	for index in 24:
		var offers := Offers.new()
		var result := offers.advance(3601.0, 0, [2, 5, 8, 10], 100, rng)
		seen[result.gun_id] = true
	_check(seen.has(23) and seen.has(28), "random selection still excludes last eligible gun")
	var tier_change := Offers.new()
	tier_change.advance(3500.0, 0, [], 100)
	var changed := tier_change.advance(101.0, 4, [], 201)
	_check(changed.event == "offered" and Offers.candidate_ids(4).has(changed.gun_id), "timer launch tier/current candidate rank mixed up")


func _test_purchase_and_expiry() -> void:
	var offers := Offers.new()
	var offered := offers.advance(3601.0, 0, [], 1000)
	offers.activate(1001)
	offers.report_purchase("gun00", 3)
	_check(offers.status == Offers.Status.ACTIVE and offers.spent_mithril == 3, "unrelated purchase consumed designated offer")
	offers.report_purchase(offered.weapon_id, 20)
	_check(offers.status == Offers.Status.IDLE and offers.elapsed_seconds == 0.0 and offers.spent_mithril == 0, "successful designated purchase did not consume/reset offer")
	offered = offers.advance(3601.0, 0, [], 2000)
	offers.report_purchase(offered.weapon_id, 40)
	_check(offers.status == Offers.Status.IDLE, "purchasing pending target left a stale offer")
	offers.advance(3601.0, 0, [], 3000)
	offers.activate(3000)
	_check(not offers.expire(3000 + 86399), "offer expired too early")
	_check(offers.expire(3000 + 86400), "offer did not expire at 24 hours")
	offers.advance(3601.0, 0, [], 5000)
	_check(offers.expire(4999), "clock rollback extended offer indefinitely")
	var snapshot := offers.serialize()
	_check(offers.advance(-1.0, 0, [], 10).event == "invalid_input" and offers.serialize() == snapshot, "invalid delta mutated progress")


func _test_persistence() -> void:
	var offers := Offers.new()
	var result := offers.advance(3601.0, 0, [], 1000)
	offers.activate(1000)
	offers.report_purchase("gun00", 2)
	# JSON round trip exercises number coercion without touching any player save.
	var saved: Dictionary = JSON.parse_string(JSON.stringify(offers.serialize()))
	var restored := Offers.new()
	_check(restored.restore(saved), "valid persisted offer rejected")
	_check(restored.serialize() == offers.serialize(), "serialized offer fields lost")
	_check(restored.quote(result.weapon_id, 99).mithril == 49, "restored active offer lost pricing")
	_check(restored.advance(0.0, 0, [], 1000 + 86400).event == "expired", "persisted offer never expired")
	for bad: Dictionary in [{"version": 999}, {"version": 1, "status": "active"}]:
		_check(not restored.restore(bad) and restored.status == Offers.Status.IDLE, "malformed save granted a discount")
	saved.status = 3
	_check(not restored.restore(saved), "invalid status accepted")
	saved = offers.serialize()
	saved.elapsed_seconds = NAN
	_check(not restored.restore(saved), "NaN progress accepted")
	_check(restored.restore({}) and restored.status == Offers.Status.IDLE, "old save without offers should start idle")


func _test_transaction_rollback() -> void:
	var offers := Offers.new()
	offers.advance(3500.0, 0, [], 100)
	offers.advance(50.0, 4, [], 150)
	var before := offers.serialize()
	offers.report_purchase("gun00", 85)
	_check(offers.restore(before), "purchase rollback rejected its own snapshot")
	_check(offers.report().seconds_required == 3600 and offers.report().mithril_threshold == 10, "failed purchase changed this session's timer tier")
	_check(offers.advance(51.0, 4, [], 201).event == "offered", "failed purchase delayed the next offer after a rank increase")
	var relaunched := Offers.new()
	_check(relaunched.restore(before), "relaunch rejected persisted progress")
	_check(relaunched.advance(51.0, 4, [], 201).state == "idle" and relaunched.report().seconds_required == 14400, "new session did not capture its starting rank")
