## test_telemetry_wiring.gd —— FullHaul 接线测试：Telemetry + 携带 + 闭环（GdUnit4）
##
## 职责：
##   切片 9：验证 RunFlowOrchestrator 接入 Telemetry 域与「携带」闭环后的接线：
##   - 编排器暴露 telemetry() 访问器（未注入返回 null）
##   - carry_revealed_item：已揭晓物品携带入背包格子（INV-01/04）
##   - search_and_carry_container：完成容器计数 + 携带产出入背包（闭环「携带」）
##   - 完整成功闭环：进入一局 -> 搜刮携带 -> 撤离 -> 结算入库 -> 出售
##     （遥测逐事件留痕，不修改领域数据）
##   - 撤离落定快照携带物品到 RunState（INV-10/11，结算入库依赖）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/application/test_telemetry_wiring.gd --ignoreHeadlessMode

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


## 假配置数据仓储：种子物品定义（INV-16 单一来源，含 carry 所需 item_battery）
class _FakeConfigRepo:
	extends IConfigDataRepository

	var item_definitions: Dictionary = {}

	func _init() -> void:
		item_definitions = {
			"item_battery": {"definition_id": "item_battery", "name": "电池",
				"rarity": "common", "width": 1, "height": 1, "value": 40},
		}

	func load_item_definitions() -> Dictionary:
		return item_definitions

	func get_item_definition(definition_id: String) -> Dictionary:
		return item_definitions.get(definition_id, {})


var _bus: Node = null


func before_test() -> void:
	_bus = auto_free(EventBusScript.new())
	_bus.call("_ready")


## 组装带数据层 + ItemInventory + ContainerSearch + Settlement/Warehouse +
## Telemetry 域的编排器（模拟 main.gd 组合根装配，切片 9 全量接线）。
func _wired_orchestrator() -> Dictionary:
	var store := InMemoryDataStore.new()
	var set := RepositorySet.new()
	set.config_data = MemoryConfigDataRepository.new(store)
	set.profile = MemoryProfileRepository.new(store)
	set.run_result = MemoryRunResultRepository.new(store)
	set.run_snapshot = MemoryRunSnapshotRepository.new(store)

	var bus := _LocalBusAdapter.new(_bus)
	var tx := TransactionService.new(set.run_result)
	var item_inventory := ItemInventoryService.new(_FakeConfigRepo.new(), bus)
	var container_search := ContainerSearchService.new(bus, _FakeConfigLoader.new())
	var run_state_store := _InMemoryStateStore.new()
	var run_session := RunSessionService.new(run_state_store, bus, _FakeConfigLoader.new())
	var warehouse := WarehouseService.new(tx, func(instance_id: String) -> int:
		return 40 if instance_id.begins_with("s-") else 0)
	var settlement := SettlementService.new(warehouse)
	var telemetry := TelemetryService.new(bus)
	telemetry.start()
	var orch := RunFlowOrchestrator.new(bus, run_state_store,
		_FakeConfigLoader.new(), set, null, run_session, item_inventory,
		container_search, null, settlement, warehouse, telemetry)
	return {
		"orch": orch, "store": store, "telemetry": telemetry,
		"item_inventory": item_inventory,
	}


## [Wiring] 编排器暴露 telemetry() 访问器（未注入返回 null）
func test_orchestrator_exposes_telemetry() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]

	assert_that(orch.telemetry()).is_not_null()
	assert_that(orch.telemetry() is ITelemetryService).is_true()

	var bare := RunFlowOrchestrator.new(_LocalBusAdapter.new(_bus),
		_InMemoryStateStore.new(), _FakeConfigLoader.new())
	assert_that(bare.telemetry()).is_null()


## 进入一局并选择默认背包档位（确认入场初始化背包格子）。
func _enter_run_with_backpack(orch: RunFlowOrchestrator) -> void:
	orch.start()
	orch.request_start_match()
	orch.select_backpack("backpack_5x5")
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)


