extends Node
const World = preload("res://scripts/game/network_world.gd")
var failures: Array[String] = []

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	NetworkSession.auto_change_scene = false
	for selection in range(6):
		var before := GameState.mithril
		var error := NetworkSession.host_room({"mode": "Boss", "boss_index": selection, "max_players": 1}, 24800 + selection)
		if error != OK:
			failures.append("host %d" % selection)
			continue
		NetworkSession.set_ready(true, 0)
		if not NetworkSession.start_match(): failures.append("solo start %d" % selection)
		var world := World.new()
		add_child(world)
		for frame in range(120):
			await get_tree().physics_frame
			world.player.invulnerable_left = 100.0
		var expected := 2 if selection == 3 else 1
		if world.enemies.size() != expected or world.boss_spawn_points.size() != expected or world.player_spawn_points.size() != 3:
			failures.append("source encounter/spawn count %d" % selection)
		if str(world.level_data.resource_directory) != "res://assets/models/boss_arenas/boss_%02d" % (selection + 1):
			failures.append("source arena %d" % selection)
		if selection == 3:
			var pair := world.enemies.values()
			if pair.size() == 2 and (pair[0].source_brain.partner_actor() != pair[1] or pair[1].source_brain.partner_actor() != pair[0]):
				failures.append("twins not linked")
		var frames := 0
		while NetworkSession.phase == "playing" and frames < 360:
			world.player.invulnerable_left = 100.0
			for enemy: Node in world.enemies.values():
				if not enemy.dead:
					world.damage_target(world.player, enemy, enemy.max_health * 1000.0, enemy.position)
			await get_tree().physics_frame
			frames += 1
		if NetworkSession.phase != "finished" or not bool(world.settlement_result.get("saved", false)):
			failures.append("encounter did not settle %d" % selection)
		if GameState.mithril != before + 1: failures.append("fixed one Mithril %d" % selection)
		world.settle_local_result()
		if GameState.mithril != before + 1: failures.append("duplicate Mithril %d" % selection)
		NetworkSession.leave()
		world.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
	await get_tree().create_timer(0.15).timeout
	print("NETWORK_BOSSES_%s six_source_arenas solo_host twins fixed_mithril failures=%s" % ["PASS" if failures.is_empty() else "FAIL", failures])
	get_tree().quit(0 if failures.is_empty() else 1)
