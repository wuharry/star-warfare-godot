class_name OriginalWeaponParticles
extends Node3D

var source: Dictionary
var renderer: Dictionary
var animator: Dictionary
var legacy := false
var elapsed := 0.0
var carry := 0.0
var duration := 1.0
var delay := 0.0
var looping := false
var local_space := true
var particles: Array[Dictionary] = []
var batch: MultiMeshInstance3D
var capacity := 1000
var bursts: Dictionary = {}
var rng := RandomNumberGenerator.new()
var death_emitter: OriginalWeaponParticles
var sub_only := false
var spawn_override: Variant = null

func configure(components: Dictionary) -> void:
	legacy = components.has("EllipsoidParticleEmitter")
	source = components.get("EllipsoidParticleEmitter", components.get("ParticleSystem", [{}]))[0]
	renderer = components.get("ParticleRenderer", components.get("ParticleSystemRenderer", [{}]))[0]
	animator = components.get("ParticleAnimator", [{}])[0]
	if legacy:
		looping = not bool(source.get("m_OneShot", 0))
		local_space = not bool(source.get("Simulate in Worldspace?", 1))
	else:
		duration = float(source.lengthInSec)
		delay = float(source.get("startDelay", 0.0))
		looping = bool(source.looping)
		local_space = bool(source.get("moveWithTransform", 1))
		capacity = int(source.InitialModule.get("maxNumParticles", 1000))

func _ready() -> void:
	rng.randomize()
	batch = MultiMeshInstance3D.new()
	batch.multimesh = MultiMesh.new()
	batch.multimesh.transform_format = MultiMesh.TRANSFORM_3D
	batch.multimesh.use_colors = true
	batch.multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	batch.multimesh.mesh = quad
	batch.multimesh.instance_count = capacity
	batch.multimesh.visible_instance_count = 0
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var refs: Array = renderer.get("m_Materials", [])
	if not refs.is_empty():
		var material := OriginalWeaponEffect.material_resource(refs[0].guid, true)
		var uv: Dictionary = source.get("UVModule", {})
		if legacy:
			uv = renderer.get("UV Animation", {})
			material.set_shader_parameter("tiles", Vector2(float(uv.get("x Tile",1)),float(uv.get("y Tile",1))))
		elif bool(uv.get("enabled",0)):
			material.set_shader_parameter("tiles", Vector2(float(uv.tilesX),float(uv.tilesY)))
		batch.material_override = material
	add_child(batch)
	if not local_space:
		batch.top_level = true
		batch.global_transform = Transform3D.IDENTITY
	set_process(bool(renderer.get("m_Enabled",1)) and bool(source.get("m_Enabled",1)))

static func unpack_color(value: Dictionary) -> Color:
	if value.has("rgba"):
		var n := int(value.rgba)
		return Color(float(n & 255)/255.0, float((n>>8)&255)/255.0, float((n>>16)&255)/255.0, float((n>>24)&255)/255.0)
	return Color(float(value.get("r",1)),float(value.get("g",1)),float(value.get("b",1)),float(value.get("a",1)))

static func gradient(g: Dictionary, t: float) -> Color:
	var result := Color.WHITE
	for alpha in [false,true]:
		var count := int(g.get("m_NumAlphaKeys" if alpha else "m_NumColorKeys",0))
		var previous := Color.WHITE
		var previous_time := 0.0
		for i in count:
			var color := unpack_color(g.get("key%d"%i,{}))
			var time := float(g.get(("atime%d" if alpha else "ctime%d")%i,0))/65535.0
			var current := color
			if i > 0 and t < time:
				current = previous.lerp(color,clampf((t-previous_time)/maxf(time-previous_time,0.00001),0,1))
			if alpha: result.a = current.a
			else:
				result.r=current.r; result.g=current.g; result.b=current.b
			if t <= time: break
			previous=color; previous_time=time
	return result

static func gradient_range(g: Dictionary, t: float, random: float) -> Color:
	var mode := int(g.get("minMaxState",0))
	if mode == 0: return unpack_color(g.get("maxColor",{}))
	if mode == 1: return gradient(g.get("maxGradient",{}),t)
	if mode == 2: return unpack_color(g.get("minColor",{})).lerp(unpack_color(g.get("maxColor",{})),random)
	return gradient(g.get("minGradient",{}),t).lerp(gradient(g.get("maxGradient",{}),t),random)