## [Wiring] carry_revealed_item：已揭晓物品携带入背包格子（INV-01/04）
func test_carry_revealed_item_places_into_backpack() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var item_inventory: ItemInventoryService = parts["item_inventory"]

	_enter_run_with_backpack(orch)
	## 确认入场已初始化背包格子（5x5）
	assert_that(item_inventory.get_grid(GridInventory.OwnerType.BACKPACK)).is_not_null()

	assert_that(orch.carry_revealed_item("s-001", "item_battery", Vector2i.ONE)).is_true()
	assert_that(orch.carried_item_count()).is_equal(1)
	## 背包格内确有此实例（INV-01 唯一归属）
	assert_that(item_inventory.get_item("s-001")).is_not_null()


## [Wiring] search_and_carry_container：完成容器计数 + 携带产出入背包
func test_search_and_carry_completes_container_and_carries() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]

	_enter_run_with_backpack(orch)

	var first: Dictionary = orch.search_and_carry_container()
	assert_that(first.get("completed_count")).is_equal(1)
	assert_that(first.get("carried_count")).is_equal(1)
	assert_that(orch.carried_item_count()).is_equal(1)

	## 撤离解锁阈值仍为 5（INV-07）
	for i in 4:
		var result: Dictionary = orch.search_and_carry_container()
		assert_that(result.get("completed_count")).is_equal(i + 2)
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)


## [Wiring] 完整成功闭环：进入一局 -> 搜刮携带 -> 撤离 -> 结算入库 -> 出售，
## 遥测逐事件留痕且不改领域数据（规范 6.4）
func test_full_success_chain_with_telemetry() -> void:
	var parts := _wired_orchestrator()
	var store: InMemoryDataStore = parts["store"]
	var orch: RunFlowOrchestrator = parts["orch"]
	var telemetry: TelemetryService = parts["telemetry"]

	## 进入一局
	_enter_run_with_backpack(orch)
	assert_that(store.profile.currency).is_equal(100000)  # AC-21 初始货币

	## 搜刮 + 携带（5 容器）
	for i in 5:
		orch.search_and_carry_container()
	assert_that(orch.carried_item_count()).is_equal(5)

	## 撤离 -> 撤离读条完成（成功）
	orch.start_extraction()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.EXTRACTING)
	orch.complete_extraction_placeholder()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.RUN_SUCCEEDED)
	## 撤离落定快照携带物品（INV-10）
	var state: RunState = store.run_snapshots.get("run-0001")
	assert_that(state).is_not_null()
	assert_that(state.carried_item_ids.size()).is_equal(5)

	## 结算入库（INV-10/INV-09 幂等）
	orch.settle()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.SETTLED)
	assert_that(store.profile.warehouse_item_ids.size()).is_equal(5)

	## 返回局外出售一件（INV-12 原子事务）
	orch.confirm_settled()
	var price := orch.sell_warehouse_item(store.profile.warehouse_item_ids[0])
	assert_that(price).is_equal(40)
	assert_that(store.profile.currency).is_equal(100040)

	## 遥测逐事件留痕（埋点，不构成产品规则来源）
	assert_that(telemetry.count(DomainEvents.Events.OUT_OF_RUN_ENTERED)).is_greater_equal(1)
	assert_that(telemetry.count(DomainEvents.Events.RUN_INITIALIZED)).is_equal(1)
	assert_that(telemetry.count(DomainEvents.Events.CONTAINER_COMPLETED)).is_equal(5)
	assert_that(telemetry.count(DomainEvents.Events.EXTRACT_STARTED)).is_equal(1)
	assert_that(telemetry.count(DomainEvents.Events.RUN_SUCCEEDED)).is_equal(1)
	assert_that(telemetry.count(DomainEvents.Events.RUN_SETTLED)).is_equal(1)
	assert_that(telemetry.count(DomainEvents.Events.ITEM_SOLD)).is_equal(1)


## [Wiring] 未注入 ContainerSearch/ItemInventory：search_and_carry 回退纯计数占位
func test_search_and_carry_fallback_without_services() -> void:
	var bus := _LocalBusAdapter.new(_bus)
	var orch := RunFlowOrchestrator.new(bus, _InMemoryStateStore.new(),
		_FakeConfigLoader.new(), null, null, null, null, null, null, null, null,
		null)

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()

	var result: Dictionary = orch.search_and_carry_container()
	assert_that(result.get("completed_count")).is_equal(1)
	assert_that(result.get("carried_count")).is_equal(0)
	assert_that(orch.carried_item_count()).is_equal(0)