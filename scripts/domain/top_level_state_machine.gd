## top_level_state_machine.gd —— FullHaul 顶层状态机（领域层，纯逻辑）
##
## 职责：
##   实现架构文档 §2.1 的顶层状态机，驱动一局从 BOOT 到 SETTLED 的完整
##   生命周期流转（规范 4.2）。
##
## 流转关系（对应架构 §2.1）：
##   BOOT -> OUT_OF_RUN -> LOADOUT -> RUN_INIT -> IN_RUN_LOCKED
##        -> IN_RUN_EXTRACTABLE -> EXTRACTING -> RUN_SUCCEEDED/RUN_FAILED
##        -> SETTLED -> OUT_OF_RUN
##   BOOT -> ERROR（加载失败）
##
## 设计要点：
##   1. 纯逻辑：不依赖任何 Godot 节点，可独立单元测试（架构原则 2）。
##   2. 通过事件总线发布领域事件；通过 IRunStateStore 读写 RunState。
##   3. 依赖注入：构造时注入 IEventBus、IRunStateStore、IConfigLoader，
##      便于测试替换 mock。
##
## 说明：本文件为 V0.1 基础框架骨架，提供状态机的主体结构与合法转移表；
## 各业务域（Loadout/Loot/Extract/Settlement）的细化逻辑由对应域在后续
## 切片中接入。

extends RefCounted
class_name TopLevelStateMachine

## 注入的事件总线
var _bus: IEventBus = null
## 注入的局内状态存储
var _state_store: IRunStateStore = null
## 注入的配置加载器
var _config_loader: IConfigLoader = null

## 注入的领域服务（域拆分，架构 §1.1）：各域拥有自己的转移/计数逻辑。
## 均为可选注入（默认 null）；未注入时回退到骨架自带的简易行为，保证
## 既有测试与最小切片可独立运行。后续切片注入具体实现后，转移逻辑交由
## 对应域服务托管（架构 §3 接口原则）。
var _loadout_service: ILoadoutService = null
var _run_session_service: IRunSessionService = null
var _container_search_service: IContainerSearchService = null
var _extract_service: IExtractService = null
var _settlement_service: ISettlementService = null

## 当前 RunState（便于状态机内部直接操作）
var _state: RunState = null


func _init(bus: IEventBus, state_store: IRunStateStore, config_loader: IConfigLoader,
		loadout_service: ILoadoutService = null,
		run_session_service: IRunSessionService = null,
		container_search_service: IContainerSearchService = null,
		extract_service: IExtractService = null,
		settlement_service: ISettlementService = null) -> void:
	_bus = bus
	_state_store = state_store
	_config_loader = config_loader
	_loadout_service = loadout_service
	_run_session_service = run_session_service
	_container_search_service = container_search_service
	_extract_service = extract_service
	_settlement_service = settlement_service


## 初始化状态机到 BOOT 阶段。
func boot() -> void:
	_state = _state_store.read()
	if _state == null:
		_state = RunState.new("", 0, 0)
		_state.set_phase(RunState.Phase.BOOT)
		_state_store.write(_state)


## 启动加载完成 -> 进入局外状态。
func on_boot_ok() -> void:
	_transition(RunState.Phase.OUT_OF_RUN)
	_bus.publish(DomainEvents.Events.OUT_OF_RUN_ENTERED, DomainEvents.OutOfRunEntered.new())


## 启动加载失败 -> 进入错误态。
func on_boot_error() -> void:
	_transition(RunState.Phase.ERROR)


## 局外选择开始 -> 进入 LOADOUT。
func on_start_match_requested() -> void:
	if not _can_transition(RunState.Phase.LOADOUT):
		return
	_transition(RunState.Phase.LOADOUT)
	_bus.publish(DomainEvents.Events.START_MATCH_REQUESTED, DomainEvents.StartMatchRequested.new())


## LOADOUT 取消 -> 返回局外。
## WORD-26：进入局外同样广播 OUT_OF_RUN_ENTERED，保证表现层对
## 「每次进入局外」都有事件可订阅（界面切换由事件驱动）。
func on_loadout_cancelled() -> void:
	_transition(RunState.Phase.OUT_OF_RUN)
	_bus.publish(DomainEvents.Events.OUT_OF_RUN_ENTERED, DomainEvents.OutOfRunEntered.new())


