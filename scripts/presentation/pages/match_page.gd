## match_page.gd —— FullHaul 表现层：局内主页面
##
## 职责：
##   局内主页（WORD-26 + 切片 9 表现层接线）：
##   - 地图容器实体：对局场景内按本局容器计划生成可点击的容器（AC-17 核心
##     搜刮图形化：容器为可操作图形界面，不退化为纯文本清单），点击即搜索
##     该容器并把产出物品携带入背包格子（Loot 域 ContainerSearchService +
##     Item 域携带，切片 9「携带」闭环）
##   - 「搜索容器」按钮：搜索下一个未完成容器（与地图容器同一用例，便捷入口）
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
@onready var map_containers: GridContainer = $%MapContainers
@onready var search_button: Button = $%SearchButton
@onready var extract_button: Button = $%ExtractButton
@onready var extract_done_button: Button = $%ExtractDoneButton
@onready var timeout_button: Button = $%TimeoutButton

## 上帧所见阶段（阶段变化时刷新按钮/容器实体态：RUN_INIT -> IN_RUN_LOCKED
## 等转移不发布事件，事件驱动的刷新会错过启用时机，导致局内按钮全禁用）
var _last_seen_phase: int = -1


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


## 新一局开始：复位 HUD、重建地图容器与按钮态。
## 强制下一帧刷新按钮/容器实体态（RUN_INITIALIZED 时阶段尚为 RUN_INIT，
## 实体先按禁用构建；RUN_INIT -> IN_RUN_LOCKED 无事件，由 _process 轮询补刷，
## 复位 _last_seen_phase 保证入场后首帧必然刷新，不依赖中间阶段被轮询到）。
func reset_for_new_run() -> void:
	_last_seen_phase = -1
	hud.reset_for_new_run()
	_rebuild_map_containers()
	_refresh_buttons()


## [RUN_INITIALIZED] 进入新一局（多局复位，INV-14）。
func _on_run_initialized(_payload: RefCounted) -> void:
	reset_for_new_run()


## [EXTRACT_UNLOCKED] 撤离解锁：开放撤离按钮（INV-07）。
func _on_extract_unlocked(_payload: RefCounted) -> void:
	_refresh_buttons()


## 表现层计时循环：推进本局总计时与撤离读条（只经编排器用例，不直改领域状态）。
## 同时跟踪阶段变化：RUN_INIT -> IN_RUN_LOCKED 等转移不发布事件，靠每帧
## 轮询阶段差异补一次按钮/容器实体态刷新（否则局内按钮停留在禁用态）。
func _process(delta: float) -> void:
	if _orchestrator == null:
		return
	var phase := _orchestrator.current_phase()
	if phase != _last_seen_phase:
		_last_seen_phase = phase
		_refresh_buttons()
		_refresh_container_buttons()
	if phase == RunState.Phase.IN_RUN_LOCKED or phase == RunState.Phase.IN_RUN_EXTRACTABLE:
		_orchestrator.tick_match_time(delta)
		hud.set_match_time(_orchestrator.remaining_match_time())
		hud.set_carried(_orchestrator.carried_item_count())
	elif phase == RunState.Phase.EXTRACTING:
		var resolved := _orchestrator.tick_extraction(delta)
		hud.set_extract_progress(_orchestrator.remaining_extraction_time())
		if resolved:
			_refresh_buttons()


## 按钮回调：搜索容器（搜索下一个未完成容器，真实 Loot 域搜索 + 携带入背包）。
func _on_search_button_pressed() -> void:
	if _orchestrator == null:
		return
	_apply_search_result(_orchestrator.search_and_carry_container())


## 地图容器点击回调：搜索指定容器（AC-17 可操作容器实体）。
func _on_container_pressed(container_id: String) -> void:
	if _orchestrator == null:
		return
	_apply_search_result(_orchestrator.search_and_carry_container(container_id))


## 应用搜索结果：刷新 HUD 撤离目标/携带数、容器实体态与按钮态。
func _apply_search_result(result: Dictionary) -> void:
	if result.is_empty():
		return
	var count: int = result.get("completed_count", -1)
	if count < 0:
		return
	var required := _orchestrator.required_container_count()
	hud.set_objective(count, required, count >= required)
	hud.set_carried(_orchestrator.carried_item_count())
	_refresh_container_buttons()
	_refresh_buttons()


## 重建地图容器实体（数据驱动：编排器本局容器计划，AC-17）。
## 旧实体先脱离容器再延迟释放（queue_free 帧末才生效，同帧内仍会被
## get_children 读到，先 remove 保证重建后立即只有新实体）。
func _rebuild_map_containers() -> void:
	if map_containers == null or _orchestrator == null:
		return
	for child in map_containers.get_children():
		map_containers.remove_child(child)
		child.queue_free()
	for entry in _orchestrator.match_containers():
		var container_id := str(entry.get("container_id", ""))
		var display_name := str(entry.get("display_name", "容器"))
		var size_text := "%sx%s" % [entry.get("grid_width", 3), entry.get("grid_height", 3)]
		var button := Button.new()
		button.text = "%s %s\n点击搜索" % [display_name, size_text]
		button.custom_minimum_size = Vector2(0, 200)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.size_flags_vertical = Control.SIZE_EXPAND_FILL
		button.set_meta("container_id", container_id)
		button.set_meta("display_name", display_name)
		button.pressed.connect(func(): _on_container_pressed(container_id))
		map_containers.add_child(button)
	_refresh_container_buttons()


## 刷新地图容器实体态：已完成的容器标记并禁用；非局内阶段全部禁用。
func _refresh_container_buttons() -> void:
	if map_containers == null or _orchestrator == null:
		return
	var in_run := _orchestrator.current_phase() == RunState.Phase.IN_RUN_LOCKED \
		or _orchestrator.current_phase() == RunState.Phase.IN_RUN_EXTRACTABLE
	var search_service: IContainerSearchService = _orchestrator.container_search()
	for child in map_containers.get_children():
		var button := child as Button
		if button == null:
			continue
		var container_id := str(button.get_meta("container_id", ""))
		var display_name := str(button.get_meta("display_name", "容器"))
		var completed := search_service != null \
			and search_service.is_container_completed(container_id)
		if completed:
			button.text = "%s\n已搜索" % display_name
			button.disabled = true
		else:
			button.disabled = not in_run


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