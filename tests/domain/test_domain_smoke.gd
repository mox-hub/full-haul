## test_domain_smoke.gd —— FullHaul 领域层冒烟测试（基础框架验证）
##
## 职责：
##   对领域层的纯逻辑（顶层状态机、RunState 幂等）做基础验证，保证基础框架
##   搭建后可运行、可自检。本脚本可在 Godot 引擎中直接运行：
##
##   godot --headless --path . --script res://tests/domain/test_domain_smoke.gd
##
## 写法对齐 godot-docs《Unit testing》的约定：
##   1. 文件与用例函数均用 test_ 前缀命名，运行器按前缀自动发现用例；
##   2. 提供无参 test() 作为入口（引擎对 GDScript 测试脚本的契约）；
##   3. 用例名带域标签（如 [RunState]）；
##   4. 断言分级：check / check_message 记录失败后继续当前用例，
##      require / require_message 失败即中止当前用例；
##   5. 退出码 0=通过 / 1=失败，供 CI 判定。
##
## 说明：
##   本脚本为「基础框架地基」的冒烟自检（对应架构 §8 测试策略），
##   不依赖任何测试插件；正式用例按 AC/INV 映射补充 GUT/GdUnit（WORD-25）。

extends SceneTree

## 用例标题表：方法名 -> 带 [Tag] 的用例名；未登记的 test_ 方法回退用方法名
const CASE_TITLES := {
	"test_run_state_settled_idempotent":
		"[RunState] 结算幂等（INV-09）",
	"test_top_level_state_machine_events":
		"[TopLevelStateMachine] 关键节点发布领域事件",
	"test_top_level_state_machine_flow":
		"[TopLevelStateMachine] 全流程合法流转",
	"test_top_level_state_machine_invalid_transition":
		"[TopLevelStateMachine] 非法转移被拦截",
	"test_top_level_state_machine_container_completed":
		"[TopLevelStateMachine] 容器完成计数与撤离解锁阈值（INV-06/07 域拆分）",
	"test_container_search_state_machine_flow":
		"[ContainerSearchStateMachine] 容器搜索子状态机全流程",
	"test_container_search_state_machine_idempotent_count":
		"[ContainerSearchStateMachine] 完成计数幂等（INV-06）",
	"test_container_search_state_machine_mask":
		"[ContainerSearchStateMachine] 遮罩不泄露身份（INV-05）",
	"test_domain_interfaces_contracts":
		"[DomainInterfaces] 领域层接口骨架可实例化且为 RefCounted",
}

## 退出码约定：0=通过，1=失败
var _fail_count := 0
var _pass_count := 0


## SceneTree 脚本入口：执行 test() 并按结果设置退出码
func _initialize() -> void:
	var failed := test()
	quit(1 if failed > 0 else 0)


## 无参 test() 入口：按 test_ 前缀自动发现并执行全部用例，返回失败断言数
func test() -> int:
	print("== FullHaul 领域层冒烟测试开始 ==")
	for case_name: String in _collect_test_cases():
		print("[RUN ] %s" % _case_title(case_name))
		call(case_name)
	print("== 冒烟测试结束：%d 通过，%d 失败 ==" % [_pass_count, _fail_count])
	return _fail_count


## 收集全部无参 test_ 前缀方法（按名称排序，保证稳定的执行顺序）
func _collect_test_cases() -> Array[String]:
	var case_names: Array[String] = []
	for method: Dictionary in get_method_list():
		if String(method.name).begins_with("test_") and method.args.is_empty():
			case_names.append(method.name)
	case_names.sort()
	return case_names


func _case_title(case_name: String) -> String:
	return String(CASE_TITLES.get(case_name, case_name))


## ---- 断言（分级语义对齐 doctest 的 CHECK / REQUIRE）----

## CHECK：自解释断言，失败时记录并继续执行当前用例
func check(condition: bool) -> bool:
	return check_message(condition, "期望为真，实际为假")


## CHECK_MESSAGE：复杂断言附带说明，失败时记录并继续执行当前用例
func check_message(condition: bool, message: String) -> bool:
	if condition:
		_pass_count += 1
		print("  [PASS] %s" % message)
	else:
		_fail_count += 1
		print("  [FAIL] %s" % message)
	return condition


## REQUIRE：前置条件断言，失败时中止当前用例。用法：
##   if not require(cond): return
func require(condition: bool) -> bool:
	return require_message(condition, "期望为真，实际为假")


## REQUIRE_MESSAGE：带说明的前置条件断言，失败时中止当前用例。用法：
##   if not require_message(cond, "..."): return
func require_message(condition: bool, message: String) -> bool:
	var passed := check_message(condition, message)
	if not passed:
		print("  [ABORT] 前置条件不成立，跳过本用例剩余断言")
	return passed


