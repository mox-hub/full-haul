## test_run_session_service.gd —— FullHaul 领域测试：RunSession 域服务（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖切片 4 落地的 RunSessionService（架构 §1.1 RunSession 域、
##   §5 RunState 实体）。
##
## 覆盖映射：
##   - AC-03：创建一局唯一 Run 实例（runId、双计时、完成数=0、撤离锁定、
##     settled=false）
##   - 事件流：创建成功后发布 RUN_INITIALIZED（matchDuration/完成数/锁定/结算）
##   - 双计时：全局计时（总时间）推进归零 -> 失败；当前目标计时（撤离读条）
##     推进归零 -> 成功（INV-07/08）
##   - 完成容器数计数（INV-06/07 依赖完成数）
##   - INV-07：撤离解锁阈值（完成数 >= 配置阈值）
##   - 一局一实例，经 IRunStateStore 读写（P1-3 禁止全局静态单例）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_run_session_service.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## 假事件总线：记录发布的事件 id 与 payload
class _FakeEventBus:
	extends IEventBus
	var published: Array = []

	func publish(event_id: int, payload: RefCounted = null) -> void:
		published.append({"event": event_id, "payload": payload})

	func has_published(event_id: int) -> bool:
		for entry in published:
			if entry.get("event", -1) == event_id:
				return true
		return false

	func last_payload(event_id: int):
		for i in range(published.size() - 1, -1, -1):
			if published[i].get("event", -1) == event_id:
				return published[i].get("payload", null)
		return null


## 假配置加载器：返回默认 GameConfig
class _FakeConfigLoader:
	extends IConfigLoader

	func get_config() -> GameConfig:
		return GameConfig.new()


## 内存态局内状态存储
class _InMemoryStateStore:
	extends IRunStateStore
	var _state: RunState = null

	func read() -> RunState:
		return _state

	func write(state: RunState) -> void:
		_state = state


## 组装被测 RunSessionService。
func _service() -> Dictionary:
	var store := _InMemoryStateStore.new()
	var bus := _FakeEventBus.new()
	var svc := RunSessionService.new(store, bus, _FakeConfigLoader.new())
	return {"svc": svc, "bus": bus, "store": store}


## [RunSessionService] AC-03：创建一局 Run 实例（runId、双计时、完成数=0、
## 撤离锁定、settled=false）
func test_create_run_ac03() -> void:
	var parts := _service()
	var svc: RunSessionService = parts["svc"]
	var state := svc.create_run("run-1", 180, 15)

	assert_that(state).is_not_null()
	assert_that(state.run_id).is_equal("run-1")
	assert_that(state.phase).is_equal(RunState.Phase.RUN_INIT)
	## 双计时：全局计时 = 总时长 180；当前目标计时 = 撤离读条 15
	assert_that(state.remaining_match_time).is_equal(180)
	assert_that(state.remaining_extraction_time).is_equal(15)
	## 完成数=0、settled=false（AC-03）
	assert_that(state.completed_container_count).is_equal(0)
	assert_that(state.settled).is_false()


## [RunSessionService] 创建成功后持久化到 IRunStateStore 并发布 RUN_INITIALIZED
func test_create_run_persists_and_publishes() -> void:
	var parts := _service()
	var svc: RunSessionService = parts["svc"]
	var bus: _FakeEventBus = parts["bus"]
	var store: _InMemoryStateStore = parts["store"]

	var state := svc.create_run("run-2", 180, 15)
	## 一局一实例：状态存储持有所建实例（P1-3）
	assert_that(store.read()).is_same(state)
	## 事件：RUN_INITIALIZED（matchDuration=180、完成数=0、撤离锁定、settled=false）
	assert_that(bus.has_published(DomainEvents.Events.RUN_INITIALIZED)).is_true()
	var evt: DomainEvents.RunInitialized = bus.last_payload(DomainEvents.Events.RUN_INITIALIZED)
	assert_that(evt.run_id).is_equal("run-2")
	assert_that(evt.match_duration).is_equal(180)
	assert_that(evt.completed_count).is_equal(0)
	assert_that(evt.extract_locked).is_true()
	assert_that(evt.settled).is_false()


## [RunSessionService] 完成容器计数 +1（INV-06/INV-07 依赖完成数）
func test_on_container_completed_increments() -> void:
	var parts := _service()
	var svc: RunSessionService = parts["svc"]
	var state := svc.create_run("run-3", 180, 15)

	svc.on_container_completed(state)
	assert_that(state.completed_container_count).is_equal(1)
	svc.on_container_completed(state)
	assert_that(state.completed_container_count).is_equal(2)
	## 状态同步写回存储
	assert_that(parts["store"].read().completed_container_count).is_equal(2)


## [RunSessionService] 全局计时推进：未耗尽返回 false，耗尽（总时间=0）返回 true
func test_tick_match_time() -> void:
	var parts := _service()
	var svc: RunSessionService = parts["svc"]
	svc.create_run("run-4", 10, 15)

	assert_that(svc.tick_match_time(4.0)).is_false()
	assert_that(svc.current_run().remaining_match_time).is_equal(6)
	assert_that(svc.tick_match_time(6.0)).is_true()
	assert_that(svc.current_run().remaining_match_time).is_equal(0)


## [RunSessionService] 当前目标计时（撤离读条）推进：耗尽返回 true（INV-08）
func test_tick_extraction_time() -> void:
	var parts := _service()
	var svc: RunSessionService = parts["svc"]
	svc.create_run("run-5", 180, 5)

	assert_that(svc.tick_extraction_time(3.0)).is_false()
	assert_that(svc.current_run().remaining_extraction_time).is_equal(2)
	assert_that(svc.tick_extraction_time(2.0)).is_true()
	assert_that(svc.current_run().remaining_extraction_time).is_equal(0)


## [RunSessionService] 双计时独立推进互不干扰（INV-08 并行计时的状态承载）
func test_dual_timers_independent() -> void:
	var parts := _service()
	var svc: RunSessionService = parts["svc"]
	svc.create_run("run-6", 10, 5)

	svc.tick_extraction_time(5.0)
	## 撤离读条耗尽不影响全局计时
	assert_that(svc.current_run().remaining_match_time).is_equal(10)
	assert_that(svc.current_run().remaining_extraction_time).is_equal(0)
	assert_that(svc.is_extract_unlocked(svc.current_run())).is_false()


## [RunSessionService] INV-07：完成数达到配置阈值后撤离解锁
func test_is_extract_unlocked_threshold() -> void:
	var parts := _service()
	var svc: RunSessionService = parts["svc"]
	var state := svc.create_run("run-7", 180, 15)

	## 默认阈值 5（配置单一来源 INV-16）
	assert_that(svc.required_completed_containers()).is_equal(5)
	for i in 4:
		svc.on_container_completed(state)
	assert_that(svc.is_extract_unlocked(state)).is_false()
	svc.on_container_completed(state)
	assert_that(svc.is_extract_unlocked(state)).is_true()


## [RunSessionService] 状态读写经 IRunStateStore（一局一实例，P1-3）
func test_current_and_save_run() -> void:
	var parts := _service()
	var svc: RunSessionService = parts["svc"]
	var store: _InMemoryStateStore = parts["store"]

	## 无实例时 current_run 返回 null
	assert_that(svc.current_run()).is_null()

	var state := svc.create_run("run-8", 180, 15)
	assert_that(svc.current_run()).is_same(state)
	state.completed_container_count = 3
	svc.save_run(state)
	assert_that(store.read().completed_container_count).is_equal(3)