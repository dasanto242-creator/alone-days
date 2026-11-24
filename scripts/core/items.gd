extends Node
## Catálogo global de itens (autoload "Items").

const CATALOG_PATH := "res://data/item_catalog.tres"

var _by_id := {}


func _ready() -> void:
	if not ResourceLoader.exists(CATALOG_PATH):
		return  # ainda não gerado (primeira execução das ferramentas)
	var catalog := load(CATALOG_PATH) as ItemCatalog
	if catalog == null:
		push_error("Catálogo de itens não encontrado: " + CATALOG_PATH)
		return
	for item in catalog.items:
		_by_id[item.id] = item


func get_item(id: StringName) -> ItemData:
	return _by_id.get(id)


func all_ids() -> Array:
	return _by_id.keys()
