class_name Inventory
extends RefCounted
## Inventário do sobrevivente: itens carregados + equipamentos vestidos.
## Limite por PESO: a capacidade vem dos bolsos (base) + mochila e roupas equipadas.
## Classe pura (sem nós), então pode ser salva e, no futuro, sincronizada em rede.

signal changed

var base_capacity := 6.0
var stacks: Array[ItemStack] = []
## ItemData.Slot -> ItemStack
var equipment := {}


func total_weight() -> float:
	var total := 0.0
	for s in stacks:
		total += s.weight()
	for s in equipment.values():
		total += (s as ItemStack).weight()
	return total


func capacity() -> float:
	var cap := base_capacity
	for s in equipment.values():
		var d := (s as ItemStack).data()
		if d:
			cap += d.capacity_bonus
	return cap


func free_weight() -> float:
	return maxf(capacity() - total_weight(), 0.0)


## Quantas unidades deste item ainda cabem (por peso).
func room_for(item_id: StringName) -> int:
	var d := Items.get_item(item_id)
	if d == null:
		return 0
	if d.weight <= 0.0:
		return 9999
	return floori((free_weight() + 0.0001) / d.weight)


## Adiciona até `quantity` unidades. Retorna quantas foram adicionadas.
func add_item(item_id: StringName, quantity := 1, durability := 100.0) -> int:
	var d := Items.get_item(item_id)
	if d == null or quantity <= 0:
		return 0
	var to_add := mini(quantity, room_for(item_id))
	var remaining := to_add
	# Primeiro completa pilhas existentes
	if d.max_stack > 1:
		for s in stacks:
			if remaining <= 0:
				break
			if s.item_id == item_id and s.quantity < d.max_stack:
				var n := mini(d.max_stack - s.quantity, remaining)
				s.quantity += n
				remaining -= n
	while remaining > 0:
		var n := mini(d.max_stack, remaining)
		stacks.append(ItemStack.new(item_id, n, durability))
		remaining -= n
	if to_add > 0:
		changed.emit()
	return to_add


## Remove `quantity` unidades da pilha `index`. Retorna a pilha removida (para soltar no chão).
func take_from(index: int, quantity := 1) -> ItemStack:
	if index < 0 or index >= stacks.size():
		return null
	var s := stacks[index]
	var n := mini(quantity, s.quantity)
	s.quantity -= n
	if s.quantity <= 0:
		stacks.remove_at(index)
	changed.emit()
	return ItemStack.new(s.item_id, n, s.durability)


func count_of(item_id: StringName) -> int:
	var total := 0
	for s in stacks:
		if s.item_id == item_id:
			total += s.quantity
	return total


## Veste o item da pilha `index`. O que estava no mesmo lugar volta para o inventário.
func equip(index: int) -> bool:
	if index < 0 or index >= stacks.size():
		return false
	var s := stacks[index]
	var d := s.data()
	if d == null or not d.is_equipment():
		return false
	stacks.remove_at(index)
	if equipment.has(d.equip_slot):
		stacks.append(equipment[d.equip_slot])
	equipment[d.equip_slot] = ItemStack.new(s.item_id, 1, s.durability)
	if s.quantity > 1:
		stacks.insert(index, ItemStack.new(s.item_id, s.quantity - 1, s.durability))
	changed.emit()
	return true


## Tira o equipamento. Só permite se, sem ele, o peso continuar dentro da capacidade.
func can_unequip(slot: int) -> bool:
	if not equipment.has(slot):
		return false
	var d := (equipment[slot] as ItemStack).data()
	return total_weight() <= capacity() - (d.capacity_bonus if d else 0.0) + 0.0001


func unequip(slot: int) -> bool:
	if not can_unequip(slot):
		return false
	stacks.append(equipment[slot])
	equipment.erase(slot)
	changed.emit()
	return true


## Remove o equipamento (para soltar no chão), sem checar capacidade.
func take_equipment(slot: int) -> ItemStack:
	if not equipment.has(slot):
		return null
	var s: ItemStack = equipment[slot]
	equipment.erase(slot)
	changed.emit()
	return s


func equipped(slot: int) -> ItemStack:
	return equipment.get(slot)


func to_dict() -> Dictionary:
	var eq := {}
	for slot in equipment:
		eq[str(slot)] = (equipment[slot] as ItemStack).to_dict()
	return {"stacks": stacks.map(func(s: ItemStack) -> Dictionary: return s.to_dict()), "equipment": eq}


func load_dict(d: Dictionary) -> void:
	stacks.clear()
	equipment.clear()
	for sd in d.get("stacks", []):
		stacks.append(ItemStack.from_dict(sd))
	var eq: Dictionary = d.get("equipment", {})
	for key in eq:
		equipment[int(key)] = ItemStack.from_dict(eq[key])
	changed.emit()
