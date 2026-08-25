## memory_run_result_repository.gd —— IRunResultRepository 的内存实现（基础设施层）
##
## WORD-31 阶段2：与 SqliteRunResultRepository 并存的内存后端。结算记录与
## 经济事务流水落在共享 InMemoryDataStore（对齐 settlement_record /
## economy_transaction），结算幂等（INV-09）与事务防重（INV-12）语义保持。

extends RefCounted
class_name MemoryRunResultRepository


var _store: InMemoryDataStore = null


func _init(store: InMemoryDataStore) -> void:
	_store = store


func insert_settlement(record: Dictionary) -> bool:
	var run_id := str(record.get("run_id", ""))
	if run_id == "":
		return false
	if _store.settlements.has(run_id):
		return false
	_store.settlements[run_id] = record.duplicate(true)
	return true


func find_settlement_by_run(run_id: String) -> Dictionary:
	return _store.settlements.get(run_id, {})


func insert_transaction(entry: Dictionary) -> bool:
	var profile_id := str(entry.get("profile_id", ""))
	var type := str(entry.get("type", ""))
	var ref_id := str(entry.get("ref_id", ""))
	if profile_id == "" or type == "" or ref_id == "":
		return false
	if has_transaction(profile_id, type, ref_id):
		return false
	_store.transactions.append(entry.duplicate(true))
	return true


func has_transaction(profile_id: String, type: String, ref_id: String) -> bool:
	for entry in _store.transactions:
		if str(entry.get("profile_id", "")) == profile_id \
				and str(entry.get("type", "")) == type \
				and str(entry.get("ref_id", "")) == ref_id:
			return true
	return false