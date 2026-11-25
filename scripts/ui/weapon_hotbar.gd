class_name WeaponHotbar
extends HBoxContainer
## Barra de armas no centro, embaixo da tela. Mostra até 4 armas (as do corpo primeiro, depois as
## da mochila). Toque: empunha; toque de novo: guarda. Arma da mochila troca com a do corpo.
## Teclado: 1 a 4.

const SLOT_SIZE := Vector2(76, 76)

var _slots: Array[Button] = []
var _player: PlayerController
var _style_normal: StyleBoxFlat
var _style_active: StyleBoxFlat


func _ready() -> void:
	add_to_group("touch_blocker")
	alignment = BoxContainer.ALIGNMENT_CENTER
	add_theme_constant_override("separation", 8)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_normal = _style(Color(0.08, 0.09, 0.08, 0.62), Color(1, 1, 1, 0.18))
	_style_active = _style(Color(0.16, 0.2, 0.12, 0.8), Color(0.62, 0.8, 0.3, 0.95))
	for i in 4:
		var b := Button.new()
		b.name = "Slot%d" % (i + 1)
		b.custom_minimum_size = SLOT_SIZE
		b.focus_mode = Control.FOCUS_NONE
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
		b.add_theme_constant_override("icon_max_width", 58)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, _style_normal)
		var key := Label.new()
		key.name = "Key"
		key.text = str(i + 1)
		key.position = Vector2(6, 2)
		key.add_theme_font_size_override("font_size", 12)
		key.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		key.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(key)
		var info := Label.new()
		info.name = "Info"
		info.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		info.size = Vector2(SLOT_SIZE.x - 8, 16)
		info.position = Vector2(2, SLOT_SIZE.y - 19)
		info.add_theme_font_size_override("font_size", 12)
		info.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		info.add_theme_constant_override("shadow_offset_x", 1)
		info.add_theme_constant_override("shadow_offset_y", 1)
		info.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(info)
		var idx := i
		b.pressed.connect(func() -> void: _on_slot_pressed(idx))
		add_child(b)
		_slots.append(b)
	Events.weapons_changed.connect(refresh)
	Events.weapon_state_changed.connect(func(_k: int, _a: String, _h: bool) -> void: refresh())
	Events.modal_changed.connect(func(open: bool) -> void: modulate.a = 0.0 if open else 1.0)
	refresh.call_deferred()


func _style(bg: Color, border: Color) -> StyleBoxFlat:
	var st := StyleBoxFlat.new()
	st.bg_color = bg
	st.border_color = border
	st.set_border_width_all(2)
	st.set_corner_radius_all(10)
	return st


func _handler() -> WeaponHandler:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as PlayerController
	return _player.get_node_or_null("Weapons") as WeaponHandler if _player else null


func refresh() -> void:
	var weapons := _handler()
	if weapons == null:
		visible = false
		return
	var entries := weapons.weapon_entries()
	visible = not entries.is_empty()
	for i in _slots.size():
		var b := _slots[i]
		var info := b.get_node("Info") as Label
		if i >= entries.size():
			b.visible = false
			continue
		b.visible = true
		var e: Dictionary = entries[i]
		var stack: ItemStack = e.stack
		var d := stack.data()
		b.icon = d.icon if d else null
		b.tooltip_text = d.display_name if d else ""
		var active: bool = e.equipped and weapons.wielded_slot == e.slot
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, _style_active if active else _style_normal)
		b.modulate = Color(1, 1, 1, 1.0 if e.equipped else 0.7)  # da mochila: mais apagada
		if d and d.weapon_kind == ItemData.WeaponKind.PISTOL:
			info.text = "%d/%d" % [stack.loaded, d.magazine_size]
		elif d and d.max_durability > 0.0:
			info.text = "%d%%" % roundi(stack.durability)
		else:
			info.text = ""


func _on_slot_pressed(i: int) -> void:
	var weapons := _handler()
	if weapons == null:
		return
	GameSettings.vibrate()
	Sfx.play_2d(&"ui_click", -6.0)
	weapons.select_entry(i)
	refresh()
