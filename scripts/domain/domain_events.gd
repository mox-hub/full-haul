## domain_events.gd —— FullHaul 领域事件定义（纯数据，领域层共享）
##
## 职责：
##   定义所有领域事件的「事件类型枚举」与「事件数据类」。本文件为纯数据
##   （extends RefCounted，无 Godot 节点依赖），供领域层、应用层、表现层与
##   事件总线共同引用（架构 §2.3 关键事件流）。
##
## 设计要点：
##   领域事件以「数据对象」承载（而非裸信号），便于跨层传递、事务化与防重
##   （架构 §4 事件总线建议）。领域层只依赖本纯数据类，不依赖任何 Autoload
##   节点，从而可独立测试（架构原则 2）。

extends RefCounted
class_name DomainEvents


## 事件类型枚举 —— 与架构文档 §2.3 关键事件流一一对应。
## 注意：战斗/生命/死亡相关事件（CombatStarted/HealthChanged/ActorDied 等）
## 已按 V0.1 规范范围删除（审核 P0-2），此处不提供。
enum Events {
	OUT_OF_RUN_ENTERED,        # 进入局外状态
	START_MATCH_REQUESTED,     # 请求开始一局
	BACKPACK_PURCHASED,        # 背包购买并扣款成功（INV-12）
	RUN_INITIALIZED,           # 对局初始化完成（AC-03）
	CONTAINER_OPENED,          # 容器被打开（INV-05）
	ITEM_REVEAL_STARTED,       # 某件物品开始揭晓计时
	ITEM_REVEALED,             # 某件物品揭晓完成
	CONTAINER_COMPLETED,       # 容器揭晓序列完成（幂等计数 INV-06）
	ITEM_PLACED,               # 物品放入格子（INV-01~05）
	ITEM_MOVED,                # 物品移动
	ITEM_ROTATED,              # 物品旋转
	ITEM_DROPPED,              # 物品丢弃
	EXTRACT_UNLOCKED,          # 撤离解锁（完成数 >= 5，INV-07）
	EXTRACT_LOCKED,            # 撤离重新锁定（完成数 < 5）
	EXTRACT_STARTED,           # 开始撤离读条（INV-08）
	RUN_SUCCEEDED,             # 撤离成功（INV-10）
	RUN_FAILED,                # 撤离失败（INV-11）
	RUN_SETTLED,               # 结算完成（幂等 INV-09）
	WAREHOUSE_ITEM_ADDED,      # 仓库入库
	ITEM_SOLD,                 # 物品出售（INV-12）
	CURRENCY_CHANGED,          # 货币变动（INV-12）
}

## OutOfRunEntered：进入局外状态
class OutOfRunEntered:
	extends RefCounted
	var at_time := 0

	func _init(p_at_time := 0) -> void:
		at_time = p_at_time

## StartMatchRequested：请求开始一局
class StartMatchRequested:
	extends RefCounted
	var at_time := 0

	func _init(p_at_time := 0) -> void:
		at_time = p_at_time

## BackpackPurchased：背包购买并扣款（INV-12）
class BackpackPurchased:
	extends RefCounted
	var offer_id: String = ""
	var price := 0
	var balance_before := 0
	var balance_after := 0

	func _init(p_offer_id := "", p_price := 0, p_balance_before := 0, p_balance_after := 0) -> void:
		offer_id = p_offer_id
		price = p_price
		balance_before = p_balance_before
		balance_after = p_balance_after

## RunInitialized：对局初始化（AC-03）
class RunInitialized:
	extends RefCounted
	var run_id: String = ""
	var match_duration := 180
	var completed_count := 0
	var extract_locked := true
	var settled := false

	func _init(p_run_id := "", p_match_duration := 180, p_completed_count := 0, p_extract_locked := true, p_settled := false) -> void:
		run_id = p_run_id
		match_duration = p_match_duration
		completed_count = p_completed_count
		extract_locked = p_extract_locked
		settled = p_settled

## ContainerOpened：容器被打开（INV-05）
class ContainerOpened:
	extends RefCounted
	var container_id: String = ""
	var unknown_count := 0
	var shapes: Array = []

	func _init(p_container_id := "", p_unknown_count := 0, p_shapes := []) -> void:
		container_id = p_container_id
		unknown_count = p_unknown_count
		shapes = p_shapes

