## sqlite_run_snapshot_repository.gd —— IRunSnapshotRepository 的 SQLite 实现（基础设施层）
##
## 局内状态快照（运行时数据，可选）落库到 run_snapshot 表，用于调试/回放。

extends RefCounted
class_name SqliteRunSnapshotRepository



var _conn: DatabaseConnector


func _init(conn: DatabaseConnector) -> void:
	_conn = conn
	_conn.open()


func upsert_run_snapshot(state: RunState) -> bool:
	_conn.execute(
		"""
		INSERT INTO run_snapshot
			(run_id, phase, remaining_match_time, remaining_extraction_time, completed_container_count, settled, carried_item_ids, safe_item_ids)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		ON CONFLICT(run_id) DO UPDATE SET
			phase = excluded.phase,
			remaining_match_time = excluded.remaining_match_time,
			remaining_extraction_time = excluded.remaining_extraction_time,
			completed_container_count = excluded.completed_container_count,
			settled = excluded.settled,
			carried_item_ids = excluded.carried_item_ids,
			safe_item_ids = excluded.safe_item_ids,
			updated_at = datetime('now')
		""",
		[
			state.run_id,
			RunStateCodec.phase_to_string(state.phase),
			state.remaining_match_time,
			state.remaining_extraction_time,
			state.completed_container_count,
			1 if state.settled else 0,
			JSON.stringify(state.carried_item_ids),
			JSON.stringify(state.safe_item_ids),
		]
	)
	return _conn.changes() > 0


func load_run_snapshot(run_id: String) -> RunState:
	var rows := _conn.query("SELECT * FROM run_snapshot WHERE run_id = ?", [run_id])
	if rows.is_empty():
		return null
	var row: Dictionary = rows[0]
	var state := RunState.new(run_id, 0, 0)
	state.phase = RunStateCodec.phase_from_string(str(row.get("phase", "RUN_INIT")))
	state.remaining_match_time = int(row.get("remaining_match_time", 0))
	state.remaining_extraction_time = int(row.get("remaining_extraction_time", 0))
	state.completed_container_count = int(row.get("completed_container_count", 0))
	state.settled = int(row.get("settled", 0)) == 1
	state.carried_item_ids = JSON.parse_string(str(row.get("carried_item_ids", "[]")))
	state.safe_item_ids = JSON.parse_string(str(row.get("safe_item_ids", "[]")))
	return state
