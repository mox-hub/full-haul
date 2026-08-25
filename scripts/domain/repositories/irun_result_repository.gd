## irun_result_repository.gd —— FullHaul 局外结算/事务数据仓储接口（领域层契约）
##
## 承载结算记录与经济事务流水的持久化（存档数据，V0.1 持久化范围为同一应用
## 运行周期内，TBD-12）。领域层经本接口读写，不暴露数据库实现细节。

extends RefCounted
class_name IRunResultRepository


## 追加一条结算记录（返回是否成功）。
## run_id 唯一（INV-09 结算幂等）；重复 run_id 应被拒绝并返回 false。
func insert_settlement(
	record: Dictionary  # {record_id, run_id, profile_id, result, currency_before, currency_after, carried_item_ids, safe_item_ids}
) -> bool:
	return false


## 按 run_id 查询结算记录；不存在返回空 Dictionary。
func find_settlement_by_run(run_id: String) -> Dictionary:
	return {}


## 追加一条经济事务流水（INV-12 防重；同 profile_id+type+ref_id 重复应被拒绝）。
func insert_transaction(
	entry: Dictionary  # {transaction_id, profile_id, type, amount, ref_id, balance_before, balance_after}
) -> bool:
	return false


## 是否已存在同 profile+type+ref 的事务（防重查询）。
func has_transaction(profile_id: String, type: String, ref_id: String) -> bool:
	return false