## ---- 用例（命名约定：test_<被测对象>_<场景>）----

## [RunState] 结算幂等（INV-09）
func test_run_state_settled_idempotent() -> void:
	var state := RunState.new("run-1", 180, 15)
	check(state.mark_settled())
	check(not state.mark_settled())
	check(state.settled)


## [TopLevelStateMachine] 全流程合法流转
func test_top_level_state_machine_flow() -> void:
	## 用测试桩注入，隔离真实 Autoload
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var loader := _FakeConfigLoader.new()

	var sm := TopLevelStateMachine.new(bus, store, loader)
	sm.boot()
	## 初始阶段是后续所有断言的前置条件，不成立则本用例剩余部分无意义
	if not require_message(
		sm.current_phase() == RunState.Phase.BOOT, "boot() 后初始阶段为 BOOT"
	):
		return

	sm.on_boot_ok()
	check_message(
		sm.current_phase() == RunState.Phase.OUT_OF_RUN, "on_boot_ok 后进入 OUT_OF_RUN"
	)

	sm.on_start_match_requested()
	check_message(
		sm.current_phase() == RunState.Phase.LOADOUT, "请求开始对局后进入 LOADOUT"
	)

	sm.on_loadout_confirmed("run-2")
	check_message(
		sm.current_phase() == RunState.Phase.RUN_INIT, "确认装载后进入 RUN_INIT"
	)
	check_message(
		store.read().run_id == "run-2", "确认装载后写入本局 RunState（run_id=run-2）"
	)

	sm.on_run_init_ok()
	check_message(
		sm.current_phase() == RunState.Phase.IN_RUN_LOCKED,
		"初始化成功后进入 IN_RUN_LOCKED",
	)

	sm.on_required_containers_completed()
	check_message(
		sm.current_phase() == RunState.Phase.IN_RUN_EXTRACTABLE,
		"完成必搜容器后进入 IN_RUN_EXTRACTABLE",
	)

	sm.on_extract_started()
	check_message(
		sm.current_phase() == RunState.Phase.EXTRACTING, "开始撤离后进入 EXTRACTING"
	)

	sm.on_extraction_complete()
	check_message(
		sm.current_phase() == RunState.Phase.RUN_SUCCEEDED, "撤离读条完成后进入 RUN_SUCCEEDED"
	)

	sm.on_settled()
	check_message(sm.current_phase() == RunState.Phase.SETTLED, "结算后进入 SETTLED")
	check(store.read().settled)

	sm.on_settled_confirmed()
	check_message(
		sm.current_phase() == RunState.Phase.OUT_OF_RUN, "确认结算后回到 OUT_OF_RUN"
	)


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
	check_message(
		sm.current_phase() == RunState.Phase.OUT_OF_RUN,
		"OUT_OF_RUN 不可直接进入 EXTRACTING",
	)
	check(not bus.has_published(DomainEvents.Events.EXTRACT_STARTED))


## [TopLevelStateMachine] 关键节点发布领域事件
func test_top_level_state_machine_events() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var loader := _FakeConfigLoader.new()

	var sm := TopLevelStateMachine.new(bus, store, loader)
	sm.boot()
	sm.on_boot_ok()
	check(bus.has_published(DomainEvents.Events.OUT_OF_RUN_ENTERED))

	sm.on_start_match_requested()
	check(bus.has_published(DomainEvents.Events.START_MATCH_REQUESTED))

	sm.on_loadout_confirmed("run-3")
	check(bus.has_published(DomainEvents.Events.RUN_INITIALIZED))

	sm.on_extract_started()  # RUN_INIT 不可直接撤离，应被拦截
	check(not bus.has_published(DomainEvents.Events.EXTRACT_STARTED))


## [TopLevelStateMachine] 容器完成计数与撤离解锁阈值（INV-06/07 域拆分）
func test_top_level_state_machine_container_completed() -> void:
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var loader := _FakeConfigLoader.new()

	var sm := TopLevelStateMachine.new(bus, store, loader)
	sm.boot()
	sm.on_boot_ok()
	sm.on_start_match_requested()
	sm.on_loadout_confirmed("run-4")
	sm.on_run_init_ok()
	check(sm.current_phase() == RunState.Phase.IN_RUN_LOCKED)

	## 达到阈值前保持锁定
	var required := loader.get_config().required_completed_containers
	for i in required - 1:
		sm.on_container_completed()
	check(sm.current_phase() == RunState.Phase.IN_RUN_LOCKED)
	check(not bus.has_published(DomainEvents.Events.EXTRACT_UNLOCKED))

	## 达到阈值 -> 撤离解锁（INV-07）
	sm.on_container_completed()
	check(sm.current_phase() == RunState.Phase.IN_RUN_EXTRACTABLE)
	check(bus.has_published(DomainEvents.Events.EXTRACT_UNLOCKED))
	check(store.read().completed_container_count == required)


