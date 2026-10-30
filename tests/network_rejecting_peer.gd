extends "res://scripts/network/network_session.gd"
## Adversarial integration fixture: ignore the polite rejection message.
@rpc("authority", "call_remote", "reliable")
func _reject(_reason: String) -> void:
	pass
