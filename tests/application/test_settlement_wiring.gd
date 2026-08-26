## test_settlement_wiring.gd —— FullHaul 接线测试：Settlement + Warehouse 接入编排器（GdUnit4）
##
## 职责：
##   切片 8：验证 RunFlowOrchestrator 接入 Settlement/Warehouse 域后的接线行为：
##   - 编排器暴露 settlement_service() / warehouse_service() 访问器
##   - 成功结算：撤离成功携带物品经结算域入仓库并落库局外账户（INV-10）
##   - 失败结算：撤离失败安全箱物品入仓库（INV-11）
##   - 结算幂等：重复 settle 不重复入库、不重复广播 RUN_SETTLED（INV-09）
##   - 出售物品：sell_warehouse_item 货币加款（Transaction 原子，INV-12）
##     + 从仓库移除 + 落库局外账户
##   - 未注入 Settlement/Warehouse 时回退占位行为（既有流程不受影响）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/application/test_settlement_wiring.gd --ignoreHeadlessMode

extends GdUnitTestSuite

const EventBusScript := preload("res://autoload/EventBus.gd")

## 本地事件总线适配器：把测试内 EventBus 实例桥接到 IEventBus
class _LocalBusAdapter:
	extends IEventBus

	var _bus: Node = null

	func _init(bus: Node) -> void:
		_bus = bus

	func publish(event_id: int, payload: RefCounted = null) -> void:
		_bus.call("publish", event_id, payload)

	func subscribe(event_id: int, callback: Callable) -> int:
		return _bus.call("subscribe", event_id, callback)

	func unsubscribe(event_id: int, sub_id: int) -> void:
		_bus.call("unsubscribe", event_id, sub_id)


## 内存态局内状态存储
class _InMemoryStateStore:
	extends IRunStateStore

	var _state: RunState = null

	func read() -> RunState:
		return _state

	func write(state: RunState) -> void:
		_state = state


## 假配置加载器：返回默认 GameConfig
class _FakeConfigLoader:
	extends IConfigLoader

	func get_config() -> GameConfig:
		return GameConfig.new()


var _bus: Node = null
var _received: Array[int] = []


func before_test() -> void:
	_bus = auto_free(EventBusScript.new())
	_bus.call("_ready")
	_received = []
	for event_id in [
		DomainEvents.Events.OUT_OF_RUN_ENTERED,
		DomainEvents.Events.RUN_INITIALIZED,
		DomainEvents.Events.RUN_SUCCEEDED,
		DomainEvents.Events.RUN_FAILED,
		DomainEvents.Events.RUN_SETTLED,
	]:
		var captured: int = event_id
		_bus.call("subscribe", event_id, func(_payload: RefCounted): _received.append(captured))


func _count(event_id: int) -> int:
	return _received.count(event_id)


## 组装带数据层 + Settlement/Warehouse 域的编排器（内存后端，共享数据源）。
func _wired_orchestrator() -> Dictionary:
	var store := InMemoryDataStore.new()
	var set := RepositorySet.new()
	set.config_data = MemoryConfigDataRepository.new(store)
	set.profile = MemoryProfileRepository.new(store)
	set.run_result = MemoryRunResultRepository.new(store)
	set.run_snapshot = MemoryRunSnapshotRepository.new(store)

	var bus := _LocalBusAdapter.new(_bus)
	var tx := TransactionService.new(set.run_result)
	var warehouse := WarehouseService.new(tx, func(instance_id: String) -> int:
		return 200 if instance_id.begins_with("i-c") else 0)
	var settlement := SettlementService.new(warehouse)
	var orch := RunFlowOrchestrator.new(bus, _InMemoryStateStore.new(),
		_FakeConfigLoader.new(), set, null, null, null, null, null, settlement, warehouse)
	return {"orch": orch, "store": store}


## 进入一局并完成必搜容器，返回可撤离阶段（INV-07）。
func _unlock_extract(orch: RunFlowOrchestrator) -> void:
	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	for i in 5:
		orch.complete_container_placeholder()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)


## [Wiring] 编排器暴露 settlement_service() / warehouse_service() 访问器
func test_orchestrator_exposes_services() -> void:
	var orch: RunFlowOrchestrator = _wired_orchestrator()["orch"]

	assert_that(orch.settlement_service()).is_not_null()
	assert_that(orch.settlement_service() is ISettlementService).is_true()
	assert_that(orch.warehouse_service()).is_not_null()
	assert_that(orch.warehouse_service() is IWarehouseService).is_true()


