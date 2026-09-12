class_name OriginalWeaponTrail
extends MeshInstance3D
var record: Dictionary
var points: Array[Dictionary] = []
var elapsed := 0.0
func _ready() -> void:
	material_override=OriginalWeaponEffect.material_resource(record.m_Materials[0].guid,true)
	cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
func _process(delta: float) -> void:
	elapsed+=delta
	var position:=global_position
	if points.is_empty() or Vector3(points[-1].position).distance_to(position)>=float(record.m_MinVertexDistance):
		points.append({"position":position,"time":elapsed})
	while not points.is_empty() and elapsed-float(points[0].time)>float(record.m_Time): points.pop_front()
	if points.size()<2: return
	var camera:=get_viewport().get_camera_3d()
	if camera==null:return
	var surface:=SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vertices:=[]
	var colors:=[]
	var uvs:=[]
	for i in points.size():
		var point:Vector3=points[i].position
		var t:=clampf((elapsed-float(points[i].time))/maxf(float(record.m_Time),0.001),0,1)
		var other:Vector3=points[maxi(0,i-1)].position if i>0 else points[1].position
		var side:Vector3=(point-other).cross(camera.global_position-point).normalized()*lerpf(float(record.m_StartWidth),float(record.m_EndWidth),t)*0.5
		var ci:=mini(floori(t*4),3)
		var c:Color=OriginalWeaponParticles.unpack_color(record.m_Colors.get("m_Color[%d]"%ci,{})).lerp(OriginalWeaponParticles.unpack_color(record.m_Colors.get("m_Color[%d]"%(ci+1),{})),t*4-ci)
		for sign_value in [-1,1]:
			vertices.append(to_local(point+side*sign_value));colors.append(c);uvs.append(Vector2(t,float(sign_value+1)/2))
	for i in range(points.size()-1):
		for index in [i*2,i*2+1,i*2+2,i*2+1,i*2+3,i*2+2]:
			surface.set_color(colors[index]);surface.set_uv(uvs[index]);surface.add_vertex(vertices[index])
	mesh=surface.commit()
