## i_warehouse_service.gd —— FullHaul 领域接口：Warehouse（仓库）域
##
## 职责：
##   定义仓库域对应用编排层暴露的最小契约（架构 §1.1 Warehouse 域）。
##   领域层只依赖本接口。
##
## 覆盖范围（规范 AC-12~15、INV-12，切片 8）：
##   - 带回物品入库（撤离成功后）
##   - 物品出售（原子事务，INV-12）
##
## 说明：本文件为 V0.1 基础框架的「接口骨架」，仅声明契约不实现；
## 具体实现由后续切片（架构 §7 切片 8）落地。

extends RefCounted
class_name IWarehouseService

## 将一件物品入库到仓库（撤离成功后）。
func add_to_warehouse(profile: PlayerProfile, instance_id: String) -> void:
	pass


## 出售一件仓库物品（INV-12 原子事务）；返回成交价格。
func sell_item(profile: PlayerProfile, instance_id: String) -> int:
	return 0
