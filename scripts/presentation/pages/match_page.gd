## match_page.gd —— FullHaul 表现层：局内主页面（首页同款像素风，WORD-40）
##
## 职责：
##   局内主页（示意草图布局 + 切片 9 表现层接线）：
##   - 顶部 HUD：本局时间 / 撤离目标 / 携带数（hud.tscn，三属性图标条）
##   - 地图容器实体：对局场景内按本局容器计划生成可点击容器（AC-17），
##     点击即搜索该容器并携带产出（Loot 域 + Item 域携带闭环）
##   - 搜索弹窗：容器内部空间可视化——打开先加载蒙版（物品占格形状），
##     逐件按品质揭晓耗时转圈搜索（越稀有越慢），揭晓后显示 3D 物品；
##     弹窗内只含容器格，不含背包/安全箱
##   - 页底背包/安全箱悬浮面板（GridPanel）：与搜索弹窗同层级——搜索弹窗
##     打开时面板浮在遮罩之上不被压暗、仍可交互，玩家把容器内揭晓的物品
##     拖拽到面板的背包/安全箱格子落地（领域侧分步推进，搬运前不落地）
##   - 操作圆钮：搜索（下一个容器）/ 撤离（解锁后可点，INV-07/08）/
##     完成（读条完毕的调试直达入口）；超时为隐藏调试钩子（测试/验证用）
##   - 本局总计时/撤离读条由 _process 计时循环推进（tick_match_time /
##     tick_extraction，切片 4/7），并轮询阶段变化刷新按钮/容器态
##
## 分层约定：
##   按钮只调用应用编排层用例（RunFlowOrchestrator）；界面状态由事件总线
##   事件与编排器只读查询驱动刷新，本页面不写任何领域状态。

extends Control
class_name MatchPage

## 页底悬浮面板格阵（示意草图：6 列背包 + 安全箱 × 4 行；实际列行数随
## 档位/安全箱配置的领域格子走，格尺寸超宽时自动缩小）
const BOTTOM_COLS := 6
const BOTTOM_ROWS := 4
const BOTTOM_CELL := 128.0
## 页底格阵可用宽度（GridPanel 1080 - 两侧边距 32×2）
const BOTTOM_AREA_W := 1016.0
## 搜索弹窗格尺寸（容器板）
const SEARCH_CONTAINER_CELL := 96.0
## 「高价值存放到安全箱」的价值阈值（单件价值 ≥ 阈值判定为高价值；
## 种子定义价值区间 40~1100，100 恰好把电池/净水壶分到低价值一侧）
const HIGH_VALUE_THRESHOLD := 100
## 操作圆钮直径（虚拟像素，实际 = 虚拟 × PixelUiKit.PX）
const ACTION_D := 28

## 事件总线（组合根注入）
var _bus: IEventBus = null
## 应用编排层（组合根注入）
var _orchestrator: RunFlowOrchestrator = null

@onready var hud: MatchHud = $%Hud
@onready var map_area: Panel = $%MapArea
@onready var map_view: Control = $%MapView
@onready var map_containers: Control = $%MapContainers
@onready var search_button: Button = $%SearchButton
@onready var extract_button: Button = $%ExtractButton
@onready var extract_done_button: Button = $%ExtractDoneButton
@onready var timeout_button: Button = $%TimeoutButton
@onready var grid_panel: Panel = $%GridPanel
@onready var backpack_grid: Control = $%BackpackGrid
@onready var safe_grid: Control = $%SafeGrid

## 页底背包/安全箱格子画布（挂在悬浮面板锚点下；多格物品合并渲染 + 拖拽）
var _backpack_board: GridBoard = null
var _safe_board: GridBoard = null

## 搜索弹窗（PopupBase 程序化构建，见 _build_search_popup）
var search_popup: PopupBase = null
var search_title: Label = null
var search_hint: Label = null
## 搜索弹窗底部三按钮：全部存入背包 / 高价值存入安全箱 / 关闭
var stow_backpack_button: Button = null
var stow_safe_button: Button = null
var close_button: Button = null
## 搜索弹窗内画布：只含容器（蒙版/揭晓），搬运目标为页底悬浮面板
var _container_board: GridBoard = null
## 当前搜索弹窗的容器 id 与计划摘要（container_search_plan 返回）
var _search_container_id := ""
var _search_plan: Dictionary = {}

