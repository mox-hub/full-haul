## memory_run_snapshot_repository.gd —— IRunSnapshotRepository 的内存实现（基础设施层）
##
## WORD-31 阶段2：与 SqliteRunSnapshotRepository 并存的内存后端。局内状态
## 快照（运行时数据，可选）落在共享 InMemoryDataStore（对齐 run_snapshot）。

extends RefCounted
class_name MemoryRunSnapshotRepository


var _store: InMemoryDataStore = null


func _init(store: InMemoryDataStore) -> void:
	_store = store


func upsert_run_snapshot(state: RunState) -> bool:
	if state == null or state.run_id == "":
		return false
	_store.run_snapshots[state.run_id] = state
	return true


func load_run_snapshot(run_id: String) -> RunState:
	return _store.run_snapshots.get(run_id, null)