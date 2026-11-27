class_name SurvivorAnimator
extends Node3D
## Anima o modelo 3D do sobrevivente e posiciona armas/equipamentos no corpo.
##
## Camadas (AnimationTree):
##   1. Locomoção (pernas e corpo): idle, walk, run, sprint, agachado, pulo, morte.
##      A velocidade de reprodução acompanha a velocidade real (pés não deslizam).
##   2. Segurar arma (só tronco e braços): hold_melee / hold_pistol.
##   3. Ação (one-shot, tronco e braços): golpe, disparo, recarga.
##   4. Aterrissagem (one-shot curto, corpo inteiro): leve ou pesada, conforme a altura da queda.
##   5. Uso (one-shot, corpo inteiro): beber, comer, pegar do chão, pular obstáculo, escalar.
## Por cima de tudo, uma inclinação procedural do corpo: tomba para dentro das curvas e para
## frente/trás ao acelerar e frear (como uma pessoa de verdade compensando o peso).

## Velocidade no chão (m/s) de cada ciclo: distância do pé no apoio / tempo de apoio.
const NOMINAL_SPEED := {&"walk": 1.3, &"run": 3.57, &"sprint": 5.78, &"crouch_walk": 0.88}
## Velocidade nominal por direção (frente, trás, lado) dos ciclos direcionais.
const DIRECTIONAL_SPEED := {&"walk": Vector3(1.3, 1.03, 1.01), &"run": Vector3(3.57, 2.14, 2.5),
	&"crouch_walk": Vector3(0.88, 0.68, 0.67), &"walk_aim": Vector3(1.03, 0.86, 0.84)}
## Espaços de mistura 2D: x = direita, y = frente.
const BLEND_SPACES := {
	&"walk": {&"walk": Vector2(0, 1), &"walk_back": Vector2(0, -1), &"walk_left": Vector2(-1, 0), &"walk_right": Vector2(1, 0)},
	&"run": {&"run": Vector2(0, 1), &"run_back": Vector2(0, -1), &"run_left": Vector2(-1, 0), &"run_right": Vector2(1, 0)},
	&"crouch_walk": {&"crouch_walk": Vector2(0, 1), &"crouch_walk_back": Vector2(0, -1),
		&"crouch_walk_left": Vector2(-1, 0), &"crouch_walk_right": Vector2(1, 0)},
	&"walk_aim": {&"walk_aim": Vector2(0, 1), &"walk_aim_back": Vector2(0, -1), &"walk_aim_left": Vector2(-1, 0),
		&"walk_aim_right": Vector2(1, 0)},
}
const LOCO: Array[StringName] = [&"idle", &"walk", &"walk_aim", &"run", &"sprint", &"crouch_idle", &"crouch_walk",
	&"jump", &"jump_run", &"fall", &"death"]
const LOOPING: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"crouch_idle", &"crouch_walk",
	&"hold_melee", &"hold_pistol", &"hold_item", &"walk_back", &"walk_left", &"walk_right", &"run_back", &"run_left",
	&"run_right", &"crouch_walk_back", &"crouch_walk_left", &"crouch_walk_right", &"walk_aim", &"walk_aim_back",
	&"walk_aim_left", &"walk_aim_right", &"fall", &"aim_pistol", &"drive", &"drive_left", &"drive_right"]
const LANDS: Array[StringName] = [&"land", &"land_hard"]
const AIR: Array[StringName] = [&"jump", &"jump_run", &"fall"]
const HOLDS: Array[StringName] = [&"hold_melee", &"hold_pistol", &"hold_item", &"aim_pistol"]
const ACTIONS: Array[StringName] = [&"attack_melee", &"fire_pistol", &"reload_pistol", &"fire_pistol_aim"]
const USES: Array[StringName] = [&"drink", &"eat", &"pickup", &"vault", &"climb", &"mantle_low", &"climb_high",
	&"car_enter", &"car_exit", &"trunk_open", &"trunk_close", &"build_fire"]
