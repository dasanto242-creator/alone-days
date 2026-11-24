class_name SurvivorAnimator
extends Node3D
## Anima o modelo 3D do sobrevivente e posiciona armas/equipamentos no corpo.
##
## Camadas (AnimationTree):
##   1. Locomoção (pernas e corpo): idle, walk, run, sprint, agachado, pulo, morte.
##      A velocidade de reprodução acompanha a velocidade real (pés não deslizam).
##   2. Segurar arma (só tronco e braços): hold_melee / hold_pistol.
##   3. Ação (one-shot, tronco e braços): golpe, disparo, recarga.

## Velocidade no chão (m/s) de cada ciclo: distância do pé no apoio / tempo de apoio.
const NOMINAL_SPEED := {&"walk": 1.3, &"run": 3.57, &"sprint": 5.78, &"crouch_walk": 0.88}
const LOCO: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"crouch_idle", &"crouch_walk", &"jump", &"death"]
const LOOPING: Array[StringName] = [&"idle", &"walk", &"run", &"sprint", &"crouch_idle", &"crouch_walk",
	&"hold_melee", &"hold_pistol"]
const HOLDS: Array[StringName] = [&"hold_melee", &"hold_pistol"]
const ACTIONS: Array[StringName] = [&"attack_melee", &"fire_pistol", &"reload_pistol"]
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


func _ready() -> void:
	_model = get_node(model_path)
	_anim = _model.find_child("AnimationPlayer", true, false) as AnimationPlayer
	_jacket = _model.find_child("Jacket", true, false) as Node3D
	_backpack = _model.find_child("Backpack", true, false) as Node3D
	_holster = _model.find_child("Holster", true, false) as Node3D
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
	_hold_amount = move_toward(_hold_amount, _hold_target, delta * 5.0)
	_tree.set("parameters/hold/blend_amount", _hold_amount)


func update_pose(ground_speed: float, _max_speed: float, grounded: bool, crouching: bool, delta: float) -> void:
	if _dead:
		return
	_airborne_time = 0.0 if grounded else _airborne_time + delta
	var target: StringName
	if _airborne_time > 0.12:
		target = &"jump"
	elif crouching:
		target = &"crouch_walk" if ground_speed > 0.2 else &"crouch_idle"
	elif ground_speed < 0.2:
		target = &"idle"
	elif ground_speed < 2.4:
		target = &"walk"
	elif ground_speed < 4.7:
		target = &"run"
	else:
		target = &"sprint"
	var scale := 1.0
	if NOMINAL_SPEED.has(target):
		scale = clampf(ground_speed / NOMINAL_SPEED[target], 0.6, 1.5)
	_set_loco(target)
	_tree.set("parameters/loco_speed/scale", scale)
	# correndo muito rápido a arma fica mais "solta" (braços acompanham a corrida)
	if _wielded >= 0:
		_hold_target = 0.55 if target == &"sprint" else 1.0


## Mostra no corpo o que está equipado (mochila, jaqueta, armas guardadas).
func show_equipment(inventory: Inventory) -> void:
	if not is_node_ready():
		await ready
	if _backpack:
		_backpack.visible = inventory.equipped(ItemData.Slot.BACK) != null
	if _jacket:
		_jacket.visible = inventory.equipped(ItemData.Slot.BODY) != null
	_refresh_weapons(inventory)


## Qual arma está na mão (-1 = nenhuma). Reposiciona os modelos e a pose dos braços.
func set_wielded(slot: int, inventory: Inventory) -> void:
	if not is_node_ready():
		await ready
	_wielded = slot
	_hold_target = 1.0 if slot >= 0 else 0.0
	if slot == ItemData.Slot.MELEE:
		_tree.set("parameters/hold_kind/transition_request", "hold_melee")
	elif slot == ItemData.Slot.SIDEARM:
		_tree.set("parameters/hold_kind/transition_request", "hold_pistol")
	_refresh_weapons(inventory)


## Golpe, disparo ou recarga (só tronco e braços; as pernas continuam).
func play_action(action: StringName) -> void:
	if _dead:
		return
	_tree.set("parameters/action_kind/transition_request", String(action))
	_tree.set("parameters/action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)


func muzzle_flash() -> void:
	var weapon: Node3D = _weapon_nodes.get(ItemData.Slot.SIDEARM)
	if weapon == null:
		return
	var muzzle := weapon.find_child("Muzzle", true, false) as Node3D
	var at := muzzle.global_position if muzzle else weapon.global_position
	var flash := Node3D.new()
	get_tree().current_scene.add_child(flash)
	flash.global_position = at
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.45)
	light.light_energy = 3.0
	light.omni_range = 4.0
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
	flash.add_child(mesh)
	get_tree().create_timer(0.05).timeout.connect(flash.queue_free)


func play_death() -> void:
	_dead = true
	_hold_target = 0.0
	_tree.set("parameters/loco_speed/scale", 1.0)
	_set_loco(&"death")


func current_animation() -> StringName:
	return _current


func weapon_node(slot: int) -> Node3D:
	return _weapon_nodes.get(slot)


# ---------------------------------------------------------------- interno

func _set_loco(anim_name: StringName) -> void:
	if anim_name == _current:
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
				_weapon_nodes[slot] = d.model.instantiate()
				add_child(_weapon_nodes[slot])
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
	bt.connect_node("output", 0, "action")
	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = bt
	_anim.get_parent().add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_anim)
	_tree.active = true
	_tree.set("parameters/hold/blend_amount", 0.0)
	_tree.set("parameters/loco_speed/scale", 1.0)
	var _unused := loco


func _transition(bt: AnimationNodeBlendTree, node_name: String, anims: Array[StringName], xfade: float) -> AnimationNodeTransition:
	var t := AnimationNodeTransition.new()
	t.xfade_time = xfade
	for anim_name in anims:
		t.add_input(String(anim_name))
	bt.add_node(node_name, t)
	for i in anims.size():
		var a := AnimationNodeAnimation.new()
		a.animation = anims[i]
		var n := "%s_%s" % [node_name, anims[i]]
		bt.add_node(n, a)
		bt.connect_node(node_name, i, n)
	return t


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