## [Wiring] 成功结算：撤离成功携带物品入仓库 + 落库局外账户 + 事件（INV-10）
func test_success_settle_stores_carried_items() -> void:
	var parts := _wired_orchestrator()
	var store: InMemoryDataStore = parts["store"]
	var orch: RunFlowOrchestrator = parts["orch"]

	_unlock_extract(orch)
	orch.start_extraction()
	## 模拟撤离成功携带物品（INV-10）
	store.run_snapshots["run-0001"].carried_item_ids = ["i-c1", "i-c2"]
	orch.complete_extraction_placeholder()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.RUN_SUCCEEDED)

	orch.settle()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.SETTLED)
	assert_that(_count(DomainEvents.Events.RUN_SETTLED)).is_equal(1)

	## 结算域将携带物品入仓库并落库局外账户（INV-10）
	assert_that(store.profile.warehouse_item_ids).contains_exactly(["i-c1", "i-c2"])
	## 结算记录已持久化（run_id 唯一幂等 INV-09）
	var rec: Dictionary = store.settlements.get("run-0001", {})
	assert_that(rec.is_empty()).is_false()
	assert_that(rec.get("result")).is_equal("success")
	assert_that(rec.get("carried_item_ids")).contains_exactly(["i-c1", "i-c2"])


## [Wiring] 失败结算：撤离失败安全箱物品入仓库 + 落库（INV-11）
func test_failure_settle_stores_safe_items() -> void:
	var parts := _wired_orchestrator()
	var store: InMemoryDataStore = parts["store"]
	var orch: RunFlowOrchestrator = parts["orch"]

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	## 模拟撤离失败安全箱物品（INV-11）
	store.run_snapshots["run-0001"].safe_item_ids = ["i-s1"]
	orch.timeout_placeholder()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.RUN_FAILED)

	orch.settle()
	assert_that(store.profile.warehouse_item_ids).contains_exactly(["i-s1"])
	var rec: Dictionary = store.settlements.get("run-0001", {})
	assert_that(rec.get("result")).is_equal("failure")
	assert_that(rec.get("safe_item_ids")).contains_exactly(["i-s1"])


## [Wiring] 结算幂等：重复 settle 不重复入库、不重复广播 RUN_SETTLED（INV-09）
func test_settle_idempotent_no_duplicate() -> void:
	var parts := _wired_orchestrator()
	var store: InMemoryDataStore = parts["store"]
	var orch: RunFlowOrchestrator = parts["orch"]

	_unlock_extract(orch)
	orch.start_extraction()
	store.run_snapshots["run-0001"].carried_item_ids = ["i-c1"]
	orch.complete_extraction_placeholder()
	orch.settle()
	orch.settle()

	assert_that(_count(DomainEvents.Events.RUN_SETTLED)).is_equal(1)
	assert_that(store.profile.warehouse_item_ids).contains_exactly(["i-c1"])
	## 结算记录仍唯一（run_id 幂等，INV-09）
	assert_that(store.settlements.keys().size()).is_equal(1)


## [Wiring] 出售物品：货币加款（Transaction 原子）+ 从仓库移除 + 落库（INV-12/AC-14）
func test_sell_warehouse_item_credits_and_persists() -> void:
	var parts := _wired_orchestrator()
	var store: InMemoryDataStore = parts["store"]
	var orch: RunFlowOrchestrator = parts["orch"]

	orch.start()
	## 预置仓库物品：货币 100000 + 物品 i-c1（价值解析 200）
	store.profile.currency = 100000
	store.profile.warehouse_item_ids = ["i-c1"]

	var price := orch.sell_warehouse_item("i-c1")
	assert_that(price).is_equal(200)
	## 货币加款并落库（INV-12 守恒：100000 + 200）
	assert_that(store.profile.currency).is_equal(100200)
	assert_that(store.profile.warehouse_item_ids.is_empty()).is_true()
	## 事务流水已记录（type=sell）
	assert_that(store.transactions.size()).is_equal(1)
	assert_that(store.transactions[0].get("type")).is_equal("sell")


## [Wiring] 出售物品：价值非正（非 i-c 前缀）拒绝，无加款无流水
func test_sell_warehouse_item_rejects_unknown_value() -> void:
	var parts := _wired_orchestrator()
	var store: InMemoryDataStore = parts["store"]
	var orch: RunFlowOrchestrator = parts["orch"]

	orch.start()
	store.profile.currency = 100000
	store.profile.warehouse_item_ids = ["i-x1"]

	assert_that(orch.sell_warehouse_item("i-x1")).is_equal(0)
	assert_that(store.profile.currency).is_equal(100000)
	assert_that(store.profile.warehouse_item_ids).contains_exactly(["i-x1"])
	assert_that(store.transactions.is_empty()).is_true()


## [Wiring] 未注入 Settlement/Warehouse：回退占位行为，既有流程不受影响
func test_fallback_without_services() -> void:
	var bus := _LocalBusAdapter.new(_bus)
	var orch := RunFlowOrchestrator.new(bus, _InMemoryStateStore.new(), _FakeConfigLoader.new())

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(orch.settlement_service()).is_null()
	assert_that(orch.warehouse_service()).is_null()

	## 既有占位结算流程不受影响
	for i in 5:
		orch.complete_container_placeholder()
	orch.start_extraction()
	orch.complete_extraction_placeholder()
	orch.settle()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.SETTLED)
	assert_that(_count(DomainEvents.Events.RUN_SETTLED)).is_equal(1)
	## 出售无仓库服务：返回 0
	assert_that(orch.sell_warehouse_item("i-c1")).is_equal(0)
