## test_run_session_wiring.gd —— FullHaul 接线测试：RunSession 接入编排器（GdUnit4）
##
## 职责：
##   切片 4：验证 RunFlowOrchestrator 接入 RunSession 域后的接线行为：
##   - 确认入场时经 RunSessionService 创建本局会话（AC-03：双计时、完成数=0、
##     撤离锁定、settled=false），RUN_INITIALIZED 经总线广播
##   - 顶层状态机 RUN_INIT -> IN_RUN_LOCKED 会话状态接线
##   - 完成容器经 RunSessionService 计数（INV-06/07），达到阈值撤离解锁
##   - 全局计时推进（tick_match_time）耗尽 -> RUN_FAILED（INV-07/08）
##   - 未注入 RunSessionService 时回退占位行为（既有流程不受影响）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/application/test_run_session_wiring.gd --ignoreHeadlessMode

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
		DomainEvents.Events.RUN_INITIALIZED,
		DomainEvents.Events.EXTRACT_UNLOCKED,
		DomainEvents.Events.RUN_FAILED,
		DomainEvents.Events.RUN_SETTLED,
	]:
		var captured: int = event_id
		_bus.call("subscribe", event_id, func(_payload: RefCounted): _received.append(captured))


func _count(event_id: int) -> int:
	return _received.count(event_id)


## 组装带 RunSession 域的编排器（共享局内状态存储）。
func _wired_orchestrator() -> Dictionary:
	var store := _InMemoryStateStore.new()
	var bus := _LocalBusAdapter.new(_bus)
	var run_session := RunSessionService.new(store, bus, _FakeConfigLoader.new())
	var orch := RunFlowOrchestrator.new(bus, store, _FakeConfigLoader.new(), null, null, run_session)
	return {"orch": orch, "store": store, "run_session": run_session}


## [Wiring] 确认入场：RunSessionService 创建会话（AC-03 双计时/完成数=0/锁定/未结算）
func test_confirm_loadout_creates_run_session() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var store: _InMemoryStateStore = parts["store"]

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()

	## RUN_INIT -> IN_RUN_LOCKED 会话状态接线
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(_count(DomainEvents.Events.RUN_INITIALIZED)).is_equal(1)
	## 双计时与完成数（AC-03）
	assert_that(store.read().remaining_match_time).is_equal(180)
	assert_that(store.read().remaining_extraction_time).is_equal(15)
	assert_that(store.read().completed_container_count).is_equal(0)
	assert_that(store.read().settled).is_false()


## [Wiring] 完成容器经 RunSessionService 计数（INV-06/07），阈值解锁撤离
func test_container_completed_counts_via_run_session() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]
	var store: _InMemoryStateStore = parts["store"]

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()

	## 完成 4 个仍锁定
	for i in 4:
		assert_that(orch.complete_container_placeholder()).is_equal(i + 1)
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(_count(DomainEvents.Events.EXTRACT_UNLOCKED)).is_equal(0)
	## 计数写回 RunSession 状态存储
	assert_that(store.read().completed_container_count).is_equal(4)

	## 第 5 个达到阈值 -> 撤离解锁（INV-07）
	assert_that(orch.complete_container_placeholder()).is_equal(5)
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)
	assert_that(_count(DomainEvents.Events.EXTRACT_UNLOCKED)).is_equal(1)
	assert_that(parts["run_session"].is_extract_unlocked(store.read())).is_true()


## [Wiring] 全局计时推进：耗尽 -> RUN_FAILED（INV-07/08）
func test_tick_match_time_timeout_fails_run() -> void:
	var parts := _wired_orchestrator()
	var orch: RunFlowOrchestrator = parts["orch"]

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)

	## 推进 179 秒未耗尽
	assert_that(orch.tick_match_time(179.0)).is_false()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	## 最后一秒耗尽 -> RUN_FAILED
	assert_that(orch.tick_match_time(1.0)).is_true()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.RUN_FAILED)
	assert_that(_count(DomainEvents.Events.RUN_FAILED)).is_equal(1)


## [Wiring] 未注入 RunSessionService：回退占位行为，既有流程不受影响
func test_fallback_without_run_session_service() -> void:
	var store := _InMemoryStateStore.new()
	var orch := RunFlowOrchestrator.new(_LocalBusAdapter.new(_bus), store, _FakeConfigLoader.new())

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(_count(DomainEvents.Events.RUN_INITIALIZED)).is_equal(1)
	assert_that(store.read().remaining_match_time).is_equal(180)

	## 占位计时：未注入服务时 tick_match_time 不推进、不转移
	assert_that(orch.tick_match_time(200.0)).is_false()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)