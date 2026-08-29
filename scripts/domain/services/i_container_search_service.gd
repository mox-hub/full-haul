## i_container_search_service.gd —— FullHaul 领域接口：Loot / Container（容器与搜集）域
##
## 职责：
##   定义容器搜索域对应用编排层暴露的最小契约（架构 §1.1 Loot / Container 域、
##   §2.2 容器搜索子状态机）。领域层只依赖本接口。
##
## 覆盖范围（规范 AC-04/05/06/17/18/19/20、INV-05/06，切片 6）：
##   - 容器搜索子状态机（UNOPENED/MASKED/REVEALING/PARTIALLY_REVEALED/COMPLETED）
##   - 未知遮罩（INV-05）、逐件揭晓、完成计数幂等（INV-06）
##   - 容器登记（一局一个容器一个实例）与完成数统计（INV-07 依赖）
##
## 说明：切片 6 由 ContainerSearchService 落地实现本契约（架构 §7 切片 6）。

extends RefCounted
class_name IContainerSearchService

## 登记一个容器（UNOPENED 初始；一局内一个容器一个实例）。
## type_id 为容器类型 id（可选）；重复登记同一 container_id 返回 false。
func register_container(container_id: String, type_id: String = "") -> bool:
	return false


## 打开一个容器进入搜索（INV-05），item_count 为容器内物品总数；
## item_instance_ids 为容器内物品实例 id 列表（可选，提供时以实例数为准，
## 保证遮罩计数与最终揭晓一致）；item_sizes 为各物品占格尺寸（可选，
## 逐件 Vector2i，蒙版按真实形状呈现）。未登记容器时自动登记。
## 返回是否打开成功（已打开过返回 false）。
func open_container(container_id: String, item_count: int, item_instance_ids: Array = [],
		item_sizes: Array = []) -> bool:
	return false


## 开始揭晓容器内下一件物品（品质决定耗时）。
func start_reveal(container_id: String, instance_id: String, rarity: String) -> bool:
	return false


## 一件物品揭晓完成。返回是否「本次揭晓使该容器首次完成并计数」
## （INV-06 幂等信号；false 表示未完成/重复揭晓/已计数）。
func complete_reveal(container_id: String, instance_id: String, definition_id: String,
		rarity: String, value: int, size: Vector2i) -> bool:
	return false


## 该容器是否已完成搜索（INV-06）。
func is_container_completed(container_id: String) -> bool:
	return false


## 当前已完成搜索的容器数（幂等 INV-06；供撤离解锁判定，INV-07）。
func completed_container_count() -> int:
	return 0


## 查询容器子状态机；不存在返回 null。
func container(container_id: String) -> ContainerSearchStateMachine:
	return null


## 清空本局容器登记（新一局开始调用；INV-14 多局隔离）。
func reset() -> void:
	pass