const UPPER_BONES := ["spine02", "spine01", "neck", "head", "jaw", "clavicle", "shoulder", "upperarm",
	"lowerarm", "wrist", "finger"]
const ACTION_BONES := ["spine04", "spine03"]

@export var blend_time := 0.22
@export var model_path: NodePath = ^"Model"

var _model: Node3D
var _anim: AnimationPlayer
var _tree: AnimationTree
var _current: StringName = &""
var _dead := false
var _airborne_time := 0.0
var _hold_amount := 0.0
var _hold_target := 0.0
var _wielded := -1
var _jacket: Node3D
var _backpack: Node3D
var _holster: Node3D
var _sockets := {}
var _weapon_nodes := {}   # slot -> Node3D
var _weapon_ids := {}     # slot -> StringName
var _flash_timer := 0.0
var _shirt: Node3D
var _prop: Node3D
var _prop_show_at := -1.0
var _prop_hide_at := -1.0
var _use_time := 0.0
var _jump_anim: StringName = &""     # pulo iniciado pelo jogador ("" = caiu de algum lugar)
var _model_basis := Basis()
var _jump_since := 0.0
var _lean_roll := 0.0
var _lean_pitch := 0.0
var _last_yaw := 0.0
var _last_speed := 0.0


func _ready() -> void:
	_model = get_node(model_path)
	_model_basis = _model.basis
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_jacket = _model.find_child("Jacket", true, false) as Node3D
	_backpack = _model.find_child("Backpack", true, false) as Node3D
	_holster = _model.find_child("Holster", true, false) as Node3D
	_shirt = _model.find_child("Shirt", true, false) as Node3D
	# peças pequenas não precisam projetar sombra (economiza uma passada de desenho)
	for small in ["Eyes", "Holster"]:
		var g := _model.find_child(small, true, false) as GeometryInstance3D
		if g:
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _holster:
		_holster.visible = false
	for socket in ["Socket_Hand_R", "Socket_Back", "Socket_Back_Pack", "Socket_Holster"]:
		_sockets[socket] = _model.find_child(socket, true, false)
	for anim_name in LOOPING:
		if _anim.has_animation(anim_name):
			_anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_build_tree()
	_set_loco(&"idle")


func _process(delta: float) -> void:
	if _flash_timer > 0.0:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			var weapon: Node3D = _weapon_nodes.get(ItemData.Slot.SIDEARM)
			if weapon and weapon.has_node("Flash"):
				(weapon.get_node("Flash") as Node3D).visible = false
	if _prop:
		_use_time += delta
		_prop.visible = _use_time >= _prop_show_at and _use_time < _prop_hide_at
		if _use_time >= _prop_hide_at:
			_prop.queue_free()
			_prop = null
	_hold_amount = move_toward(_hold_amount, _hold_target, delta * 5.0)
	_tree.set("parameters/hold/blend_amount", _hold_amount)


