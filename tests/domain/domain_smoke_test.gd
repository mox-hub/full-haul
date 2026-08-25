## domain_smoke_test.gd —— FullHaul 领域层冒烟测试（基础框架验证）
##
## 职责：
##   对领域层的纯逻辑（顶层状态机、RunState 幂等）做基础验证，保证基础框架
##   搭建后可运行、可自检。本脚本可在 Godot 引擎中直接运行：
##
##   godot --headless --script res://tests/domain/domain_smoke_test.gd
##
## 说明：
##   本脚本为「基础框架地基」的冒烟自检（对应架构 §8 测试策略）。
##   后续各域切片将按 AC/INV 映射补充 GUT/GdUnit 正式用例（WORD-25）。

extends SceneTree

## 退出码约定：0=通过，1=失败
var _fail_count := 0
var _pass_count := 0


func _initialize() -> void:
	print("== FullHaul 领域层冒烟测试开始 ==")
	_test_run_state_settled_idempotent()
	_test_top_level_state_machine_flow()
	_test_top_level_state_machine_invalid_transition()

	print("== 冒烟测试结束：%d 通过，%d 失败 ==" % [_pass_count, _fail_count])
	if _fail_count > 0:
		quit(1)
	else:
		quit(0)


## 断言辅助
func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass_count += 1
		print("  [PASS] %s" % msg)
	else:
		_fail_count += 1
		print("  [FAIL] %s" % msg)


## RunState 结算幂等（INV-09）
func _test_run_state_settled_idempotent() -> void:
	print("[测试] RunState 结算幂等 INV-09")
	var state := RunState.new("run-1", 180, 15)
	var first := state.mark_settled()
	_assert(first == true, "首次 mark_settled 返回 true")
	var second := state.mark_settled()
	_assert(second == false, "重复 mark_settled 返回 false（幂等忽略）")
	_assert(state.settled == true, "settled 标记已置位")


## 顶层状态机合法流转
func _test_top_level_state_machine_flow() -> void:
	print("[测试] 顶层状态机合法流转")
	## 用测试 mock 注入
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var loader := _FakeConfigLoader.new()

	var sm := TopLevelStateMachine.new(bus, store, loader)
	sm.boot()
	_assert(sm.current_phase() == RunState.Phase.BOOT, "初始阶段为 BOOT")

	sm.on_boot_ok()
	_assert(sm.current_phase() == RunState.Phase.OUT_OF_RUN, "boot_ok 后进入 OUT_OF_RUN")

	sm.on_start_match_requested()
	_assert(sm.current_phase() == RunState.Phase.LOADOUT, "start 后进入 LOADOUT")

	sm.on_loadout_confirmed("run-2")
	_assert(sm.current_phase() == RunState.Phase.RUN_INIT, "确认装载后进入 RUN_INIT")

	sm.on_run_init_ok()
	_assert(sm.current_phase() == RunState.Phase.IN_RUN_LOCKED, "初始化成功后进入 IN_RUN_LOCKED")

	sm.on_required_containers_completed()
	_assert(sm.current_phase() == RunState.Phase.IN_RUN_EXTRACTABLE, "完成容器后进入 IN_RUN_EXTRACTABLE")

	sm.on_extract_started()
	_assert(sm.current_phase() == RunState.Phase.EXTRACTING, "开始撤离进入 EXTRACTING")

	sm.on_extraction_complete()
	_assert(sm.current_phase() == RunState.Phase.RUN_SUCCEEDED, "撤离读条完成进入 RUN_SUCCEEDED")

	sm.on_settled()
	_assert(sm.current_phase() == RunState.Phase.SETTLED, "结算后进入 SETTLED")

	sm.on_settled_confirmed()
	_assert(sm.current_phase() == RunState.Phase.OUT_OF_RUN, "确认后回到 OUT_OF_RUN")


## 顶层状态机非法转移应被忽略
func _test_top_level_state_machine_invalid_transition() -> void:
	print("[测试] 顶层状态机非法转移拦截")
	var bus := _FakeEventBus.new()
	var store := _InMemoryStateStore.new()
	var loader := _FakeConfigLoader.new()

	var sm := TopLevelStateMachine.new(bus, store, loader)
	sm.boot()
	sm.on_boot_ok()  # -> OUT_OF_RUN

	## 从 OUT_OF_RUN 直接跳到 EXTRACTING 应被拒绝
	sm.on_extract_started()
	_assert(sm.current_phase() == RunState.Phase.OUT_OF_RUN, "OUT_OF_RUN 不可直接进入 EXTRACTING")


## ---- 测试用 mock / 桩实现（不依赖真实 Autoload）----

## 假事件总线：记录发布的事件
class _FakeEventBus:
	extends IEventBus
	var published: Array = []

	func publish(event_id: int, payload: RefCounted = null) -> void:
		published.append(event_id)


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