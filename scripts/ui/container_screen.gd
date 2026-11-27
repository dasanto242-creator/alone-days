class_name ContainerScreen
extends Control
## Tela de troca entre a mochila e um recipiente (porta-malas do carro).
## Toque num item da mochila para guardar; toque num item do recipiente para pegar.
## "1x" move uma unidade; o botão grande move a pilha inteira (o que couber).

const SLOT_SIZE := Vector2(92, 92)

var _player: PlayerController
var _container: Inventory
var _title: Label
var _left_grid: GridContainer
var _right_grid: GridContainer
var _left_weight: Label
var _right_weight: Label
var _one_toggle: CheckButton


func _ready() -> void:
	visible = false
	theme = UiTheme.get_theme()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	Events.container_requested.connect(open)


func open(inventory: Inventory, title: String) -> void:
	_player = get_tree().get_first_node_in_group("player") as PlayerController
	if _player == null or _player.stats.is_dead:
		return
	_container = inventory
	_title.text = title.to_upper()
	if not _player.inventory.changed.is_connected(_refresh):
		_player.inventory.changed.connect(_refresh)
	if not _container.changed.is_connected(_refresh):
		_container.changed.connect(_refresh)
	visible = true
	_refresh()
	Events.modal_changed.emit(true)


func close() -> void:
	if not visible:
		return
	visible = false
	if _container and _container.changed.is_connected(_refresh):
		_container.changed.disconnect(_refresh)
	Events.modal_changed.emit(false)


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if visible and (event.is_action_pressed("inventory") or event.is_action_pressed("ui_cancel")):
		close()
		get_viewport().set_input_as_handled()


func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.02, 0.72)
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
	root.add_theme_constant_override("separation", 12)
	panel.add_child(root)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 18)
	root.add_child(header)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 24)
	_title.add_theme_color_override("font_color", UiTheme.ACCENT)
	header.add_child(_title)
	var hint := Label.new()
	hint.text = "Toque num item para passar para o outro lado"
	hint.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 15)
	header.add_child(hint)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)
	_one_toggle = CheckButton.new()
	_one_toggle.text = "Mover 1 por vez"
	_one_toggle.add_theme_font_size_override("font_size", 16)
	header.add_child(_one_toggle)
	var close_btn := Button.new()
	close_btn.name = "CloseButton"
	close_btn.icon = load("res://assets/icons/ui/close.svg")
	close_btn.expand_icon = true
	close_btn.custom_minimum_size = Vector2(60, 60)
	close_btn.pressed.connect(close)
	header.add_child(close_btn)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	root.add_child(body)
	var left := _column(body, "MOCHILA")
	_left_weight = left[0]
	_left_grid = left[1]
	var arrow := Label.new()
	arrow.text = "⇄"
	arrow.add_theme_font_size_override("font_size", 34)
	arrow.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	body.add_child(arrow)
	var right := _column(body, "GUARDADO")
	_right_weight = right[0]
	_right_grid = right[1]


func _column(parent: Node, caption: String) -> Array:
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	parent.add_child(col)
	var top := HBoxContainer.new()
	col.add_child(top)
	var t := Label.new()
	t.text = caption
	t.add_theme_color_override("font_color", UiTheme.TEXT_DIM)
	t.add_theme_font_size_override("font_size", 15)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(t)
	var w := Label.new()
	w.add_theme_font_size_override("font_size", 15)
	top.add_child(w)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	return [w, grid]


func _refresh() -> void:
	if not visible or _player == null or _container == null:
		return
	_fill(_left_grid, _player.inventory, true)
	_fill(_right_grid, _container, false)
	var inv := _player.inventory
	_left_weight.text = "%.1f / %.0f kg" % [inv.total_weight(), inv.capacity()]
	_right_weight.text = "%.1f / %.0f kg" % [_container.total_weight(), _container.capacity()]


func _fill(grid: GridContainer, inv: Inventory, from_player: bool) -> void:
	for c in grid.get_children():
		c.queue_free()
	for i in inv.stacks.size():
		var s := inv.stacks[i]
		var d := s.data()
		var b := Button.new()
		b.custom_minimum_size = SLOT_SIZE
		b.expand_icon = true
		b.icon = d.icon if d else null
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.add_theme_constant_override("icon_max_width", 52)
		b.add_theme_font_size_override("font_size", 13)
		b.clip_text = true
		b.text = ("%s x%d" % [d.display_name, s.quantity]) if s.quantity > 1 else d.display_name
		b.tooltip_text = d.display_name
		b.pressed.connect(_move.bind(i, from_player))
		grid.add_child(b)


## Move a pilha (ou uma unidade) para o outro lado, até onde couber.
func move(index: int, from_player: bool, one := false) -> int:
	var src: Inventory = _player.inventory if from_player else _container
	var dst: Inventory = _container if from_player else _player.inventory
	if index < 0 or index >= src.stacks.size():
		return 0
	var s := src.stacks[index]
	var want := 1 if one else s.quantity
	var fits := mini(want, dst.room_for(s.item_id))
	if fits <= 0:
		Events.notify.emit("Não cabe: %s" % (s.data().display_name if s.data() else ""))
		return 0
	var taken := src.take_from(index, fits)
	if taken == null:
		return 0
	var added := dst.add_item(taken.item_id, taken.quantity, taken.durability)
	if added < taken.quantity:  # devolve o que sobrou
		src.add_item(taken.item_id, taken.quantity - added, taken.durability)
	Sfx.play_2d(&"bag", -8.0)
	_refresh()
	return added


func _move(index: int, from_player: bool) -> void:
	move(index, from_player, _one_toggle.button_pressed)
