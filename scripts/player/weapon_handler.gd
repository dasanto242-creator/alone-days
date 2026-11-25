class_name WeaponHandler
extends Node
## Empunhar, atacar, atirar e recarregar. Fica como filho do Player.
## Armas guardadas ficam no corpo (arma branca nas costas, pistola no coldre);
## o botão "Arma" alterna entre mãos livres -> arma branca -> pistola.

const MELEE_HIT_DELAY := 0.33   # momento do golpe dentro da animação (s)
const RELOAD_TIME := 1.2

var wielded_slot := -1           # -1 = mãos livres, ou ItemData.Slot.MELEE / SIDEARM
var _cooldown := 0.0
var _busy := 0.0                 # golpe ou recarga em andamento
var _player: PlayerController


func _ready() -> void:
	_player = get_parent() as PlayerController
	_player.inventory.changed.connect(_on_inventory_changed)
	_emit_state.call_deferred()


func _physics_process(delta: float) -> void:
	_cooldown = maxf(_cooldown - delta, 0.0)
	_busy = maxf(_busy - delta, 0.0)
	if _player.stats.is_dead:
		return
	if Input.is_action_just_pressed("weapon"):
		cycle_weapon()
	if Input.is_action_just_pressed("reload"):
		reload()
	if Input.is_action_just_pressed("attack"):
		attack()


func wielded_stack() -> ItemStack:
	return _player.inventory.equipped(wielded_slot) if wielded_slot >= 0 else null


func wielded_data() -> ItemData:
	var s := wielded_stack()
	return s.data() if s else null


func has_weapons() -> bool:
	var inv := _player.inventory
	return inv.equipped(ItemData.Slot.MELEE) != null or inv.equipped(ItemData.Slot.SIDEARM) != null


## Mãos livres -> arma branca -> pistola -> mãos livres (pula o que não estiver equipado).
func cycle_weapon() -> void:
	if _busy > 0.0:
		return
	var order := [-1, ItemData.Slot.MELEE, ItemData.Slot.SIDEARM]
	var i := order.find(wielded_slot)
	for step in range(1, order.size() + 1):
		var slot: int = order[(i + step) % order.size()]
		if slot == -1 or _player.inventory.equipped(slot) != null:
			set_wielded(slot)
			return


func set_wielded(slot: int) -> void:
	wielded_slot = slot
	_player.face_camera = slot != -1  # postura de combate: corpo acompanha a câmera
	_player.animator().set_wielded(slot, _player.inventory)
	_emit_state()


func attack() -> void:
	var d := wielded_data()
	if d == null or _cooldown > 0.0 or _busy > 0.0:
		return
	if d.weapon_kind == ItemData.WeaponKind.MELEE:
		_melee(d)
	elif d.weapon_kind == ItemData.WeaponKind.PISTOL:
		_shoot(d)


func reload() -> void:
	var s := wielded_stack()
	var d := wielded_data()
	if d == null or d.weapon_kind != ItemData.WeaponKind.PISTOL or _busy > 0.0:
		return
	var missing := d.magazine_size - s.loaded
	var available := _player.inventory.count_of(d.ammo_item)
	if missing <= 0:
		return
	if available <= 0:
		Events.notify.emit("Sem munição na mochila")
		return
	_busy = RELOAD_TIME
	_player.animator().play_action(&"reload_pistol")
	await get_tree().create_timer(RELOAD_TIME * 0.7).timeout
	if wielded_stack() != s:
		return
	s.loaded += _player.inventory.consume(d.ammo_item, mini(missing, available))
	_emit_state()


# ---------------------------------------------------------------- golpe

func _melee(d: ItemData) -> void:
	if _player.stats.stamina < d.attack_stamina:
		Events.notify.emit("Sem fôlego")
		return
	_player.stats.spend_stamina(d.attack_stamina)
	_cooldown = d.attack_cooldown
	_busy = d.attack_cooldown * 0.8
	_player.animator().play_action(&"attack_melee")
	await get_tree().create_timer(MELEE_HIT_DELAY).timeout
	if _player.stats.is_dead:
		return
	var forward := _player.facing()
	var center := _player.global_position + Vector3.UP * 1.1 + forward * d.attack_range * 0.6
	var shape := SphereShape3D.new()
	shape.radius = d.attack_range * 0.5
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis(), center)
	query.collision_mask = 1 | 4
	query.exclude = [_player.get_rid()]
	var hit_something := false
	for result in _player.get_world_3d().direct_space_state.intersect_shape(query, 8):
		var target: Object = result.collider
		if target.has_method("apply_damage"):
			target.apply_damage(d.damage, _player, center)
			Events.hit_landed.emit(target, d.damage, center)
			hit_something = true
	if hit_something:
		GameSettings.vibrate(25, 0.7)
		_wear(wielded_stack(), 2.0)


func _wear(s: ItemStack, amount: float) -> void:
	if s == null or s.data().max_durability <= 0.0:
		return
	s.durability = maxf(s.durability - amount, 0.0)
	if s.durability <= 0.0:
		Events.notify.emit("%s quebrou" % s.data().display_name)
		_player.inventory.take_equipment(wielded_slot)
		set_wielded(-1)


# ---------------------------------------------------------------- tiro

func _shoot(d: ItemData) -> void:
	var s := wielded_stack()
	if s.loaded <= 0:
		_cooldown = 0.3
		Events.notify.emit("Sem munição — recarregue" if _player.inventory.count_of(d.ammo_item) > 0 else "Sem munição")
		return
	s.loaded -= 1
	_cooldown = d.attack_cooldown
	_player.snap_to_camera()
	_player.animator().play_action(&"fire_pistol")
	_player.animator().muzzle_flash()
	_player.camera_rig().add_recoil(1.6)
	GameSettings.vibrate(18, 0.6)
	# o tiro sai do centro da tela (mira), a partir da câmera
	var cam := _player.get_viewport().get_camera_3d()
	var from := cam.global_position
	var dir := -cam.global_basis.z
	var query := PhysicsRayQueryParameters3D.create(from, from + dir * d.attack_range, 1 | 4)
	query.exclude = [_player.get_rid()]
	var hit := _player.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		ImpactEffect.spawn(_player.get_parent(), hit.position, hit.normal)
		if hit.collider.has_method("apply_damage"):
			hit.collider.apply_damage(d.damage, _player, hit.position)
			Events.hit_landed.emit(hit.collider, d.damage, hit.position)
	_emit_state()


# ---------------------------------------------------------------- estado

func _on_inventory_changed() -> void:
	# arma que estava na mão foi largada/desequipada
	if wielded_slot >= 0 and _player.inventory.equipped(wielded_slot) == null:
		set_wielded(-1)
	else:
		_player.animator().set_wielded(wielded_slot, _player.inventory)
		_emit_state()


func ammo_text() -> String:
	var d := wielded_data()
	if d == null or d.weapon_kind != ItemData.WeaponKind.PISTOL:
		return ""
	return "%d/%d  (+%d)" % [wielded_stack().loaded, d.magazine_size, _player.inventory.count_of(d.ammo_item)]


func _emit_state() -> void:
	var d := wielded_data()
	Events.weapon_state_changed.emit(d.weapon_kind if d else ItemData.WeaponKind.NONE, ammo_text(), has_weapons())
