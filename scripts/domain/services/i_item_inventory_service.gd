## i_item_inventory_service.gd —— FullHaul 领域接口：Item & Inventory（物品与背包）域
##
## 职责：
##   定义物品与格子背包域对应用编排层暴露的最小契约（架构 §1.1
##   Item & Inventory 域）。领域层只依赖本接口。
##
## 覆盖范围（规范 AC-07/AC-08、INV-01~05，切片 5）：
##   - 物品定义/实例（Definition 与 Instance 分离）
##   - 背包/安全箱两个独立格子（INV-04 语义分离）
##   - 放置校验、移动、旋转、丢弃（原子格子操作，INV-01~05）
##
## 说明：本文件为 V0.1 基础框架的「接口骨架」，仅声明契约不实现；
## 具体实现由后续切片（架构 §7 切片 5）落地。

extends RefCounted
class_name IItemInventoryService

## 放置一件物品到指定格子的目标位置。
## 返回是否放置成功（越界/重叠/尺寸不合法则失败，INV-01/02/03）。
func place_item(instance_id: String, to: Vector2i) -> bool:
	return false


## 移动一件物品（含旋转后的尺寸与目标位置校验）。
func move_item(instance_id: String, from: Vector2i, to: Vector2i) -> bool:
	return false


## 旋转一件物品（更新朝向）。
func rotate_item(instance_id: String) -> bool:
	return false


## 丢弃一件物品（INV-01 唯一归属）。
func drop_item(instance_id: String) -> bool:
	return false


## 校验物品能否放置到指定格子（不执行放置）。
func can_place(instance_id: String, to: Vector2i) -> bool:
	return false
