## warehouse_service.gd —— FullHaul 领域服务：Warehouse（仓库）域
##
## 职责：
##   实现 IWarehouseService 契约（架构 §1.1 Warehouse 域、§5 PlayerProfile
##   实体、规范 AC-14、INV-12，切片 8）：
##   - 带回物品入库（撤离成功后，INV-10/11 与 Settlement 协作）
##   - 物品出售：经 Transaction 域保证扣款/入账原子性与防重（INV-12）
##
## 设计要点：
##   1. 纯逻辑：不依赖任何 Godot 节点，可独立单元测试（架构原则 2）。
##   2. 出售走 Transaction 域（ITransactionService.apply_transaction，type="sell"，
##      ref=instance_id）：同一物品只允许售出一次（INV-12 防重）；余额不足/重复
##      交易失败时不产生任何变动。
##   3. 物品价值经注入的 value_resolver（Callable(instance_id) -> int）解析
##      （单一来源 INV-16）；未注入解析器或价值非正时拒绝出售。
##   4. 仓库不承载局内运行态，只维护局外账本（PlayerProfile.warehouse_item_ids，
##      审核 P1-3）。
##   5. 领域事件（WAREHOUSE_ITEM_ADDED/ITEM_SOLD/CURRENCY_CHANGED）由应用层
##      或后续表现层在结果流转处发布，本服务聚焦账本操作（与 Extract/Item
##      域服务一致的「不重复发布」约定）。

extends IWarehouseService
class_name WarehouseService
## 本类继承领域接口 IWarehouseService（本文件为切片 8 的落地实现）。

## 注入的事务服务（出售加款原子化与防重，INV-12）
var _tx: ITransactionService = null
## 物品价值解析器：Callable(instance_id: String) -> int（单一来源 INV-16）
var _value_resolver: Callable = Callable()


func _init(tx: ITransactionService = null, value_resolver: Callable = Callable()) -> void:
	_tx = tx
	_value_resolver = value_resolver


## 将一件物品入库到仓库（撤离成功后，INV-10/11；重复入库幂等）。
func add_to_warehouse(profile: PlayerProfile, instance_id: String) -> void:
	if profile == null or instance_id == "":
		return
	if not profile.warehouse_item_ids.has(instance_id):
		profile.warehouse_item_ids.append(instance_id)


## 出售一件仓库物品（INV-12 原子事务）；返回成交价格。
## 物品不在仓库 / 价值非正 / 重复出售（Transaction 防重）/ 事务失败时返回 0，
## 且不产生任何余额与仓库变动。
func sell_item(profile: PlayerProfile, instance_id: String) -> int:
	if profile == null or instance_id == "":
		return 0
	if not profile.warehouse_item_ids.has(instance_id):
		return 0
	var value := _resolve_value(instance_id)
	if value <= 0:
		return 0
	if _tx != null:
		if not _tx.apply_transaction(profile, "sell", value, instance_id):
			return 0
	else:
		profile.change_currency(value)
	profile.warehouse_item_ids.erase(instance_id)
	return value


## 解析物品价值（经注入的 value_resolver；未注入或非法时返回 0）。
func _resolve_value(instance_id: String) -> int:
	if _value_resolver.is_valid():
		return int(_value_resolver.call(instance_id))
	return 0
