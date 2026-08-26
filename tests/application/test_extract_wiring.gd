## test_extract_wiring.gd —— FullHaul 接线测试：Extract 接入编排器（GdUnit4）
##
## 职责：
##   切片 7：验证 RunFlowOrchestrator 接入 Extract 域后的接线行为：
##   - 编排器暴露 extract_service() 访问器（供表现层/后续切片经接口访问）
##   - 新一局初始化发布 EXTRACT_LOCKED（撤离锁定态，INV-07）
##   - 完成数达到阈值后 EXTRACT_UNLOCKED 解锁（INV-07），开始撤离进入
##     EXTRACTING（INV-08）
##   - tick_extraction 双计时并行推进：读条先归零 -> RUN_SUCCEEDED；
##     总时间先归零 -> RUN_FAILED（INV-08/AC-11）
##   - 未注入 ExtractService 时回退占位行为（既有流程不受影响）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/application/test_extract_wiring.gd --ignoreHeadlessMode

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
		DomainEvents.Events.RUN_INITIALIZED,
		DomainEvents.Events.EXTRACT_LOCKED,
		DomainEvents.Events.EXTRACT_UNLOCKED,
		DomainEvents.Events.EXTRACT_STARTED,
		DomainEvents.Events.RUN_SUCCEEDED,
		DomainEvents.Events.RUN_FAILED,
		DomainEvents.Events.RUN_SETTLED,
	]:
		var captured: int = event_id
		_bus.call("subscribe", event_id, func(_payload: RefCounted): _received.append(captured))


## 组装带 RunSession + ContainerSearch + Extract 域的编排器（切片 4/6/7）。
func _wired_orchestrator() -> Dictionary:
	var bus := _LocalBusAdapter.new(_bus)
	var store := _InMemoryStateStore.new()
	var run_session := RunSessionService.new(store, bus, _FakeConfigLoader.new())
	var container_search := ContainerSearchService.new(bus, _FakeConfigLoader.new())
	var extract := ExtractService.new(store, _FakeConfigLoader.new())
	var orch := RunFlowOrchestrator.new(bus, store, _FakeConfigLoader.new(),
		null, null, run_session, null, container_search, extract)
	return {"orch": orch, "extract": extract, "store": store}


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


## 完成必搜容器数使撤离解锁，返回 IN_RUN_EXTRACTABLE 阶段。
func _unlock_extract(orch: RunFlowOrchestrator) -> void:
	_enter_run(orch)
	for i in 5:
		_complete_one(orch, "c-%d" % i, "i-%d" % i)
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)


## [Wiring] 编排器暴露 extract_service() 访问器（领域接口类型）
func test_orchestrator_exposes_extract_service() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]

	assert_that(orch.extract_service()).is_not_null()
	assert_that(orch.extract_service() is IExtractService).is_true()
	## 解锁判定端点可用：锁定态（完成数 0）未解锁
	_enter_run(orch)
	assert_that(orch.extract_service().is_extract_unlocked(parts["store"].read())).is_false()


## [Wiring] 新一局初始化发布 EXTRACT_LOCKED（撤离锁定，INV-07/AC-03）
func test_run_init_publishes_extract_locked() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]

	_enter_run(orch)
	assert_that(_count(DomainEvents.Events.EXTRACT_LOCKED)).is_equal(1)
	assert_that(_count(DomainEvents.Events.EXTRACT_UNLOCKED)).is_equal(0)


## [Wiring] 完成数达到阈值解锁（EXTRACT_UNLOCKED），开始撤离进入 EXTRACTING
## 并重置读条（INV-07/08）
func test_unlock_then_start_extraction() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var store: _InMemoryStateStore = parts["store"]

	_unlock_extract(orch)
	assert_that(_count(DomainEvents.Events.EXTRACT_UNLOCKED)).is_equal(1)
	assert_that(store.read().completed_container_count).is_equal(5)

	orch.start_extraction()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.EXTRACTING)
	assert_that(_count(DomainEvents.Events.EXTRACT_STARTED)).is_equal(1)
	## 撤离读条重置为配置撤离时长 15（INV-16）
	assert_that(store.read().remaining_extraction_time).is_equal(15)


## [Wiring] tick_extraction 并行推进：读条先归零 -> RUN_SUCCEEDED（INV-08/AC-11）
func test_tick_extraction_success() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var store: _InMemoryStateStore = parts["store"]

	_unlock_extract(orch)
	orch.start_extraction()

	## 部分推进：双计时并行递减，尚未落定
	assert_that(orch.tick_extraction(5.0)).is_false()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.EXTRACTING)
	assert_that(store.read().remaining_match_time).is_equal(175)
	assert_that(store.read().remaining_extraction_time).is_equal(10)

	## 读条先归零（总时间仍有剩余）-> 撤离成功
	assert_that(orch.tick_extraction(10.0)).is_true()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.RUN_SUCCEEDED)
	assert_that(_count(DomainEvents.Events.RUN_SUCCEEDED)).is_equal(1)


## [Wiring] tick_extraction 并行推进：总时间先归零 -> RUN_FAILED（INV-08/AC-11）
func test_tick_extraction_failure() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var store: _InMemoryStateStore = parts["store"]

	_unlock_extract(orch)
	## 全局计时先耗到 12 秒（未归零，不触发超时）
	assert_that(orch.tick_match_time(168.0)).is_false()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)
	orch.start_extraction()
	assert_that(store.read().remaining_match_time).is_equal(12)

	## 总时间先归零（读条仍有剩余）-> 撤离失败
	assert_that(orch.tick_extraction(13.0)).is_true()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.RUN_FAILED)
	assert_that(_count(DomainEvents.Events.RUN_FAILED)).is_equal(1)


## [Wiring] 未注入 ExtractService：回退占位行为，既有流程不受影响
func test_fallback_without_extract_service() -> void:
	var bus := _LocalBusAdapter.new(_bus)
	var orch := RunFlowOrchestrator.new(bus, _InMemoryStateStore.new(), _FakeConfigLoader.new())

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	## 未接线时访问器返回 null，tick_extraction 不推进
	assert_that(orch.extract_service()).is_null()
	assert_that(orch.tick_extraction(5.0)).is_false()
	## 既有占位流程不受影响
	for i in 5:
		orch.complete_container_placeholder()
	orch.start_extraction()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.EXTRACTING)
	orch.complete_extraction_placeholder()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.RUN_SUCCEEDED)