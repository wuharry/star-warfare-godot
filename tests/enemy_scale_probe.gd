extends Node3D

# Temporary measurement scene. Prints the numbers enemy.gd uses when it scales a
# recovered model, so the authored size and the size the player actually sees can
# be compared side by side.

const KINDS := {
	"crawler": "bug01",
	"spitter": "bug03",
	"brute": "bug04",
	"boss": "boss01",
}

# Read straight off the live table so the probe cannot drift from the game.
const CURRENT_TARGETS := WarfareEnemy.TARGET_HEIGHTS

const PLAYER_CAPSULE_HEIGHT := 1.82

func _combined_mesh_aabb(root: Node3D) -> AABB:
	var result := AABB()
	var has_bounds := false
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var instance := child as MeshInstance3D
		if not instance.mesh:
			continue
		var relative := root.global_transform.affine_inverse() * instance.global_transform
		var bounds := relative * instance.mesh.get_aabb()
		result = result.merge(bounds) if has_bounds else bounds
		has_bounds = true
	return result

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found:
			return found
	return null

func _ready() -> void:
	print("PLAYER capsule height = %.3f" % PLAYER_CAPSULE_HEIGHT)
	print("kind      | bind.y  posed.y  factor  -> VISIBLE HEIGHT  (vs player)")
	for kind: String in KINDS:
		var model_name: String = KINDS[kind]
		var path := "res://assets/models/enemies/animated/%s/%s.gltf" % [model_name, model_name]
		if not ResourceLoader.exists(path):
			print("%s: MISSING %s" % [kind, path])
			continue
		var packed := load(path) as PackedScene
		var instance := packed.instantiate() as Node3D
		add_child(instance)
		var player := _find_animation_player(instance)
		var bind_bounds := _combined_mesh_aabb(instance)
		if player and player.has_animation("idle"):
			player.play("idle")
			player.advance(0.0)
			player.seek(0.0, true)
		var posed := EnemyHitGeometry.posed_bounds(instance)
		if posed.size.y <= 0.001:
			posed = bind_bounds
		var target: float = CURRENT_TARGETS[kind]
		var factor: float = target / posed.size.y
		var visible_height: float = posed.size.y * factor
		var ratio: float = visible_height / PLAYER_CAPSULE_HEIGHT
		print("%-9s | %6.3f  %6.3f  %6.3f  -> %6.3f m        (%.0f%% of player)" % [
			kind, bind_bounds.size.y, posed.size.y, factor, visible_height, ratio * 100.0])
		print("          posed footprint X=%.2f Z=%.2f -> scaled X=%.2f Z=%.2f" % [
			posed.size.x, posed.size.z, posed.size.x * factor, posed.size.z * factor])
		# What target_height would be needed for a given visible height
		var capsule: Vector2 = WarfareEnemy.HITBOX_PROFILES[kind]
		print("          walk capsule r=%.2f h=%.2f" % [capsule.x, capsule.y])
		instance.queue_free()
	print("PROBE DONE")
	get_tree().quit()
