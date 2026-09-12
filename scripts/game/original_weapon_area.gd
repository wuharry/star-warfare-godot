class_name OriginalWeaponArea
extends Node3D
var source: Node
var damage := 0.0
var radius := 4.0
var height := 8.0
var interval := 0.3
var ticks_left := 3
var delay := 0.3
func _physics_process(delta: float) -> void:
	delay-=delta
	if delay>0:return
	delay+=interval
	for target in get_tree().get_nodes_in_group("enemies"):
		if not target is Node3D or not target.has_method("take_damage"):continue
		var offset: Vector3=target.global_position-global_position
		if Vector2(offset.x,offset.z).length()>radius or offset.y < -1 or offset.y>height:continue
		var ray:=PhysicsRayQueryParameters3D.create(global_position+Vector3.UP*0.1,target.global_position+Vector3.UP,1)
		if get_world_3d().direct_space_state.intersect_ray(ray).is_empty():target.take_damage(damage,target.global_position+Vector3.UP,source)
	ticks_left-=1
	if ticks_left<=0:queue_free()
