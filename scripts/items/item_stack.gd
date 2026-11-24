class_name ItemStack
extends RefCounted
## Uma pilha de itens dentro do inventário (ex.: 3 garrafas de água).
## Guarda só o id e o estado, para ser fácil de salvar e de enviar pela rede no futuro.

var item_id: StringName
var quantity := 1
## Estado de 0 a 100 (%). Só tem efeito em itens com max_durability > 0.
var durability := 100.0


func _init(id: StringName = &"", qty := 1, condition := 100.0) -> void:
	item_id = id
	quantity = qty
	durability = condition


func data() -> ItemData:
	return Items.get_item(item_id)


func weight() -> float:
	var d := data()
	return d.weight * quantity if d else 0.0


func to_dict() -> Dictionary:
	return {"id": String(item_id), "qty": quantity, "dur": durability}


static func from_dict(d: Dictionary) -> ItemStack:
	return ItemStack.new(StringName(d.get("id", "")), int(d.get("qty", 1)), float(d.get("dur", 100.0)))
