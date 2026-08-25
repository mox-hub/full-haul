## sqlite_run_result_repository.gd —— IRunResultRepository 的 SQLite 实现（基础设施层）
##
## 结算记录与经济事务流水落库。利用唯一约束实现结算幂等（INV-09）与事务防重
## （INV-12）：冲突时写入失败并返回 false。

extends RefCounted
class_name SqliteRunResultRepository



var _conn: DatabaseConnector


func _init(conn: DatabaseConnector) -> void:
	_conn = conn
	_conn.open()


func insert_settlement(record: Dictionary) -> bool:
	_conn.execute(
		"""
		INSERT INTO settlement_record
			(record_id, run_id, profile_id, result, currency_before, currency_after, carried_item_ids, safe_item_ids)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		""",
		[
			str(record.get("record_id", "")),
			str(record.get("run_id", "")),
			str(record.get("profile_id", "")),
			str(record.get("result", "success")),
			int(record.get("currency_before", 0)),
			int(record.get("currency_after", 0)),
			JSON.stringify(record.get("carried_item_ids", [])),
			JSON.stringify(record.get("safe_item_ids", [])),
		]
	)
	return _conn.changes() > 0


func find_settlement_by_run(run_id: String) -> Dictionary:
	var rows := _conn.query(
		"SELECT * FROM settlement_record WHERE run_id = ?",
		[run_id]
	)
	if rows.is_empty():
		return {}
	return rows[0]


func insert_transaction(entry: Dictionary) -> bool:
	_conn.execute(
		"""
		INSERT INTO economy_transaction
			(transaction_id, profile_id, type, amount, ref_id, balance_before, balance_after, status)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?)
		""",
		[
			str(entry.get("transaction_id", "")),
			str(entry.get("profile_id", "")),
			str(entry.get("type", "")),
			int(entry.get("amount", 0)),
			str(entry.get("ref_id", "")),
			int(entry.get("balance_before", 0)),
			int(entry.get("balance_after", 0)),
			str(entry.get("status", "ok")),
		]
	)
	return _conn.changes() > 0


func has_transaction(profile_id: String, type: String, ref_id: String) -> bool:
	var rows := _conn.query(
		"SELECT transaction_id FROM economy_transaction WHERE profile_id = ? AND type = ? AND ref_id = ?",
		[profile_id, type, ref_id]
	)
	return not rows.is_empty()
