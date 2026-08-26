## hud.gd —— FullHaul 表现层：局内 HUD（首页同款像素风，WORD-40）
##
## 职责：
##   局内主页面顶部的属性条（示意草图「属性1/2/3」，与局外同一像素管线）：
##     1. 本局剩余时间（沙漏图标 + 倒计时，切片 4/9 计时）
##     2. 撤离目标（容器图标 + 完成数 x/N，锁定/解锁态）
##     3. 携带物品（背包图标 + 数量，切片 9 携带闭环）
##   撤离读条（EXTRACT_STARTED 后的纯视觉动画，不承载判定）显示于地图区上方。
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

@onready var top_bar: Panel = $%TopBar
@onready var time_icon: TextureRect = $%TimeIcon
@onready var objective_icon: TextureRect = $%ObjectiveIcon
@onready var carry_icon: TextureRect = $%CarryIcon
@onready var objective_label: Label = $%ObjectiveLabel
@onready var match_time_label: Label = $%MatchTimeLabel
@onready var backpack_label: Label = $%BackpackLabel
@onready var extract_bar: ProgressBar = $%ExtractBar
@onready var extract_bar_label: Label = $%ExtractBarLabel


func _ready() -> void:
	_apply_styles()


## 像素风样式（统一管线：PixelUiKit，与首页共用调色板）。
func _apply_styles() -> void:
	top_bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	top_bar.add_theme_stylebox_override("panel",
			PixelUiKit.frame_stylebox(PixelUiKit.COL_PANEL, PixelUiKit.COL_BORDER))
	time_icon.texture = PixelUiKit.icon_texture("hourglass")
	objective_icon.texture = PixelUiKit.icon_texture("crate")
	carry_icon.texture = PixelUiKit.icon_texture("backpack")
	extract_bar.add_theme_stylebox_override("background",
			PixelUiKit.inset_stylebox(Color(0.07, 0.09, 0.12), PixelUiKit.COL_BORDER))
	var fill := StyleBoxFlat.new()
	fill.bg_color = PixelUiKit.COL_GOLD
	fill.anti_aliasing = false
	extract_bar.add_theme_stylebox_override("fill", fill)


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
		objective_label.text = "容器 %d/%d —— 撤离已解锁" % [current, required]
	else:
		objective_label.text = "容器 %d/%d（锁定）" % [current, required]


## 展示本局剩余总时间（秒；由 match_page 计时循环调用，切片 4/9）。
func set_match_time(seconds: int) -> void:
	match_time_label.text = "剩余 %d 秒" % maxi(seconds, 0)


## 展示已携带入背包的物品数（切片 9 携带闭环）。
func set_carried(count: int) -> void:
	backpack_label.text = "携带 %d 件" % count


## 展示撤离读条剩余时间（秒；EXTRACTING 期间由计时循环调用，切片 7/9）。
## 读条按配置的撤离时长归一为百分比（INV-16 单一来源，不硬编码 15）。
func set_extract_progress(remaining_seconds: int) -> void:
	extract_bar.visible = true
	extract_bar_label.visible = true
	var total := 15.0
	if _orchestrator != null:
		total = maxf(float(_orchestrator.extraction_duration()), 1.0)
	extract_bar.value = clampf(remaining_seconds * 100.0 / total, 0.0, 100.0)
	extract_bar_label.text = "撤离读条：剩余 %d 秒" % maxi(remaining_seconds, 0)


## 新一局开始时复位 HUD。
## 本局时长不在此复位：它只由 RUN_INITIALIZED 事件数据写入（订阅顺序
## 无关，避免复位覆盖事件更新）。
func reset_for_new_run() -> void:
	var required := 5
	if _orchestrator != null:
		required = _orchestrator.required_container_count()
	set_objective(0, required, false)
	set_carried(0)
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
	set_match_time(evt.match_duration)


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
