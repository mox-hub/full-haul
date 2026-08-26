## container_search_state_machine.gd —— FullHaul 容器搜索子状态机（Loot/Container 域）
##
## 职责：
##   实现架构文档 §2.2 的容器搜索子状态机（规范 4.3），驱动单个容器从
##   UNOPENED 到 COMPLETED 的完整搜索/揭晓生命周期。
##
## 状态流转（对应架构 §2.2）：
##   [UNOPENED] --首次打开--> [MASKED] --开始揭晓--> [REVEALING] <-> [PARTIALLY_REVEALED]
##       |                          |                         |             |
##       | 未打开不得暴露身份         |                         +--逐件揭晓---+
##       |                          +--全部揭晓完成--> [COMPLETED]（首次进入 +1，幂等 INV-06）
##
## 关键约束：
##   - INV-05：UNOPENED 容器不得提前暴露物品身份/品质/价值；MASKED 只显示
##     物品总数与每件物品当前方向完整占格（同尺寸视觉一致，禁止剪影/造型
##     蒙版），不得泄露身份/类别/品质/价值；未开始揭晓（MASKED）不得完成揭晓。
##   - INV-06：COMPLETED 首次进入时完成容器计数 +1；同一容器不重复计数（幂等）。
##
## 设计要点：
##   1. 纯逻辑（extends RefCounted），零 Godot 节点依赖，可独立单元测试
##      （架构原则 2）。
##   2. 一容器一实例；由 ContainerSearchService 登记并推进（架构 §1.1
##      Loot/Container 域）。
##   3. 依赖注入 IEventBus（可选）：发布 CONTAINER_OPENED/ITEM_REVEAL_STARTED/
##      ITEM_REVEALED/CONTAINER_COMPLETED 领域事件（架构 §2.3）。
##   4. 逐件揭晓按实例幂等：同一 instance_id 只揭晓一次，重复 complete_reveal
##      不重复计入已揭晓数（物品揭晓逻辑）；揭晓完成信号供局级计数使用。
##
## 说明：容器内揭晓顺序（TBD-03）、搜索中断/恢复（TBD-02）为规范未确定
## 事项，此处不填默认值；揭晓顺序由调用方逐件 start_reveal 驱动，实施依赖处
## 必须停工提问（规范 10.1）。

extends RefCounted
class_name ContainerSearchStateMachine


## 容器搜索子状态机的运行阶段（对应架构 §2.2）
enum Phase {
	UNOPENED,             # 容器未打开；不得提前暴露物品身份/品质/价值（INV-05）
	MASKED,               # 遮罩态：只显示物品总数与完整占格形状
	REVEALING,            # 正在对某件物品揭晓计时
	PARTIALLY_REVEALED,   # 已有已揭晓物品仍有遮罩物品
	COMPLETED,            # 揭晓序列全部完成（首次进入 +1，幂等 INV-06）
}

## 注入的事件总线（可选，用于发布领域事件）
var _bus: IEventBus = null
## 注入的配置加载器（用于品质揭晓耗时等；可选）
var _config_loader: IConfigLoader = null

## 容器唯一标识
var container_id: String = ""
## 容器类型 id（可选，架构 §5 ContainerState type_id；登记时设置）
var type_id: String = ""
## 当前阶段
var phase: Phase = Phase.UNOPENED
## 本容器内物品总数（首次打开时确定，INV-05 遮罩计数）
var item_count := 0
## 已揭晓完成的物品数（用于判定 COMPLETED）
var revealed_count := 0
## 是否已完成过计数（INV-06 幂等保护：同一容器只 +1 一次）
var counted := false
## 本容器内物品实例 id 列表（可选；打开时登记，遮罩计数与最终尺寸一致）
var item_instance_ids: Array = []
## 已揭晓的物品实例 id -> true（物品揭晓幂等：同一实例只揭晓一次）
var _revealed_instances: Dictionary = {}


func _init(p_container_id := "", bus: IEventBus = null, config_loader: IConfigLoader = null) -> void:
	container_id = p_container_id
	_bus = bus
	_config_loader = config_loader


