## hud.gd —— FullHaul 表现层：局内 HUD（占位 V0）
##
## 职责：
##   局内主页面顶部的状态展示（WORD-26 交付项 2）：
##     1. 玩家状态占位（生命条——战斗/生命域为未来方向，仅占位）
##     2. 携带物品/背包占位展示（格子视图由切片 5/6 接入）
##     3. 撤离目标提示（完成容器数 x/N，锁定/解锁态）
##     4. 撤离读条（EXTRACT_STARTED 后的纯视觉动画，不承载判定）
##     5. 本局时长提示（RUN_INITIALIZED 事件数据，计时由切片 7 接入）
##
## 数据来源：
##   全部经事件总线（EXTRACT_UNLOCKED / EXTRACT_STARTED / RUN_INITIALIZED）
##   或应用编排层只读查询注入；HUD 不写任何领域状态。

extends Control
class_name MatchHud

## 事件总线（组合根注入，用于订阅领域事件）
var _bus: IEventBus = null
## 应用编排层（组合根注入，只读查询用）
var _orchestrator: RunFlowOrchestrator = null

## 撤离读条的视觉动画
var _bar_tween: Tween = null

@onready var objective_label: Label = $%ObjectiveLabel
@onready var match_time_label: Label = $%MatchTimeLabel
@onready var backpack_label: Label = $%BackpackLabel
@onready var extract_bar: ProgressBar = $%ExtractBar
@onready var extract_bar_label: Label = $%ExtractBarLabel


## 组合根（main.gd）注入依赖并订阅事件。
func setup(bus: IEventBus, orchestrator: RunFlowOrchestrator) -> void:
	_bus = bus
	_orchestrator = orchestrator
	_bus.subscribe(DomainEvents.Events.RUN_INITIALIZED, _on_run_initialized)
	_bus.subscribe(DomainEvents.Events.EXTRACT_UNLOCKED, _on_extract_unlocked)
	_bus.subscribe(DomainEvents.Events.EXTRACT_STARTED, _on_extract_started)


## 展示撤离目标（完成容器数 / 解锁状态）。
func set_objective(current: int, required: int, unlocked: bool) -> void:
	if unlocked:
		objective_label.text = "撤离目标：完成容器 %d/%d —— 撤离已解锁 ✓" % [current, required]
	else:
		objective_label.text = "撤离目标：完成容器 %d/%d（锁定）" % [current, required]


## 新一局开始时复位 HUD。
## 本局时长不在此复位：它只由 RUN_INITIALIZED 事件数据写入（订阅顺序
## 无关，避免复位覆盖事件更新）。
func reset_for_new_run() -> void:
	var required := 5
	if _orchestrator != null:
		required = _orchestrator.required_container_count()
	set_objective(0, required, false)
	backpack_label.text = "背包（占位）：携带物品 0 件 —— 格子视图由切片 5/6 接入"
	extract_bar.visible = false
	extract_bar_label.visible = false
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
		_bar_tween = null


## [RUN_INITIALIZED] 展示本局时长（事件数据，不读领域内部）。
func _on_run_initialized(payload: RefCounted) -> void:
	var evt := payload as DomainEvents.RunInitialized
	if evt == null:
		return
	match_time_label.text = "本局时长：%d 秒（计时占位，切片 7 接入）" % evt.match_duration


## [EXTRACT_UNLOCKED] 撤离目标切换为解锁态（INV-07）。
func _on_extract_unlocked(payload: RefCounted) -> void:
	var evt := payload as DomainEvents.ExtractUnlocked
	if evt == null:
		return
	var required := 5
	if _orchestrator != null:
		required = _orchestrator.required_container_count()
	set_objective(evt.completed_count, required, true)


## [EXTRACT_STARTED] 撤离读条视觉动画（INV-08 的展示占位）。
## 动画时长取事件数据（来源于配置单一来源）；动画仅为视觉反馈，
## 撤离成败判定由 Extract 域（切片 7）驱动，不由本动画驱动。
func _on_extract_started(payload: RefCounted) -> void:
	var evt := payload as DomainEvents.ExtractStarted
	if evt == null:
		return
	extract_bar.visible = true
	extract_bar_label.visible = true
	extract_bar.value = 100.0
	if _bar_tween != null and _bar_tween.is_valid():
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.tween_property(extract_bar, "value", 0.0, maxf(evt.remaining_extraction_time, 0.1))
