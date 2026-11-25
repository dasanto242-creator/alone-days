class_name WeaponHud
extends Control
## Mira no centro da tela (com pistola em mãos) e contador de munição.
## A mira fica vermelha por um instante quando um tiro/golpe acerta algo.

var _kind := ItemData.WeaponKind.NONE
var _hit_flash := 0.0
var _ammo_label: Label
var _gap := 6.0
var _weapons: WeaponHandler


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ammo_label = Label.new()
	_ammo_label.add_theme_font_size_override("font_size", 18)
	_ammo_label.add_theme_color_override("font_color", UiTheme.TEXT)
	_ammo_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	_ammo_label.add_theme_constant_override("shadow_offset_x", 1)
	_ammo_label.add_theme_constant_override("shadow_offset_y", 1)
	_ammo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ammo_label.anchor_left = 1.0
	_ammo_label.anchor_right = 1.0
	_ammo_label.offset_left = -260
	_ammo_label.offset_right = -20
	_ammo_label.offset_top = 120
	_ammo_label.offset_bottom = 146
	add_child(_ammo_label)
	Events.weapon_state_changed.connect(_on_weapon_state_changed)
	Events.hit_landed.connect(func(_t: Node, _a: float, _p: Vector3) -> void: _hit_flash = 0.25)
	Events.modal_changed.connect(func(open: bool) -> void: visible = not open)


func _process(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash = maxf(_hit_flash - delta, 0.0)
		queue_redraw()
	if _kind != ItemData.WeaponKind.PISTOL:
		return
	# a mira abre quando a arma fica imprecisa (andando, correndo, pulando) e fecha parado
	if _weapons == null or not is_instance_valid(_weapons):
		var p := get_tree().get_first_node_in_group("player")
		_weapons = p.get_node_or_null("Weapons") as WeaponHandler if p else null
	if _weapons:
		var cam := get_viewport().get_camera_3d()
		var px_per_deg := size.y / (cam.fov if cam else 70.0)
		var target := 4.0 + _weapons.current_spread_degrees() * px_per_deg
		var g := lerpf(_gap, target, 1.0 - exp(-10.0 * delta))
		if absf(g - _gap) > 0.05:
			_gap = g
			queue_redraw()


func _on_weapon_state_changed(kind: int, ammo_text: String, _has_weapons: bool) -> void:
	_kind = kind
	_ammo_label.text = ("PISTOLA  " + ammo_text) if not ammo_text.is_empty() else ""
	queue_redraw()


func _draw() -> void:
	if _kind != ItemData.WeaponKind.PISTOL:
		return
	var c := size * 0.5
	var color := UiTheme.DANGER if _hit_flash > 0.0 else Color(0.92, 0.92, 0.86, 0.85)
	var gap := _gap
	var length := 9.0
	for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(c + dir * gap, c + dir * (gap + length), Color(0, 0, 0, 0.5), 4.0)
		draw_line(c + dir * gap, c + dir * (gap + length), color, 2.0)
	draw_circle(c, 1.8, color)