## 物品 3D 大图弹窗（点击背包格预览打开，复用释放）
var _model_popup: PopupBase = null

## 上帧所见阶段（阶段变化时刷新按钮/容器实体态：RUN_INIT -> IN_RUN_LOCKED
## 等转移不发布事件，事件驱动的刷新会错过启用时机，导致局内按钮全禁用）
var _last_seen_phase: int = -1
## 搜索弹窗动画代际（新一次播放/关闭使旧揭晓序列余留步骤失效）
var _popup_generation := 0

## 地图场平移态（长按/按下拖动移动地图；松手位移在点击半径内视为点击容器）
var _map_dragging := false
var _map_press_pos := Vector2.ZERO
var _map_pan_origin := Vector2.ZERO

## 地图场尺寸（设计 px；大于视口，经拖动平移查看全部容器）
const MAP_CANVAS_SIZE := Vector2(1600, 2000)
## 容器实体尺寸与点击判定半径
const MAP_CONTAINER_SIZE := Vector2(320, 180)
const MAP_TAP_RADIUS := 24.0


func _ready() -> void:
	_apply_styles()
	_build_bottom_grids()
	_build_search_popup()
	search_button.pressed.connect(_on_search_button_pressed)
	extract_button.pressed.connect(_on_extract_button_pressed)
	extract_done_button.pressed.connect(_on_extract_done_button_pressed)
	timeout_button.pressed.connect(_on_timeout_button_pressed)
	map_view.gui_input.connect(_on_map_view_gui_input)


## 组合根（main.gd）注入依赖、订阅事件并初始化展示。
func setup(bus: IEventBus, orchestrator: RunFlowOrchestrator) -> void:
	_bus = bus
	_orchestrator = orchestrator
	hud.setup(bus, orchestrator)
	_bus.subscribe(DomainEvents.Events.RUN_INITIALIZED, _on_run_initialized)
	_bus.subscribe(DomainEvents.Events.EXTRACT_UNLOCKED, _on_extract_unlocked)
	## 物品落格/移动实时刷新底部画布（拖拽搬运、同步搜索携带等任意来源）
	_bus.subscribe(DomainEvents.Events.ITEM_PLACED, _on_inventory_changed)
	_bus.subscribe(DomainEvents.Events.ITEM_MOVED, _on_inventory_changed)
	reset_for_new_run()


## 新一局开始：复位 HUD、重建地图容器与按钮态。
## 强制下一帧刷新按钮/容器实体态（RUN_INITIALIZED 时阶段尚为 RUN_INIT，
## 实体先按禁用构建；RUN_INIT -> IN_RUN_LOCKED 无事件，由 _process 轮询补刷，
## 复位 _last_seen_phase 保证入场后首帧必然刷新，不依赖中间阶段被轮询到）。
func reset_for_new_run() -> void:
	_last_seen_phase = -1
	_popup_generation += 1
	if search_popup != null:
		search_popup.close()
	hud.reset_for_new_run()
	_rebuild_map_containers()
	_refresh_backpack_grid()
	_refresh_buttons()


## [RUN_INITIALIZED] 进入新一局（多局复位，INV-14）。
func _on_run_initialized(_payload: RefCounted) -> void:
	reset_for_new_run()


## [EXTRACT_UNLOCKED] 撤离解锁：开放撤离按钮（INV-07）。
func _on_extract_unlocked(_payload: RefCounted) -> void:
	_refresh_buttons()


## [ITEM_PLACED / ITEM_MOVED] 背包/安全箱内容变化：刷新悬浮面板画布与携带数。
func _on_inventory_changed(_payload: RefCounted) -> void:
	_refresh_backpack_grid()
	hud.set_carried(_orchestrator.carried_item_count() if _orchestrator != null else 0)


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
		## 进入局内阶段补刷背包/安全箱画布（格子初始化与 RUN_INITIALIZED
		## 事件同帧竞态时，事件回调会空过刷新，靠这里兜底）
		_refresh_backpack_grid()
	if phase == RunState.Phase.IN_RUN_LOCKED or phase == RunState.Phase.IN_RUN_EXTRACTABLE:
		_orchestrator.tick_match_time(delta)
		hud.set_match_time(_orchestrator.remaining_match_time())
		hud.set_carried(_orchestrator.carried_item_count())
	elif phase == RunState.Phase.EXTRACTING:
		var resolved := _orchestrator.tick_extraction(delta)
		hud.set_extract_progress(_orchestrator.remaining_extraction_time())
		if resolved:
			_refresh_buttons()