## ItemRevealStarted：某件物品开始揭晓计时
class ItemRevealStarted:
	extends RefCounted
	var container_id: String = ""
	var instance_id: String = ""
	var rarity: String = ""
	var wait_time := 0.0

	func _init(p_container_id := "", p_instance_id := "", p_rarity := "", p_wait_time := 0.0) -> void:
		container_id = p_container_id
		instance_id = p_instance_id
		rarity = p_rarity
		wait_time = p_wait_time

## ItemRevealed：某件物品揭晓完成
class ItemRevealed:
	extends RefCounted
	var container_id: String = ""
	var instance_id: String = ""
	var definition_id: String = ""
	var rarity: String = ""
	var value := 0
	var size := Vector2i.ZERO

	func _init(p_container_id := "", p_instance_id := "", p_definition_id := "", p_rarity := "", p_value := 0, p_size := Vector2i.ZERO) -> void:
		container_id = p_container_id
		instance_id = p_instance_id
		definition_id = p_definition_id
		rarity = p_rarity
		value = p_value
		size = p_size

## ContainerCompleted：容器揭晓序列完成（幂等计数 INV-06）
class ContainerCompleted:
	extends RefCounted
	var container_id: String = ""

	func _init(p_container_id := "") -> void:
		container_id = p_container_id

## ItemPlaced / ItemMoved / ItemRotated / ItemDropped 共用的格子操作数据
class GridOpData:
	extends RefCounted
	var instance_id: String = ""
	var from := Vector2i.ZERO
	var to := Vector2i.ZERO

	func _init(p_instance_id := "", p_from := Vector2i.ZERO, p_to := Vector2i.ZERO) -> void:
		instance_id = p_instance_id
		from = p_from
		to = p_to

## ExtractUnlocked：撤离解锁（INV-07）
class ExtractUnlocked:
	extends RefCounted
	var completed_count := 0

	func _init(p_completed_count := 0) -> void:
		completed_count = p_completed_count

## ExtractLocked：撤离重新锁定
class ExtractLocked:
	extends RefCounted
	var completed_count := 0

	func _init(p_completed_count := 0) -> void:
		completed_count = p_completed_count

## ExtractStarted：开始撤离读条（INV-08）
class ExtractStarted:
	extends RefCounted
	var remaining_extraction_time := 15

	func _init(p_remaining_extraction_time := 15) -> void:
		remaining_extraction_time = p_remaining_extraction_time

## RunSucceeded：撤离成功（INV-10）
class RunSucceeded:
	extends RefCounted
	var run_id: String = ""
	var carried_item_ids: Array = []

	func _init(p_run_id := "", p_carried_item_ids := []) -> void:
		run_id = p_run_id
		carried_item_ids = p_carried_item_ids

## RunFailed：撤离失败（INV-11）
class RunFailed:
	extends RefCounted
	var run_id: String = ""
	var safe_item_ids: Array = []

	func _init(p_run_id := "", p_safe_item_ids := []) -> void:
		run_id = p_run_id
		safe_item_ids = p_safe_item_ids

## RunSettled：结算完成（幂等 INV-09）
class RunSettled:
	extends RefCounted
	var run_id: String = ""

	func _init(p_run_id := "") -> void:
		run_id = p_run_id

## WarehouseItemAdded：仓库入库
class WarehouseItemAdded:
	extends RefCounted
	var instance_id: String = ""

	func _init(p_instance_id := "") -> void:
		instance_id = p_instance_id

## ItemSold：物品出售（INV-12）
class ItemSold:
	extends RefCounted
	var instance_id: String = ""
	var price := 0
	var balance_before := 0
	var balance_after := 0

	func _init(p_instance_id := "", p_price := 0, p_balance_before := 0, p_balance_after := 0) -> void:
		instance_id = p_instance_id
		price = p_price
		balance_before = p_balance_before
		balance_after = p_balance_after

## CurrencyChanged：货币变动（INV-12）
class CurrencyChanged:
	extends RefCounted
	var delta := 0
	var balance_before := 0
	var balance_after := 0

	func _init(p_delta := 0, p_balance_before := 0, p_balance_after := 0) -> void:
		delta = p_delta
		balance_before = p_balance_before
		balance_after = p_balance_after
