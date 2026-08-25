## test_profile_loadout_wiring.gd —— FullHaul 接线测试：Profile + Loadout 接入编排器（GdUnit4）
##
## 职责：
##   切片 3：验证 RunFlowOrchestrator 接入 Loadout 域与局外账户持久化后的接线行为：
##   - 开局初始化局外账户（全新档案写入初始货币，INV-16/AC-21）
##   - 确认入场经 LoadoutService 购买扣款（走 Transaction 域原子性，INV-12）
##   - 扣款成功后落库局外账户（货币/已选背包）
##   - 余额不足时确认被拦截，留在 LOADOUT，不推进对局
##   - 未注入 LoadoutService 时回退占位行为（既有流程不受影响）
##   - 领域事件（BACKPACK_PURCHASED / CURRENCY_CHANGED）经总线广播
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/application/test_profile_loadout_wiring.gd --ignoreHeadlessMode

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
		DomainEvents.Events.START_MATCH_REQUESTED,
		DomainEvents.Events.BACKPACK_PURCHASED,
		DomainEvents.Events.CURRENCY_CHANGED,
		DomainEvents.Events.RUN_INITIALIZED,
	]:
		var captured: int = event_id
		_bus.call("subscribe", event_id, func(_payload: RefCounted): _received.append(captured))


func _count(event_id: int) -> int:
	return _received.count(event_id)


## 组装带数据层 + Loadout 域的编排器（内存后端，共享数据源）。
func _wired_orchestrator() -> Dictionary:
	var store := InMemoryDataStore.new()
	var set := RepositorySet.new()
	set.config_data = MemoryConfigDataRepository.new(store)
	set.profile = MemoryProfileRepository.new(store)
	set.run_result = MemoryRunResultRepository.new(store)
	set.run_snapshot = MemoryRunSnapshotRepository.new(store)

	var bus := _LocalBusAdapter.new(_bus)
	var tx := TransactionService.new(set.run_result)
	var loadout := LoadoutService.new(_FakeConfigLoader.new(), tx, bus)
	var orch := RunFlowOrchestrator.new(bus, _InMemoryStateStore.new(),
		_FakeConfigLoader.new(), set, loadout)
	return {"orch": orch, "store": store}


## [Wiring] 开局初始化局外账户：全新档案写入初始货币（INV-16/AC-21）
func test_start_seeds_initial_currency() -> void:
	var orch: RunFlowOrchestrator = _wired_orchestrator()["orch"]
	orch.start()

	var profile := orch.current_profile()
	assert_that(profile).is_not_null()
	assert_that(profile.currency).is_equal(100000)
	assert_that(profile.warehouse_item_ids.is_empty()).is_true()
	assert_that(profile.selected_backpack_offer_id).is_equal("")


## [Wiring] 已初始化档案不重复写入初始货币
func test_start_does_not_reseed_initialized_profile() -> void:
	var parts := _wired_orchestrator()
	var store: InMemoryDataStore = parts["store"]
	store.profile = PlayerProfile.new(5000)
	store.profile.selected_backpack_offer_id = "backpack_5x5"

	var orch: RunFlowOrchestrator = parts["orch"]
	orch.start()
	assert_that(orch.current_profile().currency).is_equal(5000)
	assert_that(orch.current_profile().selected_backpack_offer_id).is_equal("backpack_5x5")


## [Wiring] 确认入场：购买扣款（Transaction 原子）+ 落库局外账户 + 事件广播
func test_confirm_loadout_purchases_and_persists() -> void:
	var parts := _wired_orchestrator()
	var store: InMemoryDataStore = parts["store"]
	var orch: RunFlowOrchestrator = parts["orch"]

	orch.start()
	orch.request_start_match()
	assert_that(orch.select_backpack("backpack_4x4")).is_true()
	orch.confirm_loadout()

	## 已进入局内锁定态（RUN_INITIALIZED 事件）
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(_count(DomainEvents.Events.RUN_INITIALIZED)).is_equal(1)

	## 局外账户落库：扣款 1000 后余额 99000，已选背包记录（INV-12）
	assert_that(store.profile.currency).is_equal(99000)
	assert_that(store.profile.selected_backpack_offer_id).is_equal("backpack_4x4")
	## 事务流水已记录（防重 INV-12）
	assert_that(store.transactions.size()).is_equal(1)
	assert_that(store.transactions[0].get("type")).is_equal("purchase")
	assert_that(store.transactions[0].get("amount")).is_equal(-1000)

	## 事件广播：BACKPACK_PURCHASED + CURRENCY_CHANGED
	assert_that(_count(DomainEvents.Events.BACKPACK_PURCHASED)).is_equal(1)
	assert_that(_count(DomainEvents.Events.CURRENCY_CHANGED)).is_equal(1)


## [Wiring] 余额不足：确认被拦截，留在 LOADOUT，不推进对局、不落库变动
func test_confirm_loadout_insufficient_blocks() -> void:
	var parts := _wired_orchestrator()
	var store: InMemoryDataStore = parts["store"]
	store.profile = PlayerProfile.new(100)
	var orch: RunFlowOrchestrator = parts["orch"]

	orch.start()
	orch.request_start_match()
	orch.select_backpack("backpack_6x6")
	orch.confirm_loadout()

	## 留在 LOADOUT：不推进 RUN_INIT（AC-02 扣款失败留在装载）
	assert_that(orch.current_phase()).is_equal(RunState.Phase.LOADOUT)
	assert_that(_count(DomainEvents.Events.RUN_INITIALIZED)).is_equal(0)
	assert_that(_count(DomainEvents.Events.BACKPACK_PURCHASED)).is_equal(0)
	assert_that(store.profile.currency).is_equal(100)
	assert_that(store.profile.selected_backpack_offer_id).is_equal("")
	assert_that(store.transactions.is_empty()).is_true()


## [Wiring] 选择校验：不存在的档位选择失败
func test_select_backpack_validates_offer() -> void:
	var orch: RunFlowOrchestrator = _wired_orchestrator()["orch"]
	orch.start()
	assert_that(orch.select_backpack("nope")).is_false()
	assert_that(orch.select_backpack("backpack_4x4")).is_true()


## [Wiring] 未注入 LoadoutService：回退占位行为，既有流程不受影响
func test_confirm_loadout_fallback_without_service() -> void:
	var store := InMemoryDataStore.new()
	var set := RepositorySet.new()
	set.profile = MemoryProfileRepository.new(store)
	set.run_result = MemoryRunResultRepository.new(store)
	var orch := RunFlowOrchestrator.new(_LocalBusAdapter.new(_bus), _InMemoryStateStore.new(),
		_FakeConfigLoader.new(), set)

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(_count(DomainEvents.Events.RUN_INITIALIZED)).is_equal(1)
	## 无 Loadout 域：不产生购买事件
	assert_that(_count(DomainEvents.Events.BACKPACK_PURCHASED)).is_equal(0)
	assert_that(store.transactions.is_empty()).is_true()