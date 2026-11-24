class_name InventoryScreen
extends Control
## Tela de inventário feita para toque: toque num item para selecionar e use os
## botões grandes do painel à direita (menu contextual) — sem depender de arrastar.

const SLOT_SIZE := Vector2(108, 108)
const SLOT_NAMES := {ItemData.Slot.BACK: "Costas", ItemData.Slot.BODY: "Corpo"}

var _player: PlayerController
var _selected_index := -1
var _selected_slot := -1

var _grid: GridContainer
var _empty_label: Label
var _weight_label: Label
var _weight_bar: ProgressBar
var _equip_buttons := {}
var _detail_icon: TextureRect
var _detail_name: Label
var _detail_category: Label
var _detail_desc: Label
var _detail_stats: Label
var _btn_primary: Button
var _btn_drop_one: Button
var _btn_drop_all: Button


func _ready() -> void:
	visible = false
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_bind.call_deferred()


func _bind() -> void:
	_player = get_tree().get_first_node_in_group("player") as PlayerController
	if _player:
		_player.inventory.changed.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		close() if visible else open()
		get_viewport().set_input_as_handled()


func open() -> void:
	if _player == null or _player.stats.is_dead:
		return
	_selected_index = -1
	_selected_slot = -1
	visible = true
	_refresh()
	Events.modal_changed.emit(true)


func close() -> void:
	visible = false
	Events.modal_changed.emit(false)


# ---------------------------------------------------------------- montagem

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	panel.add_child(root)

	# Cabeçalho: título, peso, fechar
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	root.add_child(header)
	var title := Label.new()
	title.text = "INVENTÁRIO"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", UiTheme.ACCENT)
	header.add_child(title)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	var weight_box := VBoxContainer.new()
	weight_box.custom_minimum_size.x = 260
	header.add_child(weight_box)
	_weight_label = Label.new()
	_weight_label.add_theme_font_size_override("font_size", 15)
	weight_box.add_child(_weight_label)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size.y = 10
	_weight_bar.add_theme_stylebox_override("background", UiTheme.box(Color(0, 0, 0, 0.5), 3, Color.TRANSPARENT, 0))
	_weight_bar.add_theme_stylebox_override("fill", UiTheme.box(UiTheme.ACCENT, 3, Color.TRANSPARENT, 0))
	weight_box.add_child(_weight_bar)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.icon = load("res://assets/icons/ui/close.svg")
	close_btn.expand_icon = true
	close_btn.custom_minimum_size = Vector2(60, 60)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	# Equipamento
	var equip_col := VBoxContainer.new()
	equip_col.add_theme_constant_override("separation", 10)
	body.add_child(equip_col)
	var equip_title := Label.new()
	equip_title.text = "EQUIPADO"
	equip_title.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	equip_title.add_theme_font_size_override("font_size", 14)
	equip_col.add_child(equip_title)
	for slot in SLOT_NAMES:
		var b := _slot_button()
		b.name = "Equip%s" % SLOT_NAMES[slot]
		b.pressed.connect(_select.bind(-1, slot))
		equip_col.add_child(b)
		_equip_buttons[slot] = b

	# Itens carregados
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	var scroll_box := VBoxContainer.new()
	scroll_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_box)
	_grid = GridContainer.new()
	_grid.columns = 5
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	scroll_box.add_child(_grid)
	_empty_label = Label.new()
	_empty_label.text = "Nada aqui. Procure suprimentos pelo mundo."
	_empty_label.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	scroll_box.add_child(_empty_label)

	# Detalhes + ações (menu contextual)
	var detail := PanelContainer.new()
	detail.custom_minimum_size.x = 320
	detail.add_theme_stylebox_override("panel", UiTheme.box(Color(0.12, 0.13, 0.11), 8, Color.TRANSPARENT, 14))
	body.add_child(detail)
	var dbox := VBoxContainer.new()
	dbox.add_theme_constant_override("separation", 8)
	detail.add_child(dbox)
	_detail_icon = TextureRect.new()
	_detail_icon.custom_minimum_size = Vector2(72, 72)
	_detail_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_detail_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	dbox.add_child(_detail_icon)
	_detail_name = Label.new()
	_detail_name.add_theme_font_size_override("font_size", 21)
	_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dbox.add_child(_detail_name)
	_detail_category = Label.new()
	_detail_category.add_theme_color_override("font_color", UiTheme.ACCENT)
	_detail_category.add_theme_font_size_override("font_size", 14)
	dbox.add_child(_detail_category)
	_detail_desc = Label.new()
	_detail_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_desc.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	_detail_desc.add_theme_font_size_override("font_size", 15)
	dbox.add_child(_detail_desc)
	_detail_stats = Label.new()
	_detail_stats.add_theme_font_size_override("font_size", 15)
	dbox.add_child(_detail_stats)
	var fill := Control.new()
	fill.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dbox.add_child(fill)
	_btn_primary = _action_button("PrimaryButton", dbox, _on_primary)
	_btn_drop_one = _action_button("DropOneButton", dbox, _on_drop_one)
	_btn_drop_all = _action_button("DropAllButton", dbox, _on_drop_all)


func _slot_button() -> Button:
	var b := Button.new()
	b.custom_minimum_size = SLOT_SIZE
	b.expand_icon = true
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
	b.add_theme_constant_override("icon_max_width", 56)
	b.add_theme_font_size_override("font_size", 14)
	b.clip_text = true
	return b


