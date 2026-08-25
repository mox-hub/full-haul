## test_repository_wiring.gd —— FullHaul 数据层接线测试：编排器接入数据层（GdUnit4）
##
## 职责：
##   WORD-31 阶段2：验证 RunFlowOrchestrator 接入数据层后的接线行为：
##   - 开局加载配置数据（IConfigDataRepository）
##   - 局内状态变更写运行时快照（IRunSnapshotRepository）
##   - 结算后写入存档（IRunResultRepository 结算记录 + IProfileRepository 局外账户）
##   - 既有事件驱动接线不变（RUN_INITIALIZED / RUN_SETTLED 等仍经总线广播）
##   - 数据可读回（重开等价：同一数据源新读）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/application/test_repository_wiring.gd --ignoreHeadlessMode

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


func _subscribe_flow_events() -> void:
	for event_id in [
		DomainEvents.Events.OUT_OF_RUN_ENTERED,
		DomainEvents.Events.START_MATCH_REQUESTED,
		DomainEvents.Events.RUN_INITIALIZED,
		DomainEvents.Events.EXTRACT_UNLOCKED,
		DomainEvents.Events.EXTRACT_STARTED,
		DomainEvents.Events.RUN_SUCCEEDED,
		DomainEvents.Events.RUN_FAILED,
		DomainEvents.Events.RUN_SETTLED,
	]:
		var captured: int = event_id
		_bus.call("subscribe", event_id, func(_payload: RefCounted): _received.append(captured))


func _count(event_id: int) -> int:
	return _received.count(event_id)


## 构造带数据层的编排器（内存后端，共享数据源）。
func _wired_orchestrator() -> RunFlowOrchestrator:
	var store := InMemoryDataStore.new()
	store.item_definitions = {"item_001": {"definition_id": "item_001", "name": "能量饮料"}}
	store.backpack_offers = {"backpack_4x4": {"offer_id": "backpack_4x4", "price": 1000}}
	store.container_tier_weights = {"C1": {"common": 60, "rare": 10}}

	var set := RepositorySet.new()
	set.config_data = MemoryConfigDataRepository.new(store)
	set.profile = MemoryProfileRepository.new(store)
	set.run_result = MemoryRunResultRepository.new(store)
	set.run_snapshot = MemoryRunSnapshotRepository.new(store)

	return RunFlowOrchestrator.new(_LocalBusAdapter.new(_bus), _InMemoryStateStore.new(),
		_FakeConfigLoader.new(), set)


## [Wiring] 开局加载配置数据（IConfigDataRepository）
func test_start_loads_config_data() -> void:
	var orch := _wired_orchestrator()
	orch.start()

	var data := orch.loaded_config_data()
	assert_that(data.has("item_definitions")).is_true()
	assert_that(data.get("item_definitions").has("item_001")).is_true()
	assert_that(data.get("backpack_offers").has("backpack_4x4")).is_true()
	assert_that(data.get("container_tier_weights").has("C1")).is_true()


## [Wiring] 未接线数据层时 loaded_config_data 为空且流程不受影响
func test_no_repos_config_data_empty() -> void:
	var orch := RunFlowOrchestrator.new(_LocalBusAdapter.new(_bus), _InMemoryStateStore.new(),
		_FakeConfigLoader.new())
	orch.start()
	assert_that(orch.loaded_config_data().is_empty()).is_true()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)


## [Wiring] 局内状态变更写运行时快照（IRunSnapshotRepository）
func test_match_writes_run_snapshot() -> void:
	var store := InMemoryDataStore.new()
	var set := RepositorySet.new()
	set.config_data = MemoryConfigDataRepository.new(store)
	set.profile = MemoryProfileRepository.new(store)
	set.run_result = MemoryRunResultRepository.new(store)
	set.run_snapshot = MemoryRunSnapshotRepository.new(store)
	var orch := RunFlowOrchestrator.new(_LocalBusAdapter.new(_bus), _InMemoryStateStore.new(),
		_FakeConfigLoader.new(), set)

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	## 完成 5 个容器触发撤离解锁（INV-07），快照随每次变更覆盖写
	for i in 5:
		orch.complete_container_placeholder()

	var snap: RunState = store.run_snapshots.get("run-0001", null)
	assert_that(snap).is_not_null()
	assert_that(snap.completed_container_count).is_equal(5)
	assert_that(snap.phase).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)


