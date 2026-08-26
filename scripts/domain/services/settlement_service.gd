## settlement_service.gd —— FullHaul 领域服务：Settlement（结算）域
##
## 职责：
##   实现 ISettlementService 契约（架构 §1.1 Settlement 域、§2.1
##   RUN_SUCCEEDED/RUN_FAILED -> SETTLED、§5 RunState 实体、规范 AC-12/13、
##   INV-09/10/11，切片 8）：
##   - 成功结算：撤离成功携带物品入库（INV-10，carried_item_ids）
##   - 失败结算：撤离失败安全箱物品入库（INV-11，safe_item_ids）
##   - 单次结算幂等（INV-09）：结算标记置位后重复结算被忽略
##
## 设计要点：
##   1. 纯逻辑：不依赖任何 Godot 节点，可独立单元测试（架构原则 2）。
##   2. 结算的「结果流转至局外」经 Warehouse 域落库（架构 §1.1 Settlement
##      依赖 Warehouse）；货币变动（出售）由 Transaction 域单独处理，结算本身
##      不直接改动货币。
##   3. 领域事件（RUN_SUCCEEDED/RUN_FAILED/RUN_SETTLED）由顶层状态机在转移时
##      发布，本服务只负责结算域的状态流转与物品去向，不重复发布事件。
##   4. 本服务不持有局内运行态，一局一实例经 IRunStateStore 承载（审核 P1-3）。

extends ISettlementService
class_name SettlementService
## 本类继承领域接口 ISettlementService（本文件为切片 8 的落地实现）。

## 注入的仓库服务（撤离后物品入库落库，INV-10/11；可选）
var _warehouse: IWarehouseService = null


func _init(warehouse: IWarehouseService = null) -> void:
	_warehouse = warehouse


## 执行一次成功结算（INV-10）：撤离成功携带物品入仓库。
## 返回是否真正结算（false 表示重复结算被幂等忽略，INV-09）。
func settle_success(state: RunState, profile: PlayerProfile) -> bool:
	if state == null:
		return false
	if state.settled:
		return false
	if _warehouse != null:
		for instance_id in state.carried_item_ids:
			_warehouse.add_to_warehouse(profile, str(instance_id))
	return true


## 执行一次失败结算（INV-11）：撤离失败安全箱物品入仓库。
## 返回是否真正结算（false 表示重复结算被幂等忽略，INV-09）。
func settle_failure(state: RunState, profile: PlayerProfile) -> bool:
	if state == null:
		return false
	if state.settled:
		return false
	if _warehouse != null:
		for instance_id in state.safe_item_ids:
			_warehouse.add_to_warehouse(profile, str(instance_id))
	return true


## 结算是否已完成（INV-09）。
func is_settled(state: RunState) -> bool:
	return state != null and state.settled
