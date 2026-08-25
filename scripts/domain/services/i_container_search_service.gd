## i_container_search_service.gd —— FullHaul 领域接口：Loot / Container（容器与搜集）域
##
## 职责：
##   定义容器搜索域对应用编排层暴露的最小契约（架构 §1.1 Loot / Container 域、
##   §2.2 容器搜索子状态机）。领域层只依赖本接口。
##
## 覆盖范围（规范 AC-04/05/06/17/18/19/20、INV-05/06，切片 6）：
##   - 容器搜索子状态机（UNOPENED/MASKED/REVEALING/PARTIALLY_REVEALED/COMPLETED）
##   - 未知遮罩、逐件揭晓、完成计数幂等（INV-06）
##
## 说明：本文件为 V0.1 基础框架的「接口骨架」，声明容器搜索域的契约；
## 本 run 已提供对应的子状态机骨架 `ContainerSearchStateMachine`。

extends RefCounted
class_name IContainerSearchService

## 打开一个容器进入搜索（INV-05），item_count 为容器内物品总数。
func open_container(container_id: String, item_count: int) -> void:
	pass


## 开始揭晓容器内下一件物品（品质决定耗时）。
func start_reveal(container_id: String, instance_id: String, rarity: String) -> bool:
	return false


## 一件物品揭晓完成。
func complete_reveal(container_id: String, instance_id: String, definition_id: String,
		rarity: String, value: int, size: Vector2i) -> void:
	pass


## 该容器是否已完成搜索（INV-06）。
func is_container_completed(container_id: String) -> bool:
	return false


## 当前已完成搜索的容器数（供撤离解锁判定，INV-07）。
func completed_container_count() -> int:
	return 0