## [Wiring] 结算后写入存档：结算记录 + 局外账户（成功路径 INV-10）
func test_settle_persists_archive_success() -> void:
	var store := InMemoryDataStore.new()
	store.profile = PlayerProfile.new(100000)
	var set := RepositorySet.new()
	set.config_data = MemoryConfigDataRepository.new(store)
	set.profile = MemoryProfileRepository.new(store)
	set.run_result = MemoryRunResultRepository.new(store)
	set.run_snapshot = MemoryRunSnapshotRepository.new(store)
	var orch := RunFlowOrchestrator.new(_LocalBusAdapter.new(_bus), _InMemoryStateStore.new(),
		_FakeConfigLoader.new(), set)
	_subscribe_flow_events()

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	for i in 5:
		orch.complete_container_placeholder()
	orch.start_extraction()
	## 模拟撤离成功携带物品
	store.run_snapshots["run-0001"].carried_item_ids = ["i-c1", "i-c2"]
	orch.complete_extraction_placeholder()
	orch.settle()

	## 结算记录已写入（run_id 唯一幂等 INV-09）
	var rec: Dictionary = store.settlements.get("run-0001", {})
	assert_that(rec.is_empty()).is_false()
	assert_that(rec.get("result")).is_equal("success")
	assert_that(rec.get("carried_item_ids")).contains_exactly(["i-c1", "i-c2"])

	## 局外账户已落库：撤离成功携带物品入库（INV-10）
	assert_that(store.profile.warehouse_item_ids).contains_exactly(["i-c1", "i-c2"])

	## 既有事件接线不变
	assert_that(_count(DomainEvents.Events.RUN_INITIALIZED)).is_equal(1)
	assert_that(_count(DomainEvents.Events.RUN_SETTLED)).is_equal(1)


## [Wiring] 结算后写入存档：失败路径安全箱物品入库（INV-11）
func test_settle_persists_archive_failure() -> void:
	var store := InMemoryDataStore.new()
	store.profile = PlayerProfile.new(100000)
	var set := RepositorySet.new()
	set.config_data = MemoryConfigDataRepository.new(store)
	set.profile = MemoryProfileRepository.new(store)
	set.run_result = MemoryRunResultRepository.new(store)
	set.run_snapshot = MemoryRunSnapshotRepository.new(store)
	var orch := RunFlowOrchestrator.new(_LocalBusAdapter.new(_bus), _InMemoryStateStore.new(),
		_FakeConfigLoader.new(), set)

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	orch.timeout_placeholder()
	store.run_snapshots["run-0001"].safe_item_ids = ["i-s1"]
	orch.settle()

	var rec: Dictionary = store.settlements.get("run-0001", {})
	assert_that(rec.get("result")).is_equal("failure")
	assert_that(rec.get("safe_item_ids")).contains_exactly(["i-s1"])
	assert_that(store.profile.warehouse_item_ids).contains_exactly(["i-s1"])


## [Wiring] 数据可读回：同一数据源重开等价读回（结算记录 + 局外账户）
func test_archive_readable_after_reopen() -> void:
	var store := InMemoryDataStore.new()
	store.profile = PlayerProfile.new(100000)
	var set := RepositorySet.new()
	set.config_data = MemoryConfigDataRepository.new(store)
	set.profile = MemoryProfileRepository.new(store)
	set.run_result = MemoryRunResultRepository.new(store)
	set.run_snapshot = MemoryRunSnapshotRepository.new(store)

	var orch := RunFlowOrchestrator.new(_LocalBusAdapter.new(_bus), _InMemoryStateStore.new(),
		_FakeConfigLoader.new(), set)
	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	for i in 5:
		orch.complete_container_placeholder()
	orch.start_extraction()
	store.run_snapshots["run-0001"].carried_item_ids = ["i-c1"]
	orch.complete_extraction_placeholder()
	orch.settle()

	## 「重开」：以同一数据源装配新仓储读回（V0.1 运行周期内持久化，TBD-12）
	var reopen_set := RepositorySet.new()
	reopen_set.config_data = MemoryConfigDataRepository.new(store)
	reopen_set.profile = MemoryProfileRepository.new(store)
	reopen_set.run_result = MemoryRunResultRepository.new(store)
	reopen_set.run_snapshot = MemoryRunSnapshotRepository.new(store)

	assert_that(reopen_set.run_result.find_settlement_by_run("run-0001").get("result")).is_equal("success")
	assert_that(reopen_set.profile.load().warehouse_item_ids).contains_exactly(["i-c1"])
	assert_that(reopen_set.run_snapshot.load_run_snapshot("run-0001")).is_not_null()