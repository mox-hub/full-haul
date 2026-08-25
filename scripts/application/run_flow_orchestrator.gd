## run_flow_orchestrator.gd —— FullHaul 应用编排层：一局流程编排器
##
## 职责：
##   承载 V0.1 玩法验证闭环的用例编排（架构 §3 应用编排层、§6 切片 9 的
##   表现层接线前置）：持有顶层状态机，向表现层暴露「用例级」入口，
##   并通过事件总线广播领域事件驱动界面切换。
##
## 分层约定（架构 §3，WORD-26）：
##   - 表现层（页面/按钮）只调用本编排器的用例方法，不直接触碰领域层
##     状态机与 RunState（禁止表现层直改领域状态）。
##   - 本编排器只依赖领域层接口（IEventBus/IRunStateStore/IConfigLoader）
##     与 TopLevelStateMachine 的公开转移入口。
##
## V0.1 占位说明：
##   - 「完成容器」「撤离读条完成」「总时间耗尽」在 V0.1 由占位用例直接
##     触发转移；真实的逐件揭晓计时与双计时并行推进分别由 Loot/Extract
##     域切片（架构 §7 切片 6/7）接入。同刻计时优先级为规范 TBD-04，
##     依赖处停工提问，本层不私自补默认值。
##   - Loadout 域（购买/选择/扣款，切片 3）未接入：确认入场即以占位
##     配置直接初始化对局。

extends RefCounted
class_name RunFlowOrchestrator

## 注入的事件总线（驱动界面切换的唯一通道）
var _bus: IEventBus = null
## 注入的局内状态存储
var _store: IRunStateStore = null
## 注入的配置加载器（单一来源 INV-16）
var _config_loader: IConfigLoader = null
## 顶层状态机（领域层，编排器内部持有）
var _sm: TopLevelStateMachine = null

## 运行序号（生成 runId，保证一局一 id，INV-14 多局隔离）
var _run_seq := 0


func _init(bus: IEventBus, state_store: IRunStateStore, config_loader: IConfigLoader) -> void:
	_bus = bus
	_store = state_store
	_config_loader = config_loader
	_sm = TopLevelStateMachine.new(bus, state_store, config_loader)


## 启动：BOOT -> OUT_OF_RUN（主场景引导完成后调用一次）。
func start() -> void:
	_sm.boot()
	_sm.on_boot_ok()


## ---- 局外 / 入场装载 ----

## 用例：请求开始一局（OUT_OF_RUN -> LOADOUT）。
func request_start_match() -> void:
	_sm.on_start_match_requested()


## 用例：确认入场装载（LOADOUT -> RUN_INIT -> IN_RUN_LOCKED）。
## V0.1 无购买/扣款（切片 3 未接入），以占位方式直接初始化对局。
func confirm_loadout() -> void:
	_run_seq += 1
	_sm.on_loadout_confirmed("run-%04d" % _run_seq)
	## V0.1 对局初始化为同步完成（无异步加载），立即进入局内锁定态
	_sm.on_run_init_ok()


## 用例：取消入场装载（LOADOUT -> OUT_OF_RUN）。
func cancel_loadout() -> void:
	_sm.on_loadout_cancelled()


## ---- 局内（探索搜集 / 撤离）----

## 用例（占位）：完成一个必搜容器（IN_RUN_* 内有效）。
## 返回完成后累计的完成容器数（供 HUD 展示）；局外调用返回 -1。
func complete_container_placeholder() -> int:
	var state: RunState = _store.read()
	if state == null:
		return -1
	if state.phase != RunState.Phase.IN_RUN_LOCKED and state.phase != RunState.Phase.IN_RUN_EXTRACTABLE:
		return -1
	_sm.on_container_completed()
	return _store.read().completed_container_count


## 用例：开始撤离读条（IN_RUN_EXTRACTABLE -> EXTRACTING）。
func start_extraction() -> void:
	_sm.on_extract_started()


## 用例（占位）：撤离读条完成（EXTRACTING -> RUN_SUCCEEDED）。
## 真实读条计时由 Extract 域切片 7 接入（TBD-04 同刻优先级停工红线）。
func complete_extraction_placeholder() -> void:
	_sm.on_extraction_complete()


## 用例（占位）：本局总时间耗尽（IN_RUN_* / EXTRACTING -> RUN_FAILED）。
func timeout_placeholder() -> void:
	_sm.on_timeout()


## ---- 结算 ----

## 用例：完成结算（RUN_SUCCEEDED/RUN_FAILED -> SETTLED，幂等 INV-09）。
func settle() -> void:
	_sm.on_settled()


## 用例：确认结算并返回局外（SETTLED -> OUT_OF_RUN）。
func confirm_settled() -> void:
	_sm.on_settled_confirmed()


## ---- 只读查询（供表现层展示，经接口/状态机公开入口读取）----

## 当前阶段。
func current_phase() -> RunState.Phase:
	return _sm.current_phase()


## 撤离解锁所需完成容器数（配置单一来源 INV-16）。
func required_container_count() -> int:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			return cfg.required_completed_containers
	return 5


## 当前完成容器数。
func completed_container_count() -> int:
	var state: RunState = _store.read()
	return state.completed_container_count if state != null else 0