## [ContainerSearchStateMachine] 容器搜索子状态机全流程
func test_container_search_state_machine_flow() -> void:
	var bus := _FakeEventBus.new()
	var sm := ContainerSearchStateMachine.new("container-1", bus, null)
	check(sm.phase == ContainerSearchStateMachine.Phase.UNOPENED)

	sm.open(3)
	check(sm.phase == ContainerSearchStateMachine.Phase.MASKED)
	check(bus.has_published(DomainEvents.Events.CONTAINER_OPENED))

	sm.start_reveal("inst-1", "common")
	check(sm.phase == ContainerSearchStateMachine.Phase.REVEALING)

	sm.complete_reveal("inst-1", "def-1", "common", 100, Vector2i.ONE)
	check(sm.phase == ContainerSearchStateMachine.Phase.PARTIALLY_REVEALED)

	sm.start_reveal("inst-2", "rare")
	sm.complete_reveal("inst-2", "def-2", "rare", 500, Vector2i.ONE)
	sm.start_reveal("inst-3", "legendary")
	sm.complete_reveal("inst-3", "def-3", "legendary", 2000, Vector2i.ONE)

	check(sm.phase == ContainerSearchStateMachine.Phase.COMPLETED)
	check(sm.is_completed())
	check(bus.has_published(DomainEvents.Events.CONTAINER_COMPLETED))


## [ContainerSearchStateMachine] 完成计数幂等（INV-06）
func test_container_search_state_machine_idempotent_count() -> void:
	var bus := _FakeEventBus.new()
	var sm := ContainerSearchStateMachine.new("container-2", bus, null)
	sm.open(1)
	sm.start_reveal("inst-1", "common")
	sm.complete_reveal("inst-1", "def-1", "common", 100, Vector2i.ONE)

	check(sm.is_completed())
	check(sm.was_counted())
	check(bus.count_event(DomainEvents.Events.CONTAINER_COMPLETED) == 1)

	## 重复 complete 不再重复计数（幂等 INV-06）
	sm.complete_reveal("inst-1", "def-1", "common", 100, Vector2i.ONE)
	check(bus.count_event(DomainEvents.Events.CONTAINER_COMPLETED) == 1)


## [ContainerSearchStateMachine] 遮罩不泄露身份（INV-05）
func test_container_search_state_machine_mask() -> void:
	var bus := _FakeEventBus.new()
	var sm := ContainerSearchStateMachine.new("container-3", bus, null)
	sm.open(2)
	var opened: DomainEvents.ContainerOpened = bus.last_payload(DomainEvents.Events.CONTAINER_OPENED)
	check(opened != null)
	if opened != null:
		check(opened.unknown_count == 2)
		check(opened.shapes.size() == 2)
		## 遮罩形状统一为 1x1 占位，不含身份/品质/价值信息（INV-05）
		for shape in opened.shapes:
			check(shape == Vector2i.ONE)


## [DomainInterfaces] 领域层接口骨架可实例化且为 RefCounted
func test_domain_interfaces_contracts() -> void:
	## 域拆分接口均为纯 RefCounted 契约（架构 §3 接口原则）
	var ifaces: Array[RefCounted] = [
		ILoadoutService.new(),
		IItemInventoryService.new(),
		IContainerSearchService.new(),
		IExtractService.new(),
		ISettlementService.new(),
		IWarehouseService.new(),
		ITransactionService.new(),
		IRunSessionService.new(),
	]
	for iface: RefCounted in ifaces:
		check(iface != null)


## ---- 测试用 mock / 桩实现（不依赖真实 Autoload）----

## 假事件总线：记录发布的事件与载荷，支持断言
class _FakeEventBus:
	extends IEventBus
	var published: Array = []
	var _payloads: Dictionary = {}

	func publish(event_id: int, payload: RefCounted = null) -> void:
		published.append(event_id)
		if not _payloads.has(event_id):
			_payloads[event_id] = []
		_payloads[event_id].append(payload)

	func has_published(event_id: int) -> bool:
		return event_id in published

	func count_event(event_id: int) -> int:
		return _payloads.get(event_id, []).size()

	func last_payload(event_id: int) -> RefCounted:
		var arr: Array = _payloads.get(event_id, [])
		return arr[-1] if arr.size() > 0 else null


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