func _spawn() -> void:
	if particles.size() >= capacity: return
	var random := rng.randf()
	var position := Vector3.ZERO
	var velocity := Vector3.ZERO
	var force := Vector3.ZERO
	var life := 1.0
	var size := 1.0
	var angle := 0.0
	var color := Color.WHITE
	var radial := Vector3(rng.randfn(),rng.randfn(),rng.randfn()).normalized()
	if legacy:
		position = radial * pow(rng.randf(),1.0/3.0) * OriginalWeaponEffect.vector(source.m_Ellipsoid)
		var random_velocity := OriginalWeaponEffect.vector(source.rndVelocity,true)
		velocity = OriginalWeaponEffect.vector(source.localVelocity,true)+Vector3(rng.randf_range(-1,1),rng.randf_range(-1,1),rng.randf_range(-1,1))*random_velocity
		velocity += OriginalWeaponEffect.vector(source.worldVelocity,true)
		force = OriginalWeaponEffect.vector(animator.get("force",{"x":0,"y":0,"z":0}),true)
		life=rng.randf_range(float(source.minEnergy),float(source.maxEnergy))
		size=rng.randf_range(float(source.minSize),float(source.maxSize))
		angle=rng.randf_range(0,TAU) if bool(source.rndRotation) else 0.0
	else:
		var initial: Dictionary = source.InitialModule
		var t := fmod(maxf(elapsed-delay,0),duration)/duration
		life=OriginalWeaponEffect.minmax(initial.startLifetime,t,random,1)
		size=OriginalWeaponEffect.minmax(initial.startSize,t,random,1)
		angle=OriginalWeaponEffect.minmax(initial.get("startRotation",{}),t,random)
		color=gradient_range(initial.startColor,t,random)
		var shape: Dictionary = source.get("ShapeModule",{})
		var direction := Vector3.FORWARD
		if bool(shape.get("enabled",0)):
			var radius := float(shape.get("radius",0))
			match int(shape.get("type",0)):
				0,1:
					position=radial*radius*(1.0 if int(shape.type)==1 else pow(rng.randf(),1.0/3.0))
					direction=radial
				2,3:
					radial.z=-absf(radial.z)
					position=radial*radius*pow(rng.randf(),1.0/3.0); direction=radial
				4,7:
					var a:=rng.randf()*TAU
					var r:=sqrt(rng.randf())
					position=Vector3(cos(a),sin(a),0)*radius*r
					direction=Vector3(cos(a)*sin(deg_to_rad(float(shape.angle)))*r,sin(a)*sin(deg_to_rad(float(shape.angle)))*r,-cos(deg_to_rad(float(shape.angle)))).normalized()
				5:
					position=Vector3(rng.randf_range(-0.5,0.5)*float(shape.boxX),rng.randf_range(-0.5,0.5)*float(shape.boxY),rng.randf_range(-0.5,0.5)*float(shape.boxZ))
			if bool(shape.get("randomDirection",0)): direction=radial
		velocity=direction*OriginalWeaponEffect.minmax(initial.startSpeed,t,random)
		force=Vector3.DOWN*9.81*OriginalWeaponEffect.minmax(initial.get("gravityModifier",{}),t,random)
	if not local_space:
		position=global_transform*position
		velocity=global_basis*velocity
		force=global_basis*force
	if spawn_override != null: position += Vector3(spawn_override) - global_position
	particles.append({"position":position,"velocity":velocity,"force":force,"life":maxf(life,0.001),"age":0.0,"size":size,"angle":angle,"random":random,"color":color})

func trigger_at(point: Vector3) -> void:
	spawn_override = point
	var emission: Dictionary = source.get("EmissionModule",{})
	for i in int(emission.get("m_BurstCount",0)):
		for j in int(emission.get("cnt%d"%i,0)): _spawn()
	spawn_override = null