## 首次打开容器 -> MASKED（INV-05）。
## item_count 为容器内物品总数（遮罩态显示）；p_instance_ids 为容器内物品
## 实例 id 列表（可选）：提供时以实例数为准，保证遮罩计数与最终揭晓一致。
## 已打开过返回 false（重复打开忽略）。
func open(p_item_count: int, p_instance_ids: Array = []) -> bool:
	if phase != Phase.UNOPENED:
		return false
	item_instance_ids = p_instance_ids.duplicate()
	item_count = item_instance_ids.size() if not item_instance_ids.is_empty() else p_item_count
	phase = Phase.MASKED
	if _bus != null:
		var shapes := _build_masked_shapes(item_count)
		_bus.publish(DomainEvents.Events.CONTAINER_OPENED,
			DomainEvents.ContainerOpened.new(container_id, item_count, shapes))
	return true


## 开始对一件物品揭晓计时 -> REVEALING。
## rarity 为该物品品质（决定揭晓耗时，来自配置）；instance_id 标识该物品实例。
## UNOPENED / COMPLETED 不可开始揭晓；已全部揭晓不可再开始（INV-05）。
func start_reveal(instance_id: String, rarity: String) -> bool:
	if phase not in [Phase.MASKED, Phase.REVEALING, Phase.PARTIALLY_REVEALED]:
		return false
	if revealed_count >= item_count:
		## 已全部揭晓，不应再开始新揭晓
		return false
	phase = Phase.REVEALING
	if _bus != null:
		var wait_time := _reveal_wait(rarity)
		_bus.publish(DomainEvents.Events.ITEM_REVEAL_STARTED,
			DomainEvents.ItemRevealStarted.new(container_id, instance_id, rarity, wait_time))
	return true


## 一件物品揭晓完成。
## 仅可在 REVEALING / PARTIALLY_REVEALED 阶段完成揭晓（须先 start_reveal，
## INV-05）；同一实例只揭晓一次，重复揭晓返回 false（物品揭晓幂等）。
## 返回是否「本次揭晓使容器首次完成并计数」（INV-06 局级计数触发信号）。
func complete_reveal(instance_id: String, definition_id: String, rarity: String,
		value: int, size: Vector2i) -> bool:
	if phase == Phase.COMPLETED:
		return false
	if phase not in [Phase.REVEALING, Phase.PARTIALLY_REVEALED]:
		return false
	if _revealed_instances.has(instance_id):
		return false
	_revealed_instances[instance_id] = true
	if _bus != null:
		_bus.publish(DomainEvents.Events.ITEM_REVEALED,
			DomainEvents.ItemRevealed.new(container_id, instance_id, definition_id, rarity, value, size))
	revealed_count = min(revealed_count + 1, item_count)
	if revealed_count >= item_count:
		return _complete()
	phase = Phase.PARTIALLY_REVEALED
	return false


## 进入 COMPLETED；首次进入时完成容器计数 +1（幂等 INV-06）。
## 返回是否本次真正执行了「首次完成计数」（false 表示已计数）。
func _complete() -> bool:
	phase = Phase.COMPLETED
	if not counted:
		counted = true
		if _bus != null:
			_bus.publish(DomainEvents.Events.CONTAINER_COMPLETED,
				DomainEvents.ContainerCompleted.new(container_id))
		return true
	return false


## 是否已完成（供外部判定，INV-06/INV-07 依赖完成数）。
func is_completed() -> bool:
	return phase == Phase.COMPLETED


## 是否首次完成（用于状态机内部/测试断言：counted 只置位一次）。
func was_counted() -> bool:
	return counted


## 构建遮罩态的占格形状列表（INV-05：只含数量与形状，不含身份/品质/价值）。
## 说明：V0.1 阶段形状统一以 1x1 占位；具体物品形状由 Item&Inventory
## 切片提供，此处仅保证「遮罩计数」语义成立。
func _build_masked_shapes(count: int) -> Array:
	var shapes: Array = []
	for i in count:
		shapes.append(Vector2i.ONE)
	return shapes


## 获取指定品质的揭晓耗时（秒）；读取配置单一来源（INV-16）。
func _reveal_wait(rarity: String) -> float:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			return cfg.get_reveal_duration(rarity)
	return 1.0