## [UI_INTERACTED] 表现层交互留痕：按钮点击/弹窗开合/拖拽落格等统一发布
## 到事件总线（遥测 console_echo 开启时同步打印控制台日志）。
func _log_ui(action: String, target := "", detail := "") -> void:
	if _bus == null:
		return
	_bus.publish(DomainEvents.Events.UI_INTERACTED,
			DomainEvents.UiInteracted.new("match", action, target, detail))


## 按钮回调：搜索容器（自动选取下一个未完成容器，打开搜索弹窗）。
func _on_search_button_pressed() -> void:
	_log_ui("search_button")
	_open_container_search(_next_container_entry())


## 地图容器点击回调：打开该容器的搜索弹窗（AC-17 可操作容器实体）。
func _on_container_pressed(container_id: String) -> void:
	_log_ui("container_click", container_id)
	_open_container_search(_container_entry(container_id))


## 打开容器搜索（分步流程）：领域侧打开容器进 MASKED（蒙版）→ 弹窗展示
## 蒙版块 → 自动逐件揭晓（转圈速度按品质揭晓耗时）→ 玩家拖拽物品入
## 背包/安全箱。每次打开重建弹窗内容，代际号保证旧揭晓序列失效。
func _open_container_search(entry: Dictionary) -> void:
	if _orchestrator == null or entry.is_empty():
		return
	var container_id := str(entry.get("container_id", ""))
	var plan := _orchestrator.container_search_plan(container_id)
	if plan.is_empty():
		## 未接线 Loot 域（占位编排器）：回退占位完成计数，不开搜索弹窗
		_log_ui("search_button", container_id, "placeholder")
		_orchestrator.complete_container_placeholder()
		_refresh_objective()
		_refresh_container_buttons()
		_refresh_buttons()
		return
	_popup_generation += 1
	_search_container_id = container_id
	_search_plan = plan
	_setup_container_board(entry, plan)
	_refresh_backpack_grid()
	search_title.text = "%s %dx%d" % [str(entry.get("display_name", "容器")),
		maxi(int(entry.get("grid_width", 3)), 1), maxi(int(entry.get("grid_height", 3)), 1)]
	search_hint.text = "搜索中…"
	search_popup.open()
	_log_ui("search_popup_open", container_id)
	_reveal_sequence(_popup_generation)


## 容器板重建：按计划摘要摆蒙版块；已揭晓的块直接显示 3D 物品（中断重开）。
func _setup_container_board(entry: Dictionary, plan: Dictionary) -> void:
	_container_board.configure(maxi(int(entry.get("grid_width", 3)), 1),
			maxi(int(entry.get("grid_height", 3)), 1), SEARCH_CONTAINER_CELL)
	var blocks: Array = plan.get("blocks", [])
	for i in blocks.size():
		var b: Dictionary = blocks[i]
		if bool(b.get("revealed", false)):
			_reveal_container_block(i, str(plan.get("instance_ids", [])[i]),
					_orchestrator.pending_item_info(str(plan.get("instance_ids", [])[i])))
		else:
			_container_board.put_mask(i, b.get("pos", Vector2i.ZERO), b.get("size", Vector2i.ONE))


## 逐件揭晓序列（async）：reveal 拿品质与耗时 → 蒙版挂转圈（速度随品质，
## 越稀有越慢）→ 计时结束 finish 揭晓身份，蒙版替换为 3D 物品。代际号失效
## 中断（关弹窗/新搜索）。全部揭晓后提示拖拽搬运。
func _reveal_sequence(gen: int) -> void:
	var ids: Array = _search_plan.get("instance_ids", [])
	var pending := 0
	for i in ids.size():
		var instance_id := str(ids[i])
		var revealed := _orchestrator.reveal_container_item(_search_container_id, instance_id)
		if revealed.is_empty():
			continue
		if gen != _popup_generation:
			return
		pending += 1
		var wait: float = maxf(float(revealed.get("wait_time", 1.0)), 0.05)
		_attach_mask_spinner(i, TAU / maxf(wait * 2.0, 0.5))
		await get_tree().create_timer(wait).timeout
		if gen != _popup_generation or not is_inside_tree():
			return
		var info := _orchestrator.finish_reveal_container_item(_search_container_id, instance_id)
		_reveal_container_block(i, instance_id, info)
		if bool(info.get("newly_completed", false)):
			_refresh_objective()
			_refresh_container_buttons()
			_refresh_buttons()
	if gen == _popup_generation:
		if pending > 0:
			search_hint.text = "拖拽物品到背包 / 安全箱"
		else:
			search_hint.text = "容器已搜索完毕"
		_refresh_objective()