## LOADOUT 确认并扣款成功 -> 初始化对局。
## 域拆分：当注入 ILoadoutService 时，背包校验/扣款/绑定交由 Loadout 域处理；
## 未注入时回退到骨架自带的行为（直接创建本局 RunState）。
## 切片 4：当注入 IRunSessionService 时，对局初始化（RUN_INIT 会话状态：runId、
## 双计时、完成数=0、撤离锁定、settled=false，AC-03）交由 RunSession 域创建。
func on_loadout_confirmed(run_id: String) -> void:
	_transition(RunState.Phase.RUN_INIT)
	if _run_session_service != null:
		_state = _run_session_service.create_run(run_id, _match_duration(), _extraction_duration())
		return
	var cfg := _config_loader.get_config()
	var match_duration := cfg.match_duration if cfg != null else 180
	var extraction_duration := cfg.extraction_duration if cfg != null else 15
	_state = RunState.new(run_id, match_duration, extraction_duration)
	_state.set_phase(RunState.Phase.RUN_INIT)
	_state_store.write(_state)
	_bus.publish(DomainEvents.Events.RUN_INITIALIZED, DomainEvents.RunInitialized.new(
		run_id, match_duration, 0, true, false))


## 对局初始化成功 -> 进入局内锁定态（完成数<5）。
func on_run_init_ok() -> void:
	_transition(RunState.Phase.IN_RUN_LOCKED)


## 容器完成数达到阈值 -> 撤离解锁（INV-07）。
## 域拆分：当注入 IContainerSearchService 时，以容器搜索域统计的完成数为准；
## 未注入时回退到骨架自带行为（直接把当前计数写入并转移）。
func on_required_containers_completed() -> void:
	if _state == null:
		return
	if _container_search_service != null:
		_state.completed_container_count = _container_search_service.completed_container_count()
		_state_store.write(_state)
	_transition(RunState.Phase.IN_RUN_EXTRACTABLE)
	_bus.publish(DomainEvents.Events.EXTRACT_UNLOCKED, DomainEvents.ExtractUnlocked.new(
		_state.completed_container_count))


## 记录完成一个容器（Loot/Container 域上报，INV-06），并在达到阈值时撤离解锁
## （INV-07）。域拆分：完成数由容器搜索域/调用方上报，顶层状态机只做阈值判定；
## 切片 4：注入 IRunSessionService 时，完成数计数交由 RunSession 域维护（INV-06/07）。
func on_container_completed() -> void:
	if _state == null:
		return
	if _run_session_service != null:
		_run_session_service.on_container_completed(_state)
	else:
		_state.completed_container_count += 1
	_state_store.write(_state)
	var required := _required_completed_containers()
	if _state.completed_container_count >= required and _can_transition(RunState.Phase.IN_RUN_EXTRACTABLE):
		_transition(RunState.Phase.IN_RUN_EXTRACTABLE)
		_bus.publish(DomainEvents.Events.EXTRACT_UNLOCKED, DomainEvents.ExtractUnlocked.new(
			_state.completed_container_count))


## 推进本局全局计时（总时间）。总时间归零 -> RUN_FAILED（INV-07/08）。
## 域拆分：注入 IRunSessionService 时由 RunSession 域推进双计时之一；
## 返回是否发生本次全局计时耗尽（已转移至 RUN_FAILED）。
func tick_match_time(delta_seconds: float) -> bool:
	if _state == null:
		return false
	if _run_session_service == null:
		return false
	if _run_session_service.tick_match_time(delta_seconds):
		on_timeout()
		return true
	return false


## 撤离解锁所需完成容器数（读取配置单一来源 INV-16）。
func _required_completed_containers() -> int:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			return cfg.required_completed_containers
	return 5


## 一局总时长（读取配置单一来源 INV-16；未加载时回退默认 180）。
func _match_duration() -> int:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			return cfg.match_duration
	return 180


## 撤离读条时长（读取配置单一来源 INV-16；未加载时回退默认 15）。
func _extraction_duration() -> int:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			return cfg.extraction_duration
	return 15


