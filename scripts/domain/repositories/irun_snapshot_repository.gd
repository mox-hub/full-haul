## irun_snapshot_repository.gd —— FullHaul 局内状态快照仓储接口（领域层契约）
##
## 运行时数据（可选）：一局内状态快照，用于调试/回放，非强制。
## 领域层经本接口读写快照，不暴露数据库实现细节。

extends RefCounted
class_name IRunSnapshotRepository


## 保存（插入或更新）一局状态快照。
func upsert_run_snapshot(
	state: RunState
) -> bool:
	return false


## 按 run_id 读取快照；不存在返回 null。
func load_run_snapshot(run_id: String) -> RunState:
	return null
