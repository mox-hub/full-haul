## i_item_inventory_service.gd —— FullHaul 领域接口：Item & Inventory（物品与背包）域
##
## 职责：
##   定义物品与格子背包域对应用编排层暴露的最小契约（架构 §1.1
##   Item & Inventory 域）。领域层只依赖本接口。
##
## 覆盖范围（规范 AC-07/AC-08、INV-01~05，切片 5）：
##   - 物品定义/实例（Definition 与 Instance 分离，数据驱动配置单一来源 INV-16）
##   - 背包/安全箱两个独立格子（INV-04 语义分离）
##   - 放置校验（占位/边界/合法性）、移动、旋转、丢弃（原子格子操作，INV-01~05）
##
## 说明：切片 5 由 ItemInventoryService 落地实现本契约（架构 §7 切片 5）。

extends RefCounted
class_name IItemInventoryService

## 创建物品实例（definition_id 必须存在于数据驱动配置中，INV-16）。
## 返回创建的实例；定义不存在或 instance_id 已被占用时返回 null（INV-01）。
func create_item(instance_id: String, definition_id: String) -> ItemInstance:
	return null


## 查询物品实例；不存在返回 null。
func get_item(instance_id: String) -> ItemInstance:
	return null


## 查询物品定义；不存在返回 null。
func get_definition(definition_id: String) -> ItemDefinition:
	return null


## 查询指定归属类型的格子；未初始化返回 null。
func get_grid(owner: GridInventory.OwnerType) -> GridInventory:
	return null


## 建立本局背包格子（尺寸来自 Loadout 选定档位；AC-03 前置绑定）。
func setup_backpack(grid_width: int, grid_height: int) -> bool:
	return false


## 建立安全箱格子（尺寸来自配置 SafeContainerConfig，INV-16）。
func setup_safe(grid_width: int, grid_height: int) -> bool:
	return false


## 放置校验：物品能否放入指定格子的目标位置（不执行放置；越界/重叠/尺寸
## 不合法返回 false，INV-04）。
func can_place(instance_id: String, owner: GridInventory.OwnerType, to: Vector2i) -> bool:
	return false


## 放置物品到指定格子的目标位置（INV-01 唯一归属；失败保持操作前状态）。
func place_item(instance_id: String, owner: GridInventory.OwnerType, to: Vector2i) -> bool:
	return false


## 移动物品到目标格子的目标位置（可跨格子，AC-08 背包↔安全箱往返）。
## 失败时保持操作前状态（INV-04）。
func move_item(instance_id: String, to_owner: GridInventory.OwnerType, to: Vector2i) -> bool:
	return false


## 旋转物品（更新朝向；旋转后占格一致 INV-05）。非法旋转（越界/重叠）时
## 保持原朝向（AC-07 非法旋转）。
func rotate_item(instance_id: String) -> bool:
	return false


## 丢弃物品（INV-01/03：移出格子并明确标记为已丢弃）。
func drop_item(instance_id: String) -> bool:
	return false