## move_dir: direção do movimento em relação ao corpo (x = direita, y = frente).
## aiming: arma em posição (andar mirando, mais baixo e cuidadoso).
func update_pose(ground_speed: float, _max_speed: float, grounded: bool, crouching: bool, delta: float,
		move_dir := Vector2(0, 1), aiming := false) -> void:
	if _dead:
		return
	_airborne_time = 0.0 if grounded else _airborne_time + delta
	_jump_since += delta
	# pulo do jogador termina quando volta ao chão (depois da preparação)
	if _jump_anim != &"" and grounded and _jump_since > _jump_wait + 0.2:
		_jump_anim = &""
	var target: StringName
	if _jump_anim != &"":
		target = &"fall" if _airborne_time > 0.75 else _jump_anim
	elif _airborne_time > 0.25:
		target = &"fall"     # saiu de uma beirada sem pular
	elif crouching:
		target = &"crouch_walk" if ground_speed > 0.2 else &"crouch_idle"
	elif ground_speed < 0.2:
		target = &"idle"
	elif ground_speed < 2.4:
		target = &"walk_aim" if aiming else &"walk"
	elif ground_speed < 4.7:
		target = &"run"
	else:
		target = &"sprint"
	var scale := 1.0
	if move_dir.length_squared() < 0.01:
		move_dir = Vector2(0, 1)
	move_dir = move_dir.normalized()
	if DIRECTIONAL_SPEED.has(target):
		_tree.set("parameters/loco_%s/blend_position" % target, move_dir)
		var n: Vector3 = DIRECTIONAL_SPEED[target]
		var w := absf(move_dir.x) + absf(move_dir.y)
		var nominal := (absf(move_dir.y) * (n.x if move_dir.y > 0.0 else n.y) + absf(move_dir.x) * n.z) / w
		scale = clampf(ground_speed / nominal, 0.6, 1.5)
	elif NOMINAL_SPEED.has(target):
		scale = clampf(ground_speed / NOMINAL_SPEED[target], 0.6, 1.5)
	_set_loco(target)
	_tree.set("parameters/loco_speed/scale", scale)
	# correndo muito rápido a arma fica mais "solta" (braços acompanham a corrida)
	if _wielded >= 0:
		_hold_target = 0.55 if target == &"sprint" else 1.0
	_update_lean(ground_speed if grounded else 0.0, delta)


var _jump_wait := 0.0


## Começa a animação de pulo (parado: com preparação; correndo: impulso numa perna só).
func start_jump(running: bool, anticipation := 0.0) -> void:
	_jump_anim = &"jump_run" if running else &"jump"
	_jump_wait = anticipation
	_jump_since = 0.0
	_current = &""
	_set_loco(_jump_anim, true)
	_tree.set("parameters/loco_speed/scale", 1.0)