func _action_button(node_name: String, parent: Node, callback: Callable) -> Button:
	var b := Button.new()
	b.name = node_name
	b.custom_minimum_size.y = 56
	b.add_theme_font_size_override("font_size", 18)
	b.pressed.connect(callback)
	parent.add_child(b)
	return b


# ---------------------------------------------------------------- atualização

func _refresh() -> void:
	if _player == null or not visible:
		return
	var inv := _player.inventory
	if _selected_index >= inv.stacks.size():
		_selected_index = inv.stacks.size() - 1
	if _selected_slot >= 0 and inv.equipped(_selected_slot) == null:
		_selected_slot = -1

	_weight_label.text = "Peso  %.1f / %.1f kg" % [inv.total_weight(), inv.capacity()]
	_weight_bar.max_value = inv.capacity()
	_weight_bar.value = inv.total_weight()

	for slot in _equip_buttons:
		var b: Button = _equip_buttons[slot]
		var s := inv.equipped(slot)
		b.icon = s.data().icon if s and s.data() else null
		b.text = SLOT_NAMES[slot] if s == null else ""
		_style_slot(b, _selected_slot == slot, s != null)

	for child in _grid.get_children():
		child.queue_free()
	for i in inv.stacks.size():
		var s := inv.stacks[i]
		var d := s.data()
		var b := _slot_button()
		b.name = "Slot%d" % i
		b.icon = d.icon if d else null
		b.text = "x%d" % s.quantity if s.quantity > 1 else ""
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER if s.quantity <= 1 else VERTICAL_ALIGNMENT_TOP
		_style_slot(b, i == _selected_index and _selected_slot < 0, true)
		b.pressed.connect(_select.bind(i, -1))
		_grid.add_child(b)
	_empty_label.visible = inv.stacks.is_empty()
	_refresh_detail()


func _style_slot(b: Button, selected: bool, filled: bool) -> void:
	var color := UiTheme.SLOT_SELECTED if selected else UiTheme.SLOT
	if not filled:
		color = Color(0.08, 0.09, 0.08)
	var border := UiTheme.ACCENT if selected else Color(1, 1, 1, 0.05)
	for state in ["normal", "hover", "pressed"]:
		b.add_theme_stylebox_override(state, UiTheme.box(color, 6, border, 6))
	b.add_theme_color_override("font_color", UiTheme.TEXT_DIM if not filled else UiTheme.TEXT)


func _select(index: int, slot: int) -> void:
	_selected_index = index
	_selected_slot = slot
	_refresh()


func _selected_stack() -> ItemStack:
	var inv := _player.inventory
	if _selected_slot >= 0:
		return inv.equipped(_selected_slot)
	if _selected_index >= 0 and _selected_index < inv.stacks.size():
		return inv.stacks[_selected_index]
	return null


func _refresh_detail() -> void:
	var s := _selected_stack()
	var d := s.data() if s else null
	var has := d != null
	_detail_icon.texture = d.icon if has else null
	_detail_name.text = d.display_name if has else "Selecione um item"
	_detail_category.text = d.category_name().to_upper() if has else ""
	_detail_desc.text = d.description if has else "Toque em um item para ver detalhes e ações."
	var stats := ""
	if has:
		stats = "Peso: %.2f kg" % d.weight
		if s.quantity > 1:
			stats += "   ·   Qtd: %d" % s.quantity
		if d.max_durability > 0.0:
			stats += "\nEstado: %s (%d%%)" % [_condition_name(s.durability), roundi(s.durability)]
		if d.capacity_bonus > 0.0:
			stats += "\nCapacidade: +%.0f kg" % d.capacity_bonus
	_detail_stats.text = stats

	var equipped_selected := _selected_slot >= 0
	_btn_primary.visible = has and (equipped_selected or d.is_usable() or d.is_equipment())
	if _btn_primary.visible:
		_btn_primary.text = "Desequipar" if equipped_selected else (d.use_verb if d.is_usable() else "Equipar")
	_btn_drop_one.visible = has
	_btn_drop_one.text = "Largar 1" if has and s.quantity > 1 else "Largar"
	_btn_drop_all.visible = has and s.quantity > 1
	_btn_drop_all.text = "Largar todos (%d)" % s.quantity if has else ""


func _condition_name(value: float) -> String:
	if value >= 70.0:
		return "Bom"
	if value >= 40.0:
		return "Desgastado"
	if value >= 10.0:
		return "Danificado"
	return "Arruinado"


# ---------------------------------------------------------------- ações

func _on_primary() -> void:
	if _selected_slot >= 0:
		_player.unequip_item(_selected_slot)
		return
	var s := _selected_stack()
	if s == null:
		return
	var d := s.data()
	if d.is_usable():
		_player.use_item(_selected_index)
	elif d.is_equipment():
		var slot := d.equip_slot
		if _player.equip_item(_selected_index):
			_selected_index = -1
			_selected_slot = slot
			_refresh()


func _on_drop_one() -> void:
	if _selected_slot >= 0:
		_player.drop_equipped(_selected_slot)
	elif _selected_index >= 0:
		_player.drop_item(_selected_index, 1)


func _on_drop_all() -> void:
	var s := _selected_stack()
	if s and _selected_slot < 0:
		_player.drop_item(_selected_index, s.quantity)
