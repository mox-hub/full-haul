## test_top_level_state_machine.gd —— FullHaul 地基测试：
##   顶层状态机（规范 4.2，GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖架构 §2.1 顶层状态机，驱动一局从 BOOT 到 SETTLED
##   的完整生命周期流转。
##
## 覆盖映射：
##   - AC-02 入场装载（LOADOUT 确认/取消）
##   - AC-03 对局初始化（RUN_INIT）
##   - AC-09/10/11 撤离锁定/解锁/撤离（INV-07/08）
##   - AC-12/13/15 结算流转（INV-09 幂等）
##   - 非法转移防护（INV 单向受控）
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_top_level_state_machine.gd --ignoreHeadlessMode

extends GdUnitTestSuite

## 事件总线 mock：记录发布的事件 id
class _FakeEventBus:
	extends IEventBus
	var published: Array[int] = []

	func publish(event_id: int, payload: RefCounted = null) -> void:
		published.append(event_id)

	func has_published(event_id: int) -> bool:
		return event_id in published


## 内存态状态存储 mock
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


func _sm(bus: _FakeEventBus, store: _InMemoryStateStore) -> TopLevelStateMachine:
	return TopLevelStateMachine.new(bus, store, _FakeConfigLoader.new())


## [TopLevelStateMachine] 完整合法流转：BOOT -> ... -> SETTLED -> OUT_OF_RUN（AC-02/03/09/10/12/13/15）
func test_full_legal_flow() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var sm := _sm(bus, store)

	sm.boot()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.BOOT)

	sm.on_boot_ok()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)
	assert_that(bus.has_published(DomainEvents.Events.OUT_OF_RUN_ENTERED)).is_true()

	sm.on_start_match_requested()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.LOADOUT)

	sm.on_loadout_confirmed("run-2")
	assert_that(sm.current_phase()).is_equal(RunState.Phase.RUN_INIT)
	assert_that(store.read().run_id).is_equal("run-2")
	assert_that(bus.has_published(DomainEvents.Events.RUN_INITIALIZED)).is_true()

	sm.on_run_init_ok()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)

	sm.on_required_containers_completed()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)
	assert_that(bus.has_published(DomainEvents.Events.EXTRACT_UNLOCKED)).is_true()

	sm.on_extract_started()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.EXTRACTING)

	sm.on_extraction_complete()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.RUN_SUCCEEDED)

	sm.on_settled()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.SETTLED)
	assert_that(store.read().settled).is_true()

	sm.on_settled_confirmed()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)


## [TopLevelStateMachine] 失败分支：加载失败 -> ERROR；总时间归零 -> RUN_FAILED
func test_failure_paths() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()

	## 加载失败 -> ERROR
	var sm1 := _sm(bus, store)
	sm1.boot()
	sm1.on_boot_error()
	assert_that(sm1.current_phase()).is_equal(RunState.Phase.ERROR)

	## 撤离后总时间归零 -> RUN_FAILED
	var sm2 := _sm(bus, store)
	sm2.boot()
	sm2.on_boot_ok()
	sm2.on_start_match_requested()
	sm2.on_loadout_confirmed("run-f")
	sm2.on_run_init_ok()
	sm2.on_required_containers_completed()
	sm2.on_extract_started()
	sm2.on_timeout()
	assert_that(sm2.current_phase()).is_equal(RunState.Phase.RUN_FAILED)
	assert_that(bus.has_published(DomainEvents.Events.RUN_FAILED)).is_true()

	sm2.on_settled()
	assert_that(sm2.current_phase()).is_equal(RunState.Phase.SETTLED)


## [TopLevelStateMachine] 非法转移防护：OUT_OF_RUN 不能直接进入 EXTRACTING
func test_invalid_transition_guarded() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var sm := _sm(bus, store)

	sm.boot()
	sm.on_boot_ok()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)

	## OUT_OF_RUN 直接开始撤离应被拒绝
	sm.on_extract_started()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)
	assert_that(bus.has_published(DomainEvents.Events.EXTRACT_STARTED)).is_false()


