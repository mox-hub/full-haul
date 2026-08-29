## test_run_flow_orchestrator.gd —— FullHaul 接线测试：应用编排层（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖 WORD-26 新增的应用编排层 RunFlowOrchestrator：
##   「进入一局 -> 探索搜集 -> 撤离 -> 结算 -> 返回局外」最小流程的
##   用例编排与事件发布（WORD-26 验收标准 1/2 的无头等价验证）。
##
## 覆盖映射：
##   - 完整成功流程：OUT_OF_RUN -> ... -> RUN_SUCCEEDED -> SETTLED -> OUT_OF_RUN
##   - 失败流程：局内超时 -> RUN_FAILED -> 结算返回
##   - 局外守卫：占位搜索在局外无效（不污染领域状态）
##   - 多局隔离：连续两局 runId 唯一、完成数复位（INV-14）
##   - 结算幂等：重复 settle 不重复发布 RUN_SETTLED（INV-09）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/application/test_run_flow_orchestrator.gd --ignoreHeadlessMode

extends GdUnitTestSuite

const EventBusScript := preload("res://autoload/EventBus.gd")

## 本地事件总线适配器：把测试内 EventBus 实例桥接为 IEventBus
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


## 内存态状态存储
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
		DomainEvents.Events.EXTRACT_STARTED,
		DomainEvents.Events.RUN_SUCCEEDED,
		DomainEvents.Events.RUN_FAILED,
		DomainEvents.Events.RUN_SETTLED,
	]:
		var captured: int = event_id
		_bus.call("subscribe", event_id, func(_payload: RefCounted): _received.append(captured))


func _orchestrator(store: _InMemoryStateStore) -> RunFlowOrchestrator:
	return RunFlowOrchestrator.new(_LocalBusAdapter.new(_bus), store, _FakeConfigLoader.new())


func _count(event_id: int) -> int:
	return _received.count(event_id)


## [RunFlowOrchestrator] 完整成功流程：最小玩法验证闭环（WORD-26 验收 1）
func test_full_success_flow() -> void:
	var store := _InMemoryStateStore.new()
	var orch := _orchestrator(store)

	## 启动 -> 局外
	orch.start()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)
	assert_that(_count(DomainEvents.Events.OUT_OF_RUN_ENTERED)).is_equal(1)

	## 请求开始 -> 入场装载
	orch.request_start_match()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.LOADOUT)
	assert_that(_count(DomainEvents.Events.START_MATCH_REQUESTED)).is_equal(1)

	## 确认入场 -> 局内锁定（RUN_INITIALIZED 事件）
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(_count(DomainEvents.Events.RUN_INITIALIZED)).is_equal(1)
	assert_that(store.read().run_id).is_equal("run-0001")

	## 探索搜集（占位）：完成 4 个仍锁定，第 5 个解锁撤离（INV-07）
	for i in 4:
		assert_that(orch.complete_container_placeholder()).is_equal(i + 1)
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(_count(DomainEvents.Events.EXTRACT_UNLOCKED)).is_equal(0)

	assert_that(orch.complete_container_placeholder()).is_equal(5)
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)
	assert_that(_count(DomainEvents.Events.EXTRACT_UNLOCKED)).is_equal(1)

	## 开始撤离 -> 撤离读条完成（占位） -> 撤离成功
	orch.start_extraction()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.EXTRACTING)
	assert_that(_count(DomainEvents.Events.EXTRACT_STARTED)).is_equal(1)

	orch.complete_extraction_placeholder()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.RUN_SUCCEEDED)
	assert_that(_count(DomainEvents.Events.RUN_SUCCEEDED)).is_equal(1)

	## 结算 -> 已结算 -> 确认返回局外
	orch.settle()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.SETTLED)
	assert_that(_count(DomainEvents.Events.RUN_SETTLED)).is_equal(1)

	orch.confirm_settled()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)
	assert_that(_count(DomainEvents.Events.OUT_OF_RUN_ENTERED)).is_equal(2)