## 蒙版块挂转圈指示器（speed 弧度/秒，按品质揭晓耗时换算）。
func _attach_mask_spinner(index: int, speed: float) -> void:
	var mask := _container_board.mask_node(index)
	if mask == null:
		return
	var spinner := GridBoard.Spinner.new()
	spinner.speed = speed
	spinner.size = Vector2(44, 44)
	spinner.position = mask.size * 0.5 - spinner.size * 0.5
	spinner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.add_child(spinner)


## 揭晓：蒙版替换为 3D 物品块（品质色框 + 旋转预览，可拖拽搬运）。
func _reveal_container_block(index: int, instance_id: String, info: Dictionary) -> void:
	_container_board.remove_mask(index)
	if info.is_empty():
		return
	var blocks: Array = _search_plan.get("blocks", [])
	var pos: Vector2i = blocks[index].get("pos", Vector2i.ZERO) if index < blocks.size() \
		else Vector2i.ZERO
	var size: Vector2i = info.get("size", Vector2i.ONE)
	var color: Color = PixelUiKit.RARITY_COLORS.get(str(info.get("rarity", "")),
			PixelUiKit.COL_TEXT_DIM)
	var display_name := str(info.get("name", ""))
	_container_board.put_item(instance_id, pos, size, color,
			str(info.get("definition_id", "")),
			"%s（%s）" % [display_name, info.get("rarity", "")])


## 揭晓完成后的目标/按钮刷新（完成数经容器搜索服务查询；占位编排器回退
## 状态机计数）。
func _refresh_objective() -> void:
	var count := 0
	var search_service: IContainerSearchService = _orchestrator.container_search()
	if search_service != null:
		count = search_service.completed_container_count()
	else:
		count = _orchestrator.completed_container_count()
	var required := _orchestrator.required_container_count()
	hud.set_objective(count, required, count >= required)
	hud.set_carried(_orchestrator.carried_item_count())


## 下一个未完成容器的计划条目（与编排器自动选取规则一致）。
func _next_container_entry() -> Dictionary:
	var search_service: IContainerSearchService = _orchestrator.container_search()
	for entry in _orchestrator.match_containers():
		var container_id := str(entry.get("container_id", ""))
		if search_service == null or not search_service.is_container_completed(container_id):
			return entry
	return {}


func _container_entry(container_id: String) -> Dictionary:
	for entry in _orchestrator.match_containers():
		if str(entry.get("container_id", "")) == container_id:
			return entry
	return {}


## 重建地图容器实体（数据驱动：编排器本局容器计划，AC-17）。
## 容器按计划中的随机刷新位置（map_pos 归一化坐标）摆放在大于视口的地图
## 场画布上；实体按钮不消费鼠标（IGNORE），地图视图统一处理长按/拖拽平移
## 与点击命中（见 _on_map_view_gui_input）。
func _rebuild_map_containers() -> void:
	if map_containers == null or _orchestrator == null:
		return
	for child in map_containers.get_children():
		map_containers.remove_child(child)
		child.queue_free()
	map_containers.position = Vector2.ZERO
	var roam := MAP_CANVAS_SIZE - MAP_CONTAINER_SIZE - Vector2(80, 80)
	for entry in _orchestrator.match_containers():
		var container_id := str(entry.get("container_id", ""))
		var display_name := str(entry.get("display_name", "容器"))
		var tier := str(entry.get("tier", "C1"))
		var size_text := "%sx%s" % [entry.get("grid_width", 3), entry.get("grid_height", 3)]
		var map_pos: Vector2 = entry.get("map_pos", Vector2(0.5, 0.5))
		var button := Button.new()
		button.text = "%s〔%s〕%s\n点击搜索" % [display_name, tier, size_text]
		button.custom_minimum_size = MAP_CONTAINER_SIZE
		button.size = MAP_CONTAINER_SIZE
		button.position = Vector2(40, 40) + map_pos * roam
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.set_meta("container_id", container_id)
		button.set_meta("display_name", display_name)
		button.pressed.connect(func(): _on_container_pressed(container_id))
		PixelUiKit.style_rect_button(button,
				PixelUiKit.COL_CHIP_BG, PixelUiKit.COL_BORDER, 22, PixelUiKit.COL_TEXT)
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