## Aterrissagem: leve (joelhos absorvem) ou pesada (agacha fundo e apoia a mão no chão).
func play_land(hard: bool) -> void:
	if _dead:
		return
	_jump_anim = &""
	_tree.set("parameters/land_kind/transition_request", "land_hard" if hard else "land")
	_tree.set("parameters/land/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Inclinação procedural: tomba para o lado de dentro da curva e para frente ao acelerar
## (para trás ao frear). Mais forte quanto maior a velocidade.
func _update_lean(speed: float, delta: float) -> void:
	if delta <= 0.0:
		return
	var yaw := global_rotation.y
	var yaw_rate := wrapf(yaw - _last_yaw, -PI, PI) / delta
	_last_yaw = yaw
	var accel := (speed - _last_speed) / delta
	_last_speed = speed
	var target_roll := clampf(yaw_rate * speed * 0.035, -0.22, 0.22)
	var target_pitch := clampf(-accel * 0.018, -0.12, 0.12)
	if _current in [&"crouch_walk", &"crouch_idle"]:
		target_roll *= 0.5
	_lean_roll = lerpf(_lean_roll, target_roll, 1.0 - exp(-6.0 * delta))
	_lean_pitch = lerpf(_lean_pitch, target_pitch, 1.0 - exp(-5.0 * delta))
	# inclinação aplicada no modelo, girando em volta dos pés (origem do Visual)
	_model.basis = Basis(Vector3(0, 0, 1), _lean_roll) * Basis(Vector3(1, 0, 0), _lean_pitch) * _model_basis


## Mostra no corpo o que está equipado (mochila, jaqueta, armas guardadas).
func show_equipment(inventory: Inventory) -> void:
	if not is_node_ready():
		await ready
	if _backpack:
		_backpack.visible = inventory.equipped(ItemData.Slot.BACK) != null
	if _jacket:
		_jacket.visible = inventory.equipped(ItemData.Slot.BODY) != null
	if _shirt:
		_shirt.visible = not (_jacket and _jacket.visible)  # coberta pela jaqueta: não desenha
	_refresh_weapons(inventory)


## Qual arma está na mão (-1 = nenhuma). Reposiciona os modelos e a pose dos braços.
func set_wielded(slot: int, inventory: Inventory) -> void:
	if not is_node_ready():
		await ready
	_wielded = slot
	_hold_target = 1.0 if slot >= 0 or _held_prop != null else 0.0
	if slot < 0 and _held_prop != null:
		_tree.set("parameters/hold_kind/transition_request", "hold_item")
	elif slot == ItemData.Slot.MELEE:
		_tree.set("parameters/hold_kind/transition_request", "hold_melee")
	elif slot == ItemData.Slot.SIDEARM:
		_tree.set("parameters/hold_kind/transition_request", "aim_pistol" if _aim else "hold_pistol")
	_refresh_weapons(inventory)


## Mirar: arma sobe para a linha dos olhos (pose de mira) ou volta para a posição de pronto.
var _aim := false


func set_aim(on: bool) -> void:
	_aim = on
	if _wielded == ItemData.Slot.SIDEARM:
		_tree.set("parameters/hold_kind/transition_request", "aim_pistol" if on else "hold_pistol")


func is_aiming() -> bool:
	return _aim


## Golpe, disparo ou recarga (só tronco e braços; as pernas continuam).
func play_action(action: StringName) -> void:
	if _dead:
		return
	_tree.set("parameters/action_kind/transition_request", String(action))
	_tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


## Animação de corpo inteiro (beber, comer, pegar). Mostra o item na mão direita entre
## show_from e show_until (segundos). Devolve a duração da animação.
func play_use(anim_name: StringName, item: ItemData = null, show_from := 0.0, show_until := -1.0) -> float:
	if _dead or not _anim.has_animation(anim_name):
		return 0.0
	var length := _anim.get_animation(anim_name).length
	_tree.set("parameters/use_kind/transition_request", String(anim_name))
	_tree.set("parameters/use/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	if _prop:
		_prop.queue_free()
		_prop = null
	var hand := _sockets.get("Socket_Hand_R") as Node3D
	if item and hand:
		_prop = _make_prop(item)
		hand.add_child(_prop)
		_use_time = 0.0
		_prop_show_at = show_from
		_prop_hide_at = length - 0.15 if show_until < 0.0 else show_until
		_prop.visible = false
	return length


## Segurando um item consumível na mão (antes de decidir consumir ou guardar).
var _held_prop: Node3D


func set_holding(item: ItemData) -> void:
	if _held_prop:
		_held_prop.queue_free()
		_held_prop = null
	if item == null:
		if _wielded < 0:
			_hold_target = 0.0
		return
	var hand := _sockets.get("Socket_Hand_R") as Node3D
	if hand:
		_held_prop = _make_prop(item)
		hand.add_child(_held_prop)
	_tree.set("parameters/hold_kind/transition_request", "hold_item")
	_hold_target = 1.0


func is_holding() -> bool:
	return _held_prop != null


## Sentado dirigindo (pose do motorista) e quanto o volante está virado (-1..1).
func set_driving(on: bool) -> void:
	_tree.set("parameters/seat/blend_amount", 1.0 if on else 0.0)
	if on:
		_hold_target = 0.0
		_model.basis = _model_basis


func set_drive_steer(amount: float) -> void:
	_tree.set("parameters/drive_space/blend_position", clampf(amount, -1.0, 1.0))


func is_driving() -> bool:
	return float(_tree.get("parameters/seat/blend_amount")) > 0.5


func is_using() -> bool:
	return bool(_tree.get("parameters/use/active"))


## Modelo do item segurado na mão (o eixo +Y da mão é o do polegar: o item fica "em pé").
func _make_prop(d: ItemData) -> Node3D:
	if d.model:
		var m := d.model.instantiate() as Node3D
		for g in m.find_children("*", "GeometryInstance3D", true, false):
			(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		return m
	var mi := MeshInstance3D.new()
	var size := d.world_size
	match d.world_shape:
		ItemData.WorldShape.CYLINDER:
			var c := CylinderMesh.new()
			c.top_radius = size.x * 0.5
			c.bottom_radius = size.x * 0.5
			c.height = size.y
			c.radial_segments = 10
			mi.mesh = c
		_:
			var b := BoxMesh.new()
			b.size = Vector3(minf(size.x, 0.1), minf(size.y, 0.16), minf(size.z, 0.1))
			mi.mesh = b
	var mat := StandardMaterial3D.new()
	mat.albedo_color = d.world_color
	mat.roughness = 0.6
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = Vector3(0, 0.02, -0.02)
	return mi


func muzzle_flash() -> void:
	var weapon: Node3D = _weapon_nodes.get(ItemData.Slot.SIDEARM)
	if weapon == null:
		return
	var flash := weapon.get_node_or_null("Flash") as Node3D
	if flash == null:
		return
	flash.visible = true
	_flash_timer = 0.05


## Luz + brilho do disparo, criados uma vez junto com a arma e reaproveitados.
func _attach_flash(weapon: Node3D) -> void:
	var muzzle := weapon.find_child("Muzzle", true, false) as Node3D
	var flash := Node3D.new()
	flash.name = "Flash"
	flash.visible = false
	weapon.add_child(flash)
	if muzzle:
		flash.position = weapon.to_local(muzzle.global_position)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.45)
	light.light_energy = 3.0
	light.omni_range = 4.0
	light.shadow_enabled = false
	flash.add_child(light)
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.5, 0.9)
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flash.add_child(mesh)


func play_death() -> void:
	_dead = true
	_hold_target = 0.0
	if _model:
		_model.basis = _model_basis
	_tree.set("parameters/use/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	_tree.set("parameters/loco_speed/scale", 1.0)
	_set_loco(&"death")


func current_animation() -> StringName:
	return _current


func weapon_node(slot: int) -> Node3D:
	return _weapon_nodes.get(slot)


# ---------------------------------------------------------------- interno

func _set_loco(anim_name: StringName, force := false) -> void:
	if anim_name == _current and not force:
		return
	_current = anim_name
	_tree.set("parameters/loco/transition_request", String(anim_name))


func _refresh_weapons(inventory: Inventory) -> void:
	for slot in [ItemData.Slot.MELEE, ItemData.Slot.SIDEARM]:
		var stack := inventory.equipped(slot)
		var id: StringName = stack.item_id if stack else &""
		if _weapon_ids.get(slot, &"") != id:
			if _weapon_nodes.has(slot):
				(_weapon_nodes[slot] as Node).queue_free()
				_weapon_nodes.erase(slot)
			_weapon_ids[slot] = id
			var d := stack.data() if stack else null
			if d and d.model:
				var w := d.model.instantiate() as Node3D
				add_child(w)
				for g in w.find_children("*", "GeometryInstance3D", true, false):
					(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				if d.weapon_kind == ItemData.WeaponKind.PISTOL:
					_attach_flash(w)
				_weapon_nodes[slot] = w
		if not _weapon_nodes.has(slot):
			continue
		var socket := "Socket_Hand_R"
		if slot != _wielded:
			if slot == ItemData.Slot.SIDEARM:
				socket = "Socket_Holster"
			elif _backpack and _backpack.visible:
				socket = "Socket_Back_Pack"
			else:
				socket = "Socket_Back"
		var node := _weapon_nodes[slot] as Node3D
		if _sockets.get(socket) and node.get_parent() != _sockets[socket]:
			node.reparent(_sockets[socket], false)
		node.transform = Transform3D.IDENTITY
	if _holster:
		_holster.visible = inventory.equipped(ItemData.Slot.SIDEARM) != null


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()
	var loco := _transition(bt, "loco", LOCO, blend_time)
	var speed := AnimationNodeTimeScale.new()
	bt.add_node("loco_speed", speed)
	bt.connect_node("loco_speed", 0, "loco")
	_transition(bt, "hold_kind", HOLDS, 0.15)
	var hold := AnimationNodeBlend2.new()
	_filter(hold, UPPER_BONES)
	bt.add_node("hold", hold)
	bt.connect_node("hold", 0, "loco_speed")
	bt.connect_node("hold", 1, "hold_kind")
	_transition(bt, "action_kind", ACTIONS, 0.0)
	var action := AnimationNodeOneShot.new()
	action.fadein_time = 0.06
	action.fadeout_time = 0.18
	_filter(action, UPPER_BONES + ACTION_BONES)
	bt.add_node("action", action)
	bt.connect_node("action", 0, "hold")
	bt.connect_node("action", 1, "action_kind")
	_transition(bt, "land_kind", LANDS, 0.0)
	var land := AnimationNodeOneShot.new()
	land.fadein_time = 0.04
	land.fadeout_time = 0.15
	bt.add_node("land", land)
	bt.connect_node("land", 0, "action")
	bt.connect_node("land", 1, "land_kind")
	# sentado no carro: mistura de 3 poses pelo esterço (mãos acompanham o volante)
	var drive := AnimationNodeBlendSpace1D.new()
	drive.min_space = -1.0
	drive.max_space = 1.0
	for pair in [[&"drive_left", -1.0], [&"drive", 0.0], [&"drive_right", 1.0]]:
		if _anim.has_animation(pair[0]):
			var a := AnimationNodeAnimation.new()
			a.animation = pair[0]
			drive.add_blend_point(a, pair[1])
	bt.add_node("drive_space", drive)
	var seat := AnimationNodeBlend2.new()
	bt.add_node("seat", seat)
	bt.connect_node("seat", 0, "land")
	bt.connect_node("seat", 1, "drive_space")
	_transition(bt, "use_kind", USES, 0.0)
	var use := AnimationNodeOneShot.new()
	use.fadein_time = 0.2
	use.fadeout_time = 0.3
	bt.add_node("use", use)
	bt.connect_node("use", 0, "seat")
	bt.connect_node("use", 1, "use_kind")
	bt.connect_node("output", 0, "use")
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = bt
	_anim.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)
	_tree.active = true
	_tree.set("parameters/hold/blend_amount", 0.0)
	_tree.set("parameters/loco_speed/scale", 1.0)
	_tree.set("parameters/seat/blend_amount", 0.0)
	var _unused := loco


func _transition(bt: AnimationNodeBlendTree, node_name: String, anims: Array[StringName], xfade: float) -> AnimationNodeTransition:
	var t := AnimationNodeTransition.new()
	t.xfade_time = xfade
	t.allow_transition_to_self = node_name == "loco"
	for anim_name in anims:
		t.add_input(String(anim_name))
	bt.add_node(node_name, t)
	for i in anims.size():
		var n := "%s_%s" % [node_name, anims[i]]
		if node_name == "loco" and BLEND_SPACES.has(anims[i]):
			bt.add_node(n, _blend_space(BLEND_SPACES[anims[i]]))
		else:
			var a := AnimationNodeAnimation.new()
			a.animation = anims[i]
			bt.add_node(n, a)
		bt.connect_node(node_name, i, n)
	return t


func _blend_space(points: Dictionary) -> AnimationNodeBlendSpace2D:
	var bs := AnimationNodeBlendSpace2D.new()
	bs.min_space = Vector2(-1, -1)
	bs.max_space = Vector2(1, 1)
	for anim_name in points:
		if not _anim.has_animation(anim_name):
			continue
		var a := AnimationNodeAnimation.new()
		a.animation = anim_name
		bs.add_blend_point(a, points[anim_name])
	bs.sync = true  # ciclos sincronizados: as pernas não "embaralham" na mistura
	return bs


## Liga o filtro só nos ossos do tronco/braços (as pernas continuam com a locomoção).
func _filter(node: AnimationNode, prefixes: Array) -> void:
	node.filter_enabled = true
	var anim := _anim.get_animation(&"hold_melee")
	for i in anim.get_track_count():
		var path := anim.track_get_path(i)
		var bone := path.get_concatenated_subnames()
		for prefix in prefixes:
			if bone.begins_with(prefix):
				node.set_filter_path(path, true)
				break
