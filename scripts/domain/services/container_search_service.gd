## container_search_service.gd —— FullHaul 领域服务：Loot / Container（容器与搜集）域
##
## 职责：
##   实现 IContainerSearchService 契约（架构 §1.1 Loot / Container 域、
##   §2.2 容器搜索子状态机、§5 ContainerState 实体、规范 AC-04/05/06/17/18、
##   INV-05/06，切片 6）：
##   - 容器登记：一局内按 container_id 登记独立容器（每容器一个
##     ContainerSearchStateMachine 实例，UNOPENED 初始）
##   - 打开容器进入 MASKED（INV-05 遮罩计数）与逐件揭晓（品质决定耗时）
##   - 完成计数幂等（INV-06）：completed_container_count 只统计已 counted 的
##     容器；同一容器重复完成不重复计数
##
## 设计要点：
##   1. 纯逻辑：不依赖任何 Godot 节点，可独立单元测试（架构原则 2）。
##   2. 领域事件（CONTAINER_OPENED/ITEM_REVEAL_STARTED/ITEM_REVEALED/
##      CONTAINER_COMPLETED）由底层状态机经注入的 IEventBus 发布，供表现层/
##      遥测订阅（架构 §2.3）。
##   3. 一局一实例：容器登记为本局运行态，新一局开始调用 reset() 清空
##      （INV-14 多局隔离）；禁止全局静态单例承载运行态（审核 P1-3）。
##   4. complete_reveal 返回「首次完成信号」，供应用编排层触发局级完成数
##      更新与撤离解锁阈值判定（INV-07）。

extends IContainerSearchService
class_name ContainerSearchService
## 本类继承领域接口 IContainerSearchService（本文件为切片 6 的落地实现）。

## 注入的事件总线（容器搜索领域事件发布）
var _bus: IEventBus = null
## 注入的配置加载器（品质揭晓耗时单一来源 INV-16）
var _config_loader: IConfigLoader = null
## container_id -> ContainerSearchStateMachine（本局容器登记表）
var _containers: Dictionary = {}


func _init(bus: IEventBus = null, config_loader: IConfigLoader = null) -> void:
	_bus = bus
	_config_loader = config_loader


## 登记一个容器（UNOPENED 初始）。重复登记同一 container_id 返回 false。
func register_container(container_id: String, type_id: String = "") -> bool:
	if _containers.has(container_id):
		return false
	var csm := ContainerSearchStateMachine.new(container_id, _bus, _config_loader)
	csm.type_id = type_id
	_containers[container_id] = csm
	return true


## 打开一个容器进入搜索（INV-05）。未登记容器时自动登记。
func open_container(container_id: String, item_count: int, item_instance_ids: Array = []) -> bool:
	var csm := _ensure_container(container_id)
	if csm == null:
		return false
	return csm.open(item_count, item_instance_ids)


## 开始揭晓容器内下一件物品（品质决定耗时）。
func start_reveal(container_id: String, instance_id: String, rarity: String) -> bool:
	var csm: ContainerSearchStateMachine = _containers.get(container_id, null)
	if csm == null:
		return false
	return csm.start_reveal(instance_id, rarity)


## 一件物品揭晓完成。返回是否「本次揭晓使该容器首次完成并计数」
## （INV-06 幂等信号；false 表示未完成/重复揭晓/已计数）。
func complete_reveal(container_id: String, instance_id: String, definition_id: String,
		rarity: String, value: int, size: Vector2i) -> bool:
	var csm: ContainerSearchStateMachine = _containers.get(container_id, null)
	if csm == null:
		return false
	return csm.complete_reveal(instance_id, definition_id, rarity, value, size)


## 该容器是否已完成搜索（INV-06）。
func is_container_completed(container_id: String) -> bool:
	var csm: ContainerSearchStateMachine = _containers.get(container_id, null)
	return csm != null and csm.is_completed()


## 当前已完成搜索的容器数（幂等 INV-06）：只统计已 counted 的容器，
## 同一容器只计一次，供撤离解锁判定（INV-07）。
func completed_container_count() -> int:
	var count := 0
	for csm in _containers.values():
		if csm.was_counted():
			count += 1
	return count


## 查询容器子状态机；不存在返回 null。
func container(container_id: String) -> ContainerSearchStateMachine:
	return _containers.get(container_id, null)


## 清空本局容器登记（新一局开始调用；INV-14 多局隔离）。
func reset() -> void:
	_containers.clear()


## 取容器状态机；未登记时自动登记（open 前的懒登记）。
func _ensure_container(container_id: String) -> ContainerSearchStateMachine:
	var csm: ContainerSearchStateMachine = _containers.get(container_id, null)
	if csm != null:
		return csm
	register_container(container_id)
	return _containers.get(container_id, null)