## 地图视图输入：按下开始记录，拖动平移地图场（画布位置钳制在视口内），
## 松手时位移在点击半径内视为点击——命中容器实体即打开搜索弹窗
## （实体按钮 mouse_filter = IGNORE，输入统一由地图视图处理）。
func _on_map_view_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var button_event := event as InputEventMouseButton
		if button_event.pressed:
			_map_dragging = true
			_map_press_pos = button_event.position
			_map_pan_origin = map_containers.position
		else:
			_map_dragging = false
			if (button_event.position - _map_press_pos).length() <= MAP_TAP_RADIUS:
				_tap_map_container(button_event.position)
	elif event is InputEventMouseMotion and _map_dragging:
		var motion := event as InputEventMouseMotion
		var offset := _map_pan_origin + motion.position - _map_press_pos
		var min_pos := map_view.size - map_containers.size
		map_containers.position = offset.clamp(
			min_pos.min(Vector2.ZERO), Vector2.ZERO)


## 点击命中：把视图局部坐标映射到画布坐标，找覆盖该点的可交互容器实体。
func _tap_map_container(local_pos: Vector2) -> void:
	var canvas_pos := local_pos - map_containers.position
	for child in map_containers.get_children():
		var button := child as Button
		if button == null or button.disabled:
			continue
		if Rect2(button.position, button.size).has_point(canvas_pos):
			button.pressed.emit()
			return


## 按钮回调：开始撤离（IN_RUN_EXTRACTABLE -> EXTRACTING）。
func _on_extract_button_pressed() -> void:
	if _orchestrator == null:
		return
	_log_ui("extract_button")
	_orchestrator.start_extraction()
	_refresh_buttons()


## 按钮回调：撤离读条完成（调试入口，直达成功结算分支）。
func _on_extract_done_button_pressed() -> void:
	if _orchestrator == null:
		return
	_log_ui("extract_done_button")
	_orchestrator.complete_extraction_placeholder()
	_refresh_buttons()


## 按钮回调：本局时间耗尽（调试入口，直达失败结算分支）。
func _on_timeout_button_pressed() -> void:
	if _orchestrator == null:
		return
	_log_ui("timeout_button")
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


## ---- 搜索弹窗（容器内部空间可视化：蒙版 -> 按品质转速揭晓 -> 拖拽搬运）----