## [RunFlowOrchestrator] 失败流程：局内超时 -> 失败结算 -> 返回局外
func test_timeout_failure_flow() -> void:
	var store := _InMemoryStateStore.new()
	var orch := _orchestrator(store)

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)

	## 本局时间耗尽（占位）：锁定态直接失败
	orch.timeout_placeholder()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.RUN_FAILED)
	assert_that(_count(DomainEvents.Events.RUN_FAILED)).is_equal(1)

	orch.settle()
	orch.confirm_settled()
	assert_that(orch.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)


## [RunFlowOrchestrator] 局外守卫：占位搜索在局外无效，不污染状态
func test_placeholder_search_guarded_out_of_run() -> void:
	var store := _InMemoryStateStore.new()
	var orch := _orchestrator(store)

	orch.start()
	assert_that(orch.complete_container_placeholder()).is_equal(-1)
	assert_that(orch.completed_container_count()).is_equal(0)
	assert_that(store.read().completed_container_count).is_equal(0)


## [RunFlowOrchestrator] 多局隔离：连续两局 runId 唯一、完成数复位（INV-14）
func test_consecutive_runs_isolated() -> void:
	var store := _InMemoryStateStore.new()
	var orch := _orchestrator(store)

	## 第一局：完成 5 容器后撤离成功结算
	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	for i in 5:
		orch.complete_container_placeholder()
	orch.start_extraction()
	orch.complete_extraction_placeholder()
	orch.settle()
	orch.confirm_settled()
	var first_run_id := store.read().run_id

	## 第二局：runId 递增唯一，完成数从 0 重新计数
	orch.request_start_match()
	orch.confirm_loadout()
	assert_that(store.read().run_id != first_run_id).is_true()
	assert_that(store.read().run_id).is_equal("run-0002")
	assert_that(store.read().completed_container_count).is_equal(0)
	assert_that(orch.completed_container_count()).is_equal(0)
	assert_that(orch.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)


## [RunFlowOrchestrator] 结算幂等：重复 settle 不重复发布 RUN_SETTLED（INV-09）
func test_settle_idempotent_events() -> void:
	var store := _InMemoryStateStore.new()
	var orch := _orchestrator(store)

	orch.start()
	orch.request_start_match()
	orch.confirm_loadout()
	orch.timeout_placeholder()

	orch.settle()
	orch.settle()
	assert_that(_count(DomainEvents.Events.RUN_SETTLED)).is_equal(1)
	assert_that(orch.current_phase()).is_equal(RunState.Phase.SETTLED)


## [RunFlowOrchestrator] 地图随机刷新：同种子产生完全一致的容器计划
## （类型与位置逐条一致；不同种子则位置分布不同）
func test_map_spawn_seed_determinism() -> void:
	var plan_a := _spawn_plan_with_seed(1234)
	var plan_b := _spawn_plan_with_seed(1234)
	var plan_c := _spawn_plan_with_seed(5678)
	assert_int(plan_a.size()).is_equal(9)
	for i in plan_a.size():
		assert_str(str(plan_a[i].get("container_id"))).is_equal(
			str(plan_b[i].get("container_id")))
		assert_str(str(plan_a[i].get("display_name"))).is_equal(
			str(plan_b[i].get("display_name")))
		assert_that(plan_a[i].get("map_pos")).is_equal(plan_b[i].get("map_pos"))
	## 位置全部落在 0..1 归一化地图场内
	for entry: Dictionary in plan_a:
		var pos: Vector2 = entry.get("map_pos", Vector2.ZERO)
		assert_bool(pos.x >= 0.0 and pos.x <= 1.0 and pos.y >= 0.0 and pos.y <= 1.0).is_true()
	## 不同种子下位置序列不同（9 个布点全同的概率可忽略）
	var differs := false
	for i in plan_a.size():
		if plan_a[i].get("map_pos") != plan_c[i].get("map_pos"):
			differs = true
			break
	assert_bool(differs).is_true()


func _spawn_plan_with_seed(seed_value: int) -> Array:
	var orch := _orchestrator(_InMemoryStateStore.new())
	orch.set_map_seed(seed_value)
	orch._build_match_containers()
	return orch.match_containers()
