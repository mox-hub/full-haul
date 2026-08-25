## memory_config_data_repository.gd —— IConfigDataRepository 的内存实现（基础设施层）
##
## WORD-31 阶段2：与 SqliteConfigDataRepository 并存的「内存后端」实现，
## 经 RepositoryProvider 按配置切换。测试/演示用默认后端（无需 sqlite
## GDExtension）；数据源为共享 InMemoryDataStore，与 SQLite 表语义对齐。

extends RefCounted
class_name MemoryConfigDataRepository


var _store: InMemoryDataStore = null


func _init(store: InMemoryDataStore) -> void:
	_store = store


func load_item_definitions() -> Dictionary:
	return _store.item_definitions


func get_item_definition(definition_id: String) -> Dictionary:
	return _store.item_definitions.get(definition_id, {})


func load_container_types() -> Dictionary:
	return _store.container_types


func load_backpack_offers() -> Dictionary:
	return _store.backpack_offers


func load_container_tier_weights() -> Dictionary:
	return _store.container_tier_weights