## 组装搜索弹窗骨架（PopupBase 单一来源）：标题 + 容器画布 + 提示 +
## 三按钮（存放到背包 / 高价值存放到安全箱 / 关闭）。
## 弹窗内只含容器格；节点树序移到页底悬浮面板（GridPanel）之下——弹窗
## 遮罩压暗页面其余部分时面板浮在遮罩上不压暗、仍可交互（同层拖拽搬运）。
func _build_search_popup() -> void:
	search_popup = PopupBase.create(Vector2(660, 0), "", false)
	add_child(search_popup)
	move_child(search_popup, grid_panel.get_index())
	## 关闭弹窗即失效进行中的揭晓序列（未搬运物品留在容器内废弃）
	search_popup.closed.connect(func():
		_popup_generation += 1
		_log_ui("search_popup_close", _search_container_id))
	search_title = Label.new()
	search_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	search_title.add_theme_color_override("font_color", PixelUiKit.COL_TEXT)
	search_title.add_theme_font_size_override("font_size", 28)
	search_popup.content.add_child(search_title)
	var wrap := HBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	_container_board = GridBoard.new()
	wrap.add_child(_container_board)
	search_popup.content.add_child(wrap)
	search_hint = Label.new()
	search_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	search_hint.add_theme_color_override("font_color", PixelUiKit.COL_TEXT_DIM)
	search_hint.add_theme_font_size_override("font_size", 20)
	search_hint.text = "搜索中…"
	search_popup.content.add_child(search_hint)
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	stow_backpack_button = Button.new()
	stow_backpack_button.text = "存放到背包"
	stow_backpack_button.custom_minimum_size = Vector2(0, 88)
	PixelUiKit.style_rect_button(stow_backpack_button, PixelUiKit.COL_CHIP_BG,
			PixelUiKit.COL_BORDER, 24, PixelUiKit.COL_TEXT)
	stow_backpack_button.pressed.connect(_on_stow_backpack_button_pressed)
	btn_row.add_child(stow_backpack_button)
	stow_safe_button = Button.new()
	stow_safe_button.text = "高价值存放到安全箱"
	stow_safe_button.custom_minimum_size = Vector2(0, 88)
	PixelUiKit.style_rect_button(stow_safe_button, PixelUiKit.COL_GOLD,
			PixelUiKit.COL_BORDER, 24, PixelUiKit.COL_TEXT)
	stow_safe_button.pressed.connect(_on_stow_high_value_button_pressed)
	btn_row.add_child(stow_safe_button)
	close_button = Button.new()
	close_button.text = "关闭"
	close_button.custom_minimum_size = Vector2(0, 88)
	PixelUiKit.style_rect_button(close_button, PixelUiKit.COL_CHIP_BG,
			PixelUiKit.COL_BORDER, 24, PixelUiKit.COL_TEXT)
	close_button.pressed.connect(func(): search_popup.close())
	btn_row.add_child(close_button)
	search_popup.content.add_child(btn_row)


## [存放到背包] 容器内已揭晓物品逐件 first-fit 存入背包（一次点击全搬）。
func _on_stow_backpack_button_pressed() -> void:
	_stow_all_revealed(GridInventory.OwnerType.BACKPACK, false)


## [高价值存安全箱] 已揭晓物品中单件价值 ≥ 阈值的逐件 first-fit 存入安全箱。
func _on_stow_high_value_button_pressed() -> void:
	_stow_all_revealed(GridInventory.OwnerType.SAFE, true)


## 容器内已揭晓物品批量搬运：owner 为目标格（背包/安全箱）；
## high_value_only 时只搬价值 ≥ HIGH_VALUE_THRESHOLD 的物品。
## 未揭晓的（蒙版态）不搬；目标格放不下的留在容器内。返回 (成功数, 剩余数)。
func _stow_all_revealed(owner: GridInventory.OwnerType, high_value_only: bool) -> void:
	if _orchestrator == null or _container_board == null:
		return
	var inv := _orchestrator.item_inventory()
	var grid: GridInventory = inv.get_grid(owner) if inv != null else null
	if grid == null:
		return
	var owner_name := "BACKPACK" if owner == GridInventory.OwnerType.BACKPACK else "SAFE"
	var stowed := 0
	var left := 0
	for instance_id in _search_plan.get("instance_ids", []):
		var id := str(instance_id)
		## 只搬已揭晓的（蒙版态物品身份未知，不参与一键搬运）
		if not _container_board.has_item(id):
			continue
		var info := _orchestrator.pending_item_info(id)
		if info.is_empty():
			continue
		if high_value_only and int(info.get("value", 0)) < HIGH_VALUE_THRESHOLD:
			left += 1
			continue
		var at := _first_free_at(grid, info.get("size", Vector2i.ONE))
		if at.x < 0 or not _orchestrator.stow_revealed_item(id, owner, at):
			left += 1
			continue
		_container_board.remove_item(id)
		_log_ui("item_stow", id, "%s@(%d,%d) ok" % [owner_name, at.x, at.y])
		stowed += 1
	_refresh_backpack_grid()
	hud.set_carried(_orchestrator.carried_item_count())
	_log_ui("stow_%s" % ("high_value_safe" if high_value_only else "backpack"),
			_search_container_id, "stowed=%d left=%d" % [stowed, left])
	if stowed == 0 and left == 0:
		search_hint.text = "容器已搜索完毕"
	elif left == 0:
		search_hint.text = "已全部放入%s（%d 件）" % ["安全箱" if high_value_only else "背包", stowed]
	else:
		search_hint.text = "已放入 %d 件，剩余 %d 件（空间不足或未揭晓）" % [stowed, left]


