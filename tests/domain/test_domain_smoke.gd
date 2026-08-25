## test_domain_smoke.gd —— FullHaul 领域层冒烟测试（基础框架验证，GdUnit4）
##
## 职责：
##   对领域层的纯逻辑（顶层状态机、RunState 幂等、容器搜索子状态机、
##   接口骨架）做基础验证，保证基础框架搭建后可运行、可自检。
##   原独立 SceneTree 冒烟脚本（godot-docs《Unit testing》约定）已按
##   WORD-25 于 2026-08-25 迁移为 GdUnit4 套件：用例语义与覆盖不变，
##   统一为 assert_that 断言风格，与其余领域套件及 VSCode 测试插件兼容。
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/domain/test_domain_smoke.gd --ignoreHeadlessMode

extends GdUnitTestSuite


## [RunState] 结算幂等（INV-09）
func test_run_state_settled_idempotent() -> void:
	var state := RunState.new("run-1", 180, 15)
	assert_that(state.mark_settled()).is_true()
	assert_that(state.mark_settled()).is_false()
	assert_that(state.settled).is_true()


## [TopLevelStateMachine] 全流程合法流转
func test_top_level_state_machine_flow() -> void:
	## 用测试桩注入，隔离真实 Autoload
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var loader := _FakeConfigLoader.new()

	var sm := TopLevelStateMachine.new(bus, store, loader)
	sm.boot()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.BOOT)

	sm.on_boot_ok()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)

	sm.on_start_match_requested()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.LOADOUT)

	sm.on_loadout_confirmed("run-2")
	assert_that(sm.current_phase()).is_equal(RunState.Phase.RUN_INIT)
	assert_that(store.read().run_id).is_equal("run-2")

	sm.on_run_init_ok()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)

	sm.on_required_containers_completed()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)

	sm.on_extract_started()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.EXTRACTING)

	sm.on_extraction_complete()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.RUN_SUCCEEDED)

	sm.on_settled()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.SETTLED)
	assert_that(store.read().settled).is_true()

	sm.on_settled_confirmed()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)


## [TopLevelStateMachine] 非法转移被拦截
func test_top_level_state_machine_invalid_transition() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var loader := _FakeConfigLoader.new()

	var sm := TopLevelStateMachine.new(bus, store, loader)
	sm.boot()
	sm.on_boot_ok()  # -> OUT_OF_RUN

	## OUT_OF_RUN 只允许去 LOADOUT，直接开始撤离应被拒绝
	sm.on_extract_started()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)
	assert_that(bus.has_published(DomainEvents.Events.EXTRACT_STARTED)).is_false()


## [TopLevelStateMachine] 关键节点发布领域事件
func test_top_level_state_machine_events() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var loader := _FakeConfigLoader.new()

	var sm := TopLevelStateMachine.new(bus, store, loader)
	sm.boot()
	sm.on_boot_ok()
	assert_that(bus.has_published(DomainEvents.Events.OUT_OF_RUN_ENTERED)).is_true()

	sm.on_start_match_requested()
	assert_that(bus.has_published(DomainEvents.Events.START_MATCH_REQUESTED)).is_true()

	sm.on_loadout_confirmed("run-3")
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


## [TopLevelStateMachine] 容器完成计数与撤离解锁阈值（INV-06/07 域拆分）
func test_top_level_state_machine_container_completed() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var loader := _FakeConfigLoader.new()

	var sm := TopLevelStateMachine.new(bus, store, loader)
	sm.boot()
	sm.on_boot_ok()
	sm.on_start_match_requested()
	sm.on_loadout_confirmed("run-c")
	sm.on_run_init_ok()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)

	## 完成数未达阈值（默认 5）时不应解锁撤离（INV-07）
	for i in 3:
		sm.on_container_completed()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.IN_RUN_LOCKED)
	assert_that(bus.has_published(DomainEvents.Events.EXTRACT_UNLOCKED)).is_false()

	## 补足到阈值 5 -> 撤离解锁（INV-07）
	sm.on_container_completed()
	sm.on_container_completed()
	assert_that(sm.current_phase()).is_equal(RunState.Phase.IN_RUN_EXTRACTABLE)
	assert_that(bus.has_published(DomainEvents.Events.EXTRACT_UNLOCKED)).is_true()
	assert_int(store.read().completed_container_count).is_greater_equal(5)


