## memory_profile_repository.gd —— IProfileRepository 的内存实现（基础设施层）
##
## WORD-31 阶段2：与 SqliteProfileRepository 并存的内存后端。把 PlayerProfile
## 持久化到共享 InMemoryDataStore（对齐 player_profile + warehouse_item 语义），
## 供 RepositoryProvider 按配置切换选用。

extends RefCounted
class_name MemoryProfileRepository


const DEFAULT_PROFILE_ID := "local"

var _store: InMemoryDataStore = null


func _init(store: InMemoryDataStore) -> void:
	_store = store


func load() -> PlayerProfile:
	var profile := _store.ensure_profile()
	var out := PlayerProfile.new()
	out.currency = profile.currency
	out.selected_backpack_offer_id = profile.selected_backpack_offer_id
	out.warehouse_item_ids = profile.warehouse_item_ids.duplicate()
	return out


func save(profile: PlayerProfile) -> void:
	var stored := _store.ensure_profile()
	stored.currency = profile.currency
	stored.selected_backpack_offer_id = profile.selected_backpack_offer_id
	stored.warehouse_item_ids = profile.warehouse_item_ids.duplicate()