## 目标格首个可放置空位（自左上逐行扫描；满格返回 (-1,-1)）。
func _first_free_at(grid: GridInventory, size: Vector2i) -> Vector2i:
	for y in grid.height:
		for x in grid.width:
			var at := Vector2i(x, y)
			if grid.can_place(size, at):
				return at
	return Vector2i(-1, -1)


## ---- 页底背包/安全箱悬浮面板 ----

func _build_bottom_grids() -> void:
	_backpack_board = GridBoard.new()
	_safe_board = GridBoard.new()
	backpack_grid.add_child(_backpack_board)
	safe_grid.add_child(_safe_board)
	_backpack_board.item_clicked.connect(_on_board_item_clicked)
	_safe_board.item_clicked.connect(_on_board_item_clicked)
	_backpack_board.drop_checker = _can_drop_into.bind(GridInventory.OwnerType.BACKPACK)
	_backpack_board.item_dropped.connect(_on_board_drop.bind(GridInventory.OwnerType.BACKPACK))
	_safe_board.drop_checker = _can_drop_into.bind(GridInventory.OwnerType.SAFE)
	_safe_board.item_dropped.connect(_on_board_drop.bind(GridInventory.OwnerType.SAFE))
	_refresh_backpack_grid()


## 按领域格子配置底部画布尺寸的助手已并入 _render_inventory_board（渲染前
## 自动对齐格底尺寸）。


## 携带/安全箱物品按领域 placements 渲染（多格物品合并大块 + 3D 预览；
## 安全箱格为红框视觉）。页底悬浮面板板共用本渲染；板尺寸与领域格子
## 不一致时先重建格底（cell 为单格边长 design px）；anchor 为页底布局锚点
## （板重建后同步其最小尺寸，避免 HBox 里收缩为 0）。
func _render_inventory_board(board: GridBoard, owner: GridInventory.OwnerType,
		cell: float, anchor: Control = null) -> void:
	if board == null:
		return
	var inv := _orchestrator.item_inventory() if _orchestrator != null else null
	var grid: GridInventory = inv.get_grid(owner) if inv != null else null
	if grid == null:
		return
	if board.cols != maxi(grid.width, 1) or board.rows != maxi(grid.height, 1) \
			or absf(board.cell - cell) > 0.01:
		board.configure(maxi(grid.width, 1), maxi(grid.height, 1), cell)
		if anchor != null:
			anchor.custom_minimum_size = board.custom_minimum_size
	else:
		board.clear_items()
	for instance_id in grid.placements:
		var info := _item_info(str(instance_id))
		var color: Color = PixelUiKit.RARITY_COLORS.get(info.rarity, PixelUiKit.COL_TEXT_DIM)
		var entry: Dictionary = grid.placements[instance_id]
		board.put_item(str(instance_id), entry.get("pos", Vector2i.ZERO),
				entry.get("size", Vector2i.ONE), color, str(info.definition_id),
				"%s（%s）" % [info.name, info.rarity])


## 刷新页底背包/安全箱画布（尺寸随领域格子自适应，超宽自动缩小）。
func _refresh_backpack_grid() -> void:
	if _backpack_board == null or _orchestrator == null:
		return
	var inv := _orchestrator.item_inventory()
	if inv == null:
		return
	var bp: GridInventory = inv.get_grid(GridInventory.OwnerType.BACKPACK)
	var safe: GridInventory = inv.get_grid(GridInventory.OwnerType.SAFE)
	if bp == null:
		return
	var safe_cols := maxi(safe.width, 1) if safe != null else 1
	var cell := minf(BOTTOM_CELL, floor((BOTTOM_AREA_W - 24.0 - float(safe_cols) * BOTTOM_CELL)
			/ float(maxi(bp.width, 1))))
	cell = maxf(cell, 40.0)
	_render_inventory_board(_backpack_board, GridInventory.OwnerType.BACKPACK, cell,
			backpack_grid)
	if safe != null:
		_render_inventory_board(_safe_board, GridInventory.OwnerType.SAFE,
				minf(BOTTOM_CELL, cell), safe_grid)


