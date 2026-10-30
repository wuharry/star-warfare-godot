extends "res://scripts/game/pickup.gd"

var network_id := 0

func _on_body_entered(body: Node3D) -> void:
	if not NetworkSession.is_host() or NetworkSession.phase != "playing" or collected:
		return
	if not body is WarfarePlayer or not "peer_id" in body or body.dead:
		return
	collected = true
	get_parent().collect_network_pickup(self, body)
	queue_free()

func network_state() -> Dictionary:
	return {"position": position, "kind": pickup_kind, "amount": amount}