func _process(delta: float) -> void:
	var previous := elapsed
	elapsed += delta*float(source.get("speed",1))
	var active := not sub_only and elapsed>=delay and (looping or elapsed<=duration+delay)
	if active:
		var rate := 0.0
		if legacy:
			rate=(float(source.minEmission)+float(source.maxEmission))*0.5 if looping else 0.0
			if not looping and previous==0:
				for i in int(rng.randf_range(float(source.minEmission),float(source.maxEmission))): _spawn()
		else:
			var emission: Dictionary = source.get("EmissionModule",{})
			if bool(emission.get("enabled",0)):
				var cycle := floori(maxf(elapsed-delay,0)/duration)
				rate=OriginalWeaponEffect.minmax(emission.get("rate",{}),fmod(elapsed-delay,duration)/duration,0.5)
				for i in int(emission.get("m_BurstCount",0)):
					var time := delay+cycle*duration+float(emission.get("time%d"%i,0))
					var key := "%d_%d"%[cycle,i]
					if elapsed>=time and not bursts.has(key):
						bursts[key]=true
						for j in int(emission.get("cnt%d"%i,0)): _spawn()
		carry+=rate*delta
		while carry>=1:
			_spawn();carry-=1
	var camera := get_viewport().get_camera_3d()
	var camera_basis := camera.global_basis if camera!=null else Basis.IDENTITY
	if local_space: camera_basis=global_basis.inverse()*camera_basis
	for i in range(particles.size()-1,-1,-1):
		var p: Dictionary = particles[i]
		p.age+=delta
		if float(p.age)>=float(p.life):
			if death_emitter != null: death_emitter.trigger_at(global_transform*Vector3(p.position) if local_space else Vector3(p.position))
			particles.remove_at(i);continue
	for i in particles.size():
		var p: Dictionary = particles[i]
		p.velocity+=Vector3(p.force)*delta
		var last_position: Vector3=p.position
		p.position+=Vector3(p.velocity)*delta
		if bool(source.get("CollisionModule",{}).get("enabled",0)):
			var from := global_transform*last_position if local_space else last_position
			var to := global_transform*Vector3(p.position) if local_space else Vector3(p.position)
			var hit := get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))
			if not hit.is_empty():
				p.position = to_local(hit.position) if local_space else hit.position
				p.age = p.life
		var t := float(p.age)/float(p.life)
		var size := float(p.size)
		var color: Color = p.color
		var frame := 0.0
		if legacy:
			p.velocity*=maxf(0,1-float(animator.get("damping",0))*delta)
			size+=float(animator.get("sizeGrow",0))*float(p.age)
			if bool(animator.get("Does Animate Color?",0)):
				var index:=mini(floori(t*4),3)
				color*=unpack_color(animator.get("colorAnimation[%d]"%index,{})).lerp(unpack_color(animator.get("colorAnimation[%d]"%(index+1),{})),t*4-index)
			var uv: Dictionary=renderer.get("UV Animation",{})
			frame=floor(fmod(t*float(uv.get("cycles",1)),1)*float(uv.get("x Tile",1))*float(uv.get("y Tile",1)))
		else:
			if bool(source.get("SizeModule",{}).get("enabled",0)): size*=OriginalWeaponEffect.minmax(source.SizeModule.curve,t,p.random,1)
			if bool(source.get("ColorModule",{}).get("enabled",0)): color*=gradient_range(source.ColorModule.gradient,t,p.random)
			if bool(source.get("RotationModule",{}).get("enabled",0)): p.angle+=OriginalWeaponEffect.minmax(source.RotationModule.curve,t,p.random)*delta
			if bool(source.get("UVModule",{}).get("enabled",0)):
				var uv: Dictionary=source.UVModule
				frame=floor(fmod(OriginalWeaponEffect.minmax(uv.frameOverTime,t,p.random)*float(uv.cycles),0.99999)*float(uv.tilesX)*float(uv.tilesY))
			if bool(source.get("ClampVelocityModule",{}).get("enabled",0)):
				var clamp_module: Dictionary=source.ClampVelocityModule
				var limit:=OriginalWeaponEffect.minmax(clamp_module.get("magnitude",{}),t,p.random,10000)
				if Vector3(p.velocity).length()>limit: p.velocity=Vector3(p.velocity).lerp(Vector3(p.velocity).limit_length(limit),float(clamp_module.get("dampen",0)))
		var basis := camera_basis*Basis(Vector3.BACK,float(p.angle))
		var scale := Vector3.ONE*maxf(size,0.00001)
		var render_mode := int(renderer.get("m_RenderMode",renderer.get("m_StretchParticles",0)))
		if render_mode==1 or render_mode==3:
			var velocity: Vector3=p.velocity
			if velocity.length_squared()>0.001:
				var along:=velocity.normalized()
				var right:=along.cross(camera_basis.z).normalized()
				if right.length_squared()>0.001: basis=Basis(right,along,right.cross(along))
				scale.y*=float(renderer.get("m_LengthScale",renderer.get("m_LengthScale",2)))+float(renderer.get("m_VelocityScale",0))*velocity.length()
		batch.multimesh.set_instance_transform(i,Transform3D(basis.scaled(scale),p.position))
		batch.multimesh.set_instance_color(i,color)
		batch.multimesh.set_instance_custom_data(i,Color(frame,0,0,0))
	batch.multimesh.visible_instance_count=particles.size()
