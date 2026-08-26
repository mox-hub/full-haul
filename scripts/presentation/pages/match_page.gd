## match_page.gd —— FullHaul 表现层：局内主页面
##
## 职责：
##   局内主页（WORD-26 + 切片 9 表现层接线）：
##   - 「搜索容器」：真实容器搜索 + 把产出物品携带入背包格子（Loot 域
##     ContainerSearchService + Item 域携带，切片 9「携带」闭环）
##   - 「开始撤离」：撤离解锁后可点（INV-07/08），撤离读条由表现层计时
##     循环推进（tick_extraction，切片 7）
##   - 本局总计时由表现层 _process 推进（tick_match_time，切片 4）
##   - 保留「撤离读条完成（占位）/ 本局时间耗尽（占位）」调试入口，
##     供验证/测试直达结算分支（真实计时已接入，二者并存）
##
## 分层约定：
##   按钮只调用应用编排层用例（RunFlowOrchestrator）；界面状态由事件总线
##   事件与编排器只读查询驱动刷新，本页面不写任何领域状态。

extends Control
class_name MatchPage

## 事件总线（组合根注入）
var _bus: IEventBus = null
## 应用编排层（组合根注入）
var _orchestrator: RunFlowOrchestrator = null

@onready var hud: MatchHud = $%Hud
@onready var search_button: Button = $%SearchButton
@onready var extract_button: Button = $%ExtractButton
@onready var extract_done_button: Button = $%ExtractDoneButton
@onready var timeout_button: Button = $%TimeoutButton


func _ready() -> void:
	search_button.pressed.connect(_on_search_button_pressed)
	extract_button.pressed.connect(_on_extract_button_pressed)
	extract_done_button.pressed.connect(_on_extract_done_button_pressed)
	timeout_button.pressed.connect(_on_timeout_button_pressed)


## 组合根（main.gd）注入依赖、订阅事件并初始化展示。
func setup(bus: IEventBus, orchestrator: RunFlowOrchestrator) -> void:
	_bus = bus
	_orchestrator = orchestrator
	hud.setup(bus, orchestrator)
	_bus.subscribe(DomainEvents.Events.RUN_INITIALIZED, _on_run_initialized)
	_bus.subscribe(DomainEvents.Events.EXTRACT_UNLOCKED, _on_extract_unlocked)
	reset_for_new_run()


## 新一局开始：复位 HUD 与按钮态。
func reset_for_new_run() -> void:
	hud.reset_for_new_run()
	_refresh_buttons()


## [RUN_INITIALIZED] 进入新一局（多局复位，INV-14）。
func _on_run_initialized(_payload: RefCounted) -> void:
	reset_for_new_run()


## [EXTRACT_UNLOCKED] 撤离解锁：开放撤离按钮（INV-07）。
func _on_extract_unlocked(_payload: RefCounted) -> void:
	_refresh_buttons()


## 表现层计时循环：推进本局总计时与撤离读条（只经编排器用例，不直改领域状态）。
func _process(delta: float) -> void:
	if _orchestrator == null:
		return
	var phase := _orchestrator.current_phase()
	if phase == RunState.Phase.IN_RUN_LOCKED or phase == RunState.Phase.IN_RUN_EXTRACTABLE:
		_orchestrator.tick_match_time(delta)
		hud.set_match_time(_orchestrator.remaining_match_time())
		hud.set_carried(_orchestrator.carried_item_count())
	elif phase == RunState.Phase.EXTRACTING:
		var resolved := _orchestrator.tick_extraction(delta)
		hud.set_extract_progress(_orchestrator.remaining_extraction_time())
		if resolved:
			_refresh_buttons()


## 按钮回调：搜索容器（真实 Loot 域搜索 + 携带入背包）。
func _on_search_button_pressed() -> void:
	if _orchestrator == null:
		return
	var result := _orchestrator.search_and_carry_container()
	if result.is_empty():
		return
	var count: int = result.get("completed_count", -1)
	if count < 0:
		return
	var required := _orchestrator.required_container_count()
	hud.set_objective(count, required, count >= required)
	hud.set_carried(_orchestrator.carried_item_count())
	_refresh_buttons()


## 按钮回调：开始撤离（IN_RUN_EXTRACTABLE -> EXTRACTING）。
func _on_extract_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.start_extraction()
	_refresh_buttons()


## 按钮回调：撤离读条完成（调试入口，直达成功结算分支）。
func _on_extract_done_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.complete_extraction_placeholder()
	_refresh_buttons()


## 按钮回调：本局时间耗尽（调试入口，直达失败结算分支）。
func _on_timeout_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.timeout_placeholder()
	_refresh_buttons()


## 依据当前阶段（编排器只读查询）刷新按钮可用态。
func _refresh_buttons() -> void:
	if _orchestrator == null:
		return
	match _orchestrator.current_phase():
		RunState.Phase.IN_RUN_LOCKED:
			search_button.disabled = false
			extract_button.disabled = true
			extract_done_button.disabled = true
			timeout_button.disabled = false
		RunState.Phase.IN_RUN_EXTRACTABLE:
			search_button.disabled = false
			extract_button.disabled = false
			extract_done_button.disabled = true
			timeout_button.disabled = false
		RunState.Phase.EXTRACTING:
			search_button.disabled = true
			extract_button.disabled = true
			extract_done_button.disabled = false
			timeout_button.disabled = false
		_:
			search_button.disabled = true
			extract_button.disabled = true
			extract_done_button.disabled = true
			timeout_button.disabled = true