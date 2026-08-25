## match_page.gd —— FullHaul 表现层：局内主页面（占位 V0）
##
## 职责：
##   局内主页骨架（WORD-26 交付项 3）：承载 HUD 与局内交互按钮，
##   支撑搜打撤核心循环的玩法验证：
##     - 「搜索容器（占位）」：推进必搜容器完成数（探索搜集环节占位）
##     - 「开始撤离」：撤离解锁后可点（INV-07/08）
##     - 「撤离读条完成（占位）/ 本局时间耗尽（占位）」：触发结算分支
##
## 分层约定：
##   按钮只调用应用编排层用例（RunFlowOrchestrator）；界面状态由
##   事件总线事件（RUN_INITIALIZED / EXTRACT_UNLOCKED）与编排器只读
##   查询驱动刷新，本页面不写任何领域状态。
##
## 占位说明：
##   任务描述中的「战斗」环节为 V0.1 规范外未来方向（架构审核 P0-1/P0-2，
##   战斗/生命事件已从领域事件中删除），本页不含战斗交互。

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


## 按钮回调：搜索容器（占位）—— 探索搜集环节占位入口。
func _on_search_button_pressed() -> void:
	if _orchestrator == null:
		return
	var count := _orchestrator.complete_container_placeholder()
	if count < 0:
		return
	var required := _orchestrator.required_container_count()
	hud.set_objective(count, required, count >= required)
	_refresh_buttons()


## 按钮回调：开始撤离（IN_RUN_EXTRACTABLE -> EXTRACTING）。
func _on_extract_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.start_extraction()
	_refresh_buttons()


## 按钮回调：撤离读条完成（占位）—— 成功结算分支入口。
func _on_extract_done_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.complete_extraction_placeholder()
	_refresh_buttons()


## 按钮回调：本局时间耗尽（占位）—— 失败结算分支入口。
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