## [TopLevelStateMachine] 完成数阈值判定：<5 不撤离解锁，>=5 解锁（INV-07，AC-09/10）
func test_container_completed_threshold() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var sm := _sm(bus, store)

	sm.boot()
	sm.on_boot_ok()
	sm.on_start_match_requested()
	sm.on_loadout_confirmed("run-c")
	sm.on_run_init_ok()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)

	## 默认阈值 5，先完成 3 个仍锁定
	for i in 3:
		sm.on_container_completed()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(bus.has_published(DomainEvents.Events.EXTRACT_UNLOCKED)).is_false()

	## 达到阈值 5 -> 撤离解锁
	sm.on_container_completed()
	sm.on_container_completed()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)
	assert_that(bus.has_published(DomainEvents.Events.EXTRACT_UNLOCKED)).is_true()
	assert_that(store.read().completed_container_count).is_greater_equal(5)


## [TopLevelStateMachine] 结算幂等：重复 on_settled 不重复转移/发布（INV-09，AC-12/13）
func test_settle_idempotent() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var sm := _sm(bus, store)

	sm.boot()
	sm.on_boot_ok()
	sm.on_start_match_requested()
	sm.on_loadout_confirmed("run-s")
	sm.on_run_init_ok()
	sm.on_required_containers_completed()
	sm.on_extract_started()
	sm.on_extraction_complete()
	sm.on_settled()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.SETTLED)

	## 再次结算应被幂等忽略，状态不变
	sm.on_settled()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.SETTLED)


## [TopLevelStateMachine] 关键领域事件按序发布（架构 §2.3 事件流）
func test_domain_events_sequence() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var sm := _sm(bus, store)

	sm.boot()
	sm.on_boot_ok()
	assert_that(bus.has_published(DomainEvents.Events.OUT_OF_RUN_ENTERED)).is_true()

	sm.on_start_match_requested()
	assert_that(bus.has_published(DomainEvents.Events.START_MATCH_REQUESTED)).is_true()

	sm.on_loadout_confirmed("run-e")
	assert_that(bus.has_published(DomainEvents.Events.RUN_INITIALIZED)).is_true()

	sm.on_run_init_ok()
	sm.on_required_containers_completed()
	assert_that(bus.has_published(DomainEvents.Events.EXTRACT_UNLOCKED)).is_true()

	sm.on_extract_started()
	assert_that(bus.has_published(DomainEvents.Events.EXTRACT_STARTED)).is_true()

	sm.on_extraction_complete()
	assert_that(bus.has_published(DomainEvents.Events.RUN_SUCCEEDED)).is_true()

	sm.on_settled()
	assert_that(bus.has_published(DomainEvents.Events.RUN_SETTLED)).is_true()


## [TopLevelStateMachine] WORD-26：取消装载/结算确认返回局外均广播
## OUT_OF_RUN_ENTERED（表现层页面切换依赖「每次进入局外」都有事件）
func test_out_of_run_reentry_events() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var sm := _sm(bus, store)

	sm.boot()
	sm.on_boot_ok()
	assert_that(bus.published.count(DomainEvents.Events.OUT_OF_RUN_ENTERED)).is_equal(1)

	## 取消装载返回局外 -> 再次广播
	sm.on_start_match_requested()
	sm.on_loadout_cancelled()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)
	assert_that(bus.published.count(DomainEvents.Events.OUT_OF_RUN_ENTERED)).is_equal(2)

	## 完整一局后确认结算返回局外 -> 再次广播
	sm.on_start_match_requested()
	sm.on_loadout_confirmed("run-re")
	sm.on_run_init_ok()
	sm.on_required_containers_completed()
	sm.on_extract_started()
	sm.on_extraction_complete()
	sm.on_settled()
	sm.on_settled_confirmed()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)
	assert_that(bus.published.count(DomainEvents.Events.OUT_OF_RUN_ENTERED)).is_equal(3)
