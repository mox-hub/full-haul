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
## 注入的仓储集合（WORD-31 数据层接线；null 表示不接线，回退纯内存运行）
var _repos: RepositorySet = null
## 顶层状态机（领域层，编排器内部持有）
var _sm: TopLevelStateMachine = null

## 运行序号（生成 runId，保证一局一 id，INV-14 多局隔离）
var _run_seq := 0

## 局开始加载的配置数据（IConfigDataRepository 读取；供表现层只读查询）
var _loaded_config_data: Dictionary = {}

## 本局终局结果（RUN_SUCCEEDED/RUN_FAILED 转移时记录；结算时 SETTLED 已覆盖
## 阶段信息，故在此留存成败，供存档写入）
var _last_run_outcome := ""


func _init(bus: IEventBus, state_store: IRunStateStore, config_loader: IConfigLoader,
		repositories: RepositorySet = null) -> void:
	_bus = bus
	_store = state_store
	_config_loader = config_loader
	_repos = repositories
	_sm = TopLevelStateMachine.new(bus, state_store, config_loader)


## 启动：BOOT -> OUT_OF_RUN（主场景引导完成后调用一次）。
## WORD-31：接入数据层后，开局加载配置数据（IConfigDataRepository）。
func start() -> void:
	_sm.boot()
	_sm.on_boot_ok()
	_load_config_data()


## ---- 局外 / 入场装载 ----

## 用例：请求开始一局（OUT_OF_RUN -> LOADOUT）。
func request_start_match() -> void:
	_sm.on_start_match_requested()


## 用例：确认入场装载（LOADOUT -> RUN_INIT -> IN_RUN_LOCKED）。
## V0.1 无购买/扣款（切片 3 未接入），以占位方式直接初始化对局。
## WORD-31：对局初始化后写入运行时快照（IRunSnapshotRepository）。
func confirm_loadout() -> void:
	_run_seq += 1
	_sm.on_loadout_confirmed("run-%04d" % _run_seq)
	## V0.1 对局初始化为同步完成（无异步加载），立即进入局内锁定态
	_sm.on_run_init_ok()
	_persist_run_snapshot()


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
	_persist_run_snapshot()
	return _store.read().completed_container_count


## 用例：开始撤离读条（IN_RUN_EXTRACTABLE -> EXTRACTING）。
func start_extraction() -> void:
	_sm.on_extract_started()
	_persist_run_snapshot()


## 用例（占位）：撤离读条完成（EXTRACTING -> RUN_SUCCEEDED）。
## 真实读条计时由 Extract 域切片 7 接入（TBD-04 同刻优先级停工红线）。
func complete_extraction_placeholder() -> void:
	_sm.on_extraction_complete()
	_last_run_outcome = "success"
	_persist_run_snapshot()


## 用例（占位）：本局总时间耗尽（IN_RUN_* / EXTRACTING -> RUN_FAILED）。
func timeout_placeholder() -> void:
	_sm.on_timeout()
	_last_run_outcome = "failure"
	_persist_run_snapshot()


## ---- 结算 ----

## 用例：完成结算（RUN_SUCCEEDED/RUN_FAILED -> SETTLED，幂等 INV-09）。
## WORD-31：结算后写入存档（IRunResultRepository 结算记录 + IProfileRepository
## 局外账户），数据变更仍由既有领域事件（RUN_SETTLED 等）经总线广播。
func settle() -> void:
	_sm.on_settled()
	_persist_settlement()


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


## 局开始加载的配置数据（WORD-31；供表现层只读查询）。
## 未接线数据层或加载失败时返回空 Dictionary。
func loaded_config_data() -> Dictionary:
	return _loaded_config_data


## ---- WORD-31 数据层接线辅助（应用层编排侧，领域/表现层不感知）----

## 开局加载配置数据（道具/藏品、容器/撤离点、背包档位、产出权重）。
func _load_config_data() -> void:
	if _repos == null or _repos.config_data == null:
		return
	_loaded_config_data = {
		"item_definitions": _repos.config_data.load_item_definitions(),
		"container_types": _repos.config_data.load_container_types(),
		"backpack_offers": _repos.config_data.load_backpack_offers(),
		"container_tier_weights": _repos.config_data.load_container_tier_weights(),
	}


## 局内状态变更后写运行时快照（IRunSnapshotRepository，可选）。
func _persist_run_snapshot() -> void:
	if _repos == null or _repos.run_snapshot == null:
		return
	var state: RunState = _store.read()
	if state != null:
		_repos.run_snapshot.upsert_run_snapshot(state)


## 结算后写入存档：结算记录（幂等 run_id 唯一，INV-09）+ 局外账户落库。
## 撤离成功携带物品入仓库（INV-10）；撤离失败安全箱物品入仓库（INV-11）。
func _persist_settlement() -> void:
	if _repos == null:
		return
	var state: RunState = _store.read()
	if state == null:
		return
	if _repos.run_result != null:
		var profile := _load_profile()
		var currency_before := profile.currency if profile != null else 0
		var outcome := _last_run_outcome if _last_run_outcome != "" else \
			("success" if state.phase == RunState.Phase.RUN_SUCCEEDED else "failure")
		_repos.run_result.insert_settlement({
			"record_id": "settle-%s" % state.run_id,
			"run_id": state.run_id,
			"profile_id": "local",
			"result": outcome,
			"currency_before": currency_before,
			"currency_after": currency_before,
			"carried_item_ids": state.carried_item_ids,
			"safe_item_ids": state.safe_item_ids,
		})
	if _repos.profile != null:
		var profile := _load_profile()
		if profile != null:
			var is_success := _last_run_outcome == "success" \
				or (_last_run_outcome == "" and state.phase == RunState.Phase.RUN_SUCCEEDED)
			var returned_ids: Array = state.carried_item_ids if is_success else state.safe_item_ids
			for instance_id in returned_ids:
				if not profile.warehouse_item_ids.has(instance_id):
					profile.warehouse_item_ids.append(instance_id)
			_repos.profile.save(profile)


## 读取局外账户（加载失败时回退默认账户）。
func _load_profile() -> PlayerProfile:
	if _repos == null or _repos.profile == null:
		return null
	return _repos.profile.load()
