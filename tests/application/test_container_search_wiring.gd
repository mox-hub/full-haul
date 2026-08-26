## test_container_search_wiring.gd —— FullHaul 接线测试：Loot/Container 接入编排器（GdUnit4）
##
## 职责：
##   切片 6：验证 RunFlowOrchestrator 接入 Loot / Container 域后的接线行为：
##   - 编排器暴露 container_search() 访问器（供表现层/后续切片经接口访问）
##   - 局内完成一个容器：完成数经容器搜索域统计（INV-06 幂等）并做撤离
##     解锁阈值判定（INV-07）
##   - 局外调用容器搜索用例不污染领域状态（局外守卫）
##   - 新一局开始清空容器登记（INV-14 多局隔离）
##   - 未注入 ContainerSearchService 时回退占位行为（既有流程不受影响）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/application/test_container_search_wiring.gd --ignoreHeadlessMode

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
		DomainEvents.Events.EXTRACT_UNLOCKED,
		DomainEvents.Events.EXTRACT_STARTED,
		DomainEvents.Events.RUN_SUCCEEDED,
		DomainEvents.Events.RUN_FAILED,
		DomainEvents.Events.RUN_SETTLED,
	]:
		var captured: int = event_id
		_bus.call("subscribe", event_id, func(_payload: RefCounted): _received.append(captured))


## 组装带 Loot / Container 域的编排器（切片 6）。
func _wired_orchestrator() -> Dictionary:
	var bus := _LocalBusAdapter.new(_bus)
	var store := _InMemoryStateStore.new()
	var run_session := RunSessionService.new(store, bus, _FakeConfigLoader.new())
	var container_search := ContainerSearchService.new(bus, _FakeConfigLoader.new())
	var orch := RunFlowOrchestrator.new(bus, store, _FakeConfigLoader.new(),
		null, null, run_session, null, container_search)
	return {"orch": orch, "container_search": container_search, "store": store}


func _count(event_id: int) -> int:
	return _received.count(event_id)


## 进入一局（OUT_OF_RUN -> LOADOUT -> IN_RUN_LOCKED）。
func _enter_run(orch: RunFlowOrchestrator) -> void:
	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)


## 在局内完整完成一个容器（打开 -> 揭晓 -> 完成）。
func _complete_one(orch: RunFlowOrchestrator, container_id: String, instance_id: String) -> void:
	assert_that(orch.open_container(container_id, 1, [instance_id])).is_true()
	assert_that(orch.start_reveal(container_id, instance_id, "common")).is_true()
	assert_that(orch.complete_reveal(container_id, instance_id, "def-1", "common", 10, Vector2i.ONE)).is_true()


## [Wiring] 编排器暴露 container_search() 访问器（领域接口类型）
func test_orchestrator_exposes_container_search() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]

	assert_that(orch.container_search()).is_not_null()
	assert_that(orch.container_search() is IContainerSearchService).is_true()
	## 经服务登记/打开容器端点可用
	_enter_run(orch)
	assert_that(orch.open_container("c-1", 2, ["i-1", "i-2"])).is_true()
	assert_that(orch.container_search().container("c-1")).is_not_null()
	assert_that(orch.container_search().container("c-1").item_count).is_equal(2)


## [Wiring] 局内完成 5 个容器：完成数按容器搜索域统计（INV-06），
## 达到阈值撤离解锁（INV-07）
func test_completing_required_containers_unlocks_extract() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var store: _InMemoryStateStore = parts["store"]

	_enter_run(orch)

	for i in 4:
		_complete_one(orch, "c-%d" % i, "i-%d" % i)
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(_count(DomainEvents.Events.EXTRACT_UNLOCKED)).is_equal(0)

	## 第 5 个完成 -> 撤离解锁（INV-07）
	_complete_one(orch, "c-4", "i-4")
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)
	assert_that(_count(DomainEvents.Events.EXTRACT_UNLOCKED)).is_equal(1)
	assert_that(store.read().completed_container_count).is_equal(5)


## [Wiring] 完成计数幂等（INV-06）：重复揭晓同一容器不重复计入局级完成数
func test_complete_reveal_idempotent_run_count() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var store: _InMemoryStateStore = parts["store"]

	_enter_run(orch)
	_complete_one(orch, "c-1", "i-1")
	assert_that(store.read().completed_container_count).is_equal(1)

	## 对已完成容器重复揭晓：返回 false，局级完成数不变（INV-06）
	assert_that(orch.complete_reveal("c-1", "i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	assert_that(store.read().completed_container_count).is_equal(1)


## [Wiring] 局外守卫：容器搜索用例在局外无效，不污染领域状态
func test_container_search_guarded_out_of_run() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var store: _InMemoryStateStore = parts["store"]

	orch.start()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)

	assert_that(orch.open_container("c-1", 1, ["i-1"])).is_false()
	assert_that(orch.start_reveal("c-1", "i-1", "common")).is_false()
	assert_that(orch.complete_reveal("c-1", "i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	## 未打开容器（未登记）且局级状态不被污染
	assert_that(orch.container_search().container("c-1")).is_null()
	assert_that(store.read().completed_container_count).is_equal(0)


## [Wiring] 新一局开始清空上局容器登记（INV-14 多局隔离）
func test_new_run_resets_container_registry() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]

	_enter_run(orch)
	_complete_one(orch, "c-1", "i-1")
	assert_that(orch.container_search().completed_container_count()).is_equal(1)

	## 回到局外再开新一局：容器登记被清空（INV-14）
	orch.start_extraction()
	orch.complete_extraction_placeholder()
	orch.settle()
	orch.confirm_settled()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.container_search().container("c-1")).is_null()
	assert_that(orch.container_search().completed_container_count()).is_equal(0)


## [Wiring] 未注入 ContainerSearchService：回退占位行为，既有流程不受影响
func test_fallback_without_container_search_service() -> void:
	var bus := _LocalBusAdapter.new(_bus)
	var orch := RunFlowOrchestrator.new(bus, _InMemoryStateStore.new(), _FakeConfigLoader.new())

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	## 未接线时访问器返回 null，容器搜索用例返回 false
	assert_that(orch.container_search()).is_null()
	assert_that(orch.open_container("c-1", 1, ["i-1"])).is_false()
	assert_that(orch.complete_reveal("c-1", "i-1", "def-1", "common", 10, Vector2i.ONE)).is_false()
	## 既有占位流程不受影响
	assert_that(orch.complete_container_placeholder()).is_equal(1)