## 开始撤离 -> EXTRACTING（INV-08）。
## 域拆分：当注入 IExtractService 时，由撤离域推进读条/判定；
## 未注入时回退到骨架自带行为。
func on_extract_started() -> void:
	if not _can_transition(RunState.Phase.EXTRACTING):
		return
	_transition(RunState.Phase.EXTRACTING)
	_bus.publish(DomainEvents.Events.EXTRACT_STARTED, DomainEvents.ExtractStarted.new(
		_state.remaining_extraction_time))


## 推进撤离读条与总计时（域拆分：委托 IExtractService）。
## 返回撤离是否已完成（读条先归零 -> RUN_SUCCEEDED；总时间先归零 -> RUN_FAILED）。
func tick_extraction(delta_seconds: float) -> bool:
	if _state == null:
		return false
	if _extract_service != null:
		if _extract_service.tick(_state, delta_seconds):
			if _extract_service.is_success(_state):
				on_extraction_complete()
			else:
				on_timeout()
			return true
		return false
	## 骨架回退：无撤离服务时不推进，直接返回未完成
	return false


## 撤离读条完成 -> 成功结算。
func on_extraction_complete() -> void:
	_transition(RunState.Phase.RUN_SUCCEEDED)
	_bus.publish(DomainEvents.Events.RUN_SUCCEEDED, DomainEvents.RunSucceeded.new(
		_state.run_id, _state.carried_item_ids))


## 总时间归零 -> 失败结算。
func on_timeout() -> void:
	_transition(RunState.Phase.RUN_FAILED)
	_bus.publish(DomainEvents.Events.RUN_FAILED, DomainEvents.RunFailed.new(
		_state.run_id, _state.safe_item_ids))


## 结算完成（幂等）-> SETTLED（INV-09）。
func on_settled() -> void:
	if _state != null:
		if not _state.mark_settled():
			## 重复结算：幂等忽略，直接返回
			return
	_transition(RunState.Phase.SETTLED)
	_bus.publish(DomainEvents.Events.RUN_SETTLED, DomainEvents.RunSettled.new(
		_state.run_id if _state != null else ""))


## SETTLED 确认 -> 回到局外，开启下一局。
## WORD-26：进入局外同样广播 OUT_OF_RUN_ENTERED（同 on_loadout_cancelled）。
func on_settled_confirmed() -> void:
	_transition(RunState.Phase.OUT_OF_RUN)
	_bus.publish(DomainEvents.Events.OUT_OF_RUN_ENTERED, DomainEvents.OutOfRunEntered.new())


## 是否允许从当前阶段转移到目标阶段（合法转移表）。
func _can_transition(target: RunState.Phase) -> bool:
	if _state == null:
		return true
	match _state.phase:
		RunState.Phase.BOOT:
			return target in [RunState.Phase.OUT_OF_RUN, RunState.Phase.ERROR]
		RunState.Phase.OUT_OF_RUN:
			return target in [RunState.Phase.LOADOUT]
		RunState.Phase.LOADOUT:
			return target in [RunState.Phase.RUN_INIT, RunState.Phase.OUT_OF_RUN]
		RunState.Phase.RUN_INIT:
			return target in [RunState.Phase.IN_RUN_LOCKED]
		RunState.Phase.IN_RUN_LOCKED:
			return target in [RunState.Phase.IN_RUN_EXTRACTABLE, RunState.Phase.RUN_FAILED]
		RunState.Phase.IN_RUN_EXTRACTABLE:
			return target in [RunState.Phase.EXTRACTING, RunState.Phase.RUN_FAILED]
		RunState.Phase.EXTRACTING:
			return target in [RunState.Phase.RUN_SUCCEEDED, RunState.Phase.RUN_FAILED]
		RunState.Phase.RUN_SUCCEEDED, RunState.Phase.RUN_FAILED:
			return target == RunState.Phase.SETTLED
		RunState.Phase.SETTLED:
			return target == RunState.Phase.OUT_OF_RUN
		_:
			return false


## 执行状态转移（校验合法性后写入状态）。
func _transition(target: RunState.Phase) -> void:
	if not _can_transition(target):
		return
	_state.set_phase(target)
	_state_store.write(_state)


## 当前阶段（用于外部读取/测试断言）。
func current_phase() -> RunState.Phase:
	if _state == null:
		return RunState.Phase.BOOT
	return _state.phase