## [板内物品点击] 打开 3D 大图弹窗。
func _on_board_item_clicked(instance_id: String) -> void:
	_log_ui("item_click", instance_id)
	_open_model_popup(_item_info(instance_id))


## 拖拽落点校验（注入 GridBoard；同格移动时忽略自身占格）。
func _can_drop_into(at: Vector2i, size: Vector2i, instance_id: String,
		owner: GridInventory.OwnerType) -> bool:
	var inv := _orchestrator.item_inventory() if _orchestrator != null else null
	var grid: GridInventory = inv.get_grid(owner) if inv != null else null
	if grid == null:
		return false
	var ignore := ""
	var item: ItemInstance = inv.get_item(instance_id)
	if item != null:
		var cur_owner := GridInventory.OwnerType.BACKPACK
		if item.location == ItemInstance.Location.SAFE:
			cur_owner = GridInventory.OwnerType.SAFE
		elif item.location != ItemInstance.Location.BACKPACK:
			cur_owner = GridInventory.OwnerType.WAREHOUSE
		if cur_owner == owner:
			ignore = instance_id
	return grid.can_place(size, at, ignore)


## [拖拽放下] 经编排器把已揭晓物品放入页底悬浮面板的背包/安全箱格子；
## 成功后从容器板移除、刷新面板画布与 HUD 携带数。
func _on_board_drop(instance_id: String, at: Vector2i, owner: GridInventory.OwnerType) -> void:
	if _orchestrator == null:
		return
	var owner_name := "BACKPACK" if owner == GridInventory.OwnerType.BACKPACK else "SAFE"
	var placed := _orchestrator.stow_revealed_item(instance_id, owner, at)
	_log_ui("item_drop", instance_id, "%s@(%d,%d) %s" % [owner_name, at.x, at.y,
			"ok" if placed else "fail"])
	if not placed:
		return
	if _container_board != null and _container_board != _backpack_board:
		_container_board.remove_item(instance_id)
	_refresh_backpack_grid()
	hud.set_carried(_orchestrator.carried_item_count())


## 打开物品 3D 大图弹窗（重建式复用：旧的先释放）。
func _open_model_popup(info: Dictionary) -> void:
	if _model_popup != null:
		_model_popup.queue_free()
	_model_popup = ModelPreviewPopup.create(info)
	add_child(_model_popup)
	_model_popup.open()


## 查询物品展示信息（定义ID/名称/价值/品质；查不到回退 instanceId）。
func _item_info(instance_id: String) -> Dictionary:
	var info := {"definition_id": "", "name": instance_id, "value": 0, "rarity": ""}
	if _orchestrator == null:
		return info
	var inv := _orchestrator.item_inventory()
	if inv == null:
		return info
	var item := inv.get_item(instance_id)
	if item == null:
		return info
	var def := inv.get_definition(item.definition_id)
	if def == null:
		return info
	info.definition_id = def.definition_id
	info.name = def.name
	info.value = def.value
	info.rarity = def.rarity
	return info


## ---- 像素风样式（统一管线：PixelUiKit，与首页共用调色板）----

func _apply_styles() -> void:
	map_area.add_theme_stylebox_override("panel",
			PixelUiKit.inset_stylebox(Color(0.906, 0.898, 0.863), PixelUiKit.COL_BORDER))
	PixelUiKit.style_circle_button(search_button, ACTION_D,
			PixelUiKit.COL_RED, PixelUiKit.COL_RED_BORDER, 30, Color(1, 0.96, 0.94))
	PixelUiKit.style_circle_button(extract_button, ACTION_D,
			PixelUiKit.COL_CHIP_BG, PixelUiKit.COL_BORDER, 30, PixelUiKit.COL_TEXT)
	PixelUiKit.style_circle_button(extract_done_button, ACTION_D,
			PixelUiKit.COL_CHIP_BG, PixelUiKit.COL_BORDER, 30, PixelUiKit.COL_TEXT)
	PixelUiKit.style_circle_button(timeout_button, ACTION_D,
			PixelUiKit.COL_CHIP_BG, PixelUiKit.COL_BORDER, 30, PixelUiKit.COL_TEXT)
	grid_panel.add_theme_stylebox_override("panel",
			PixelUiKit.frame_stylebox(PixelUiKit.COL_PANEL, PixelUiKit.COL_BORDER))