## [ContainerSearchStateMachine] 容器搜索子状态机全流程（架构 §2.2）
func test_container_search_state_machine_flow() -> void:
	var bus := _FakeEventBus.new()
	var csm := ContainerSearchStateMachine.new("c-1", bus, null)

	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.UNOPENED)

	## 打开 -> MASKED（INV-05）
	csm.open(3)
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.MASKED)
	assert_that(bus.has_published(DomainEvents.Events.CONTAINER_OPENED)).is_true()

	## 逐件揭晓 -> PARTIALLY_REVEALED
	assert_that(csm.start_reveal("i-1", "common")).is_true()
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.REVEALING)
	assert_that(bus.has_published(DomainEvents.Events.ITEM_REVEAL_STARTED)).is_true()

	csm.complete_reveal("i-1", "def-1", "common", 10, Vector2i.ONE)
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.PARTIALLY_REVEALED)

	## 全部揭晓完成 -> COMPLETED
	csm.start_reveal("i-2", "rare")
	csm.complete_reveal("i-2", "def-2", "rare", 50, Vector2i.ONE)
	csm.start_reveal("i-3", "epic")
	csm.complete_reveal("i-3", "def-3", "epic", 200, Vector2i.ONE)
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.COMPLETED)
	assert_that(csm.is_completed()).is_true()
	assert_that(bus.has_published(DomainEvents.Events.CONTAINER_COMPLETED)).is_true()


## [ContainerSearchStateMachine] 完成计数幂等（INV-06）
func test_container_search_state_machine_idempotent_count() -> void:
	var csm := ContainerSearchStateMachine.new("c-2", null, null)
	csm.open(1)
	csm.start_reveal("i-1", "common")
	csm.complete_reveal("i-1", "def-1", "common", 10, Vector2i.ONE)
	assert_that(csm.is_completed()).is_true()
	assert_that(csm.was_counted()).is_true()

	## 重复完成揭晓不应重复计数（INV-06 幂等）
	csm.complete_reveal("i-1", "def-1", "common", 10, Vector2i.ONE)
	assert_that(csm.is_completed()).is_true()
	assert_that(csm.was_counted()).is_true()


## [ContainerSearchStateMachine] 遮罩不泄露身份（INV-05）
func test_container_search_state_machine_mask() -> void:
	## UNOPENED 容器不得提前暴露身份；打开后进入 MASKED 只含数量与形状
	var csm := ContainerSearchStateMachine.new("c-3", null, null)
	assert_that(csm.start_reveal("i-1", "common")).is_false()
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.UNOPENED)

	csm.open(2)
	assert_that(csm.phase).is_equal(ContainerSearchStateMachine.Phase.MASKED)
	## 重复打开被忽略
	csm.open(5)
	assert_int(csm.item_count).is_equal(2)


## [DomainInterfaces] 领域层接口骨架可实例化且为 RefCounted
func test_domain_interfaces_contracts() -> void:
	## 各领域接口骨架均为 RefCounted（领域层零 Node 依赖，架构原则 2）
	var ifaces := [
		ILoadoutService.new(),
		IRunSessionService.new(),
		IItemInventoryService.new(),
		IContainerSearchService.new(),
		IExtractService.new(),
		ISettlementService.new(),
		IWarehouseService.new(),
		ITransactionService.new(),
		IEventBus.new(),
		IConfigLoader.new(),
		IRunStateStore.new(),
		IProfileRepository.new(),
	]
	for iface in ifaces:
		assert_that(iface is RefCounted) \
			.override_failure_message("%s 应为 RefCounted（领域层纯逻辑）" % iface.get_class()) \
			.is_true()


## ---- 测试桩（等价于独立测试命名空间，不依赖真实 Autoload）----

## 假事件总线：记录发布过的事件 ID
class _FakeEventBus:
	extends IEventBus
	var published: Array[int] = []

	func publish(event_id: int, payload: RefCounted = null) -> void:
		published.append(event_id)

	func has_published(event_id: int) -> bool:
		return event_id in published


## 内存局内状态存储
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
