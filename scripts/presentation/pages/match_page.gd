## match_page.gd —— FullHaul 表现层：局内主页面（首页同款像素风，WORD-40）
##
## 职责：
##   局内主页（示意草图布局 + 切片 9 表现层接线）：
##   - 顶部 HUD：本局时间 / 撤离目标 / 携带数（hud.tscn，三属性图标条）
##   - 地图容器实体：对局场景内按本局容器计划生成可点击容器（AC-17），
##     点击即搜索该容器并携带产出（Loot 域 + Item 域携带闭环）
##   - 搜索弹窗：容器内部空间的可视化（如 3x3 格），逐格扫描动画 +
##     品质色揭晓（纯表现层回放，领域侧一次性完成，不写领域状态）
##   - 操作圆钮：搜索（下一个容器）/ 撤离（解锁后可点，INV-07/08）/
##     完成（读条完毕的调试直达入口）；超时为隐藏调试钩子（测试/验证用）
##   - 底部背包+安全箱格阵：携带物品按品质色填入背包格（红框列为安全箱）
##   - 本局总计时/撤离读条由 _process 计时循环推进（tick_match_time /
##     tick_extraction，切片 4/7），并轮询阶段变化刷新按钮/容器态
##
## 分层约定：
##   按钮只调用应用编排层用例（RunFlowOrchestrator）；界面状态由事件总线
##   事件与编排器只读查询驱动刷新，本页面不写任何领域状态。

extends Control
class_name MatchPage

## 底部格阵（示意草图：6 列背包 + 1 列安全箱 × 4 行）
const BOTTOM_COLS := 6
const BOTTOM_ROWS := 4
const BOTTOM_CELL := 128.0
## 搜索弹窗格尺寸
const SEARCH_CELL := 110.0
## 操作圆钮直径（虚拟像素，实际 = 虚拟 × PixelUiKit.PX）
const ACTION_D := 28

## 事件总线（组合根注入）
var _bus: IEventBus = null
## 应用编排层（组合根注入）
var _orchestrator: RunFlowOrchestrator = null

@onready var hud: MatchHud = $%Hud
@onready var map_area: Panel = $%MapArea
@onready var map_containers: GridContainer = $%MapContainers
@onready var search_button: Button = $%SearchButton
@onready var extract_button: Button = $%ExtractButton
@onready var extract_done_button: Button = $%ExtractDoneButton
@onready var timeout_button: Button = $%TimeoutButton
@onready var backpack_grid: GridContainer = $%BackpackGrid
@onready var safe_grid: GridContainer = $%SafeGrid
@onready var grid_panel: Panel = $%GridPanel

## 搜索弹窗（PopupBase 程序化构建，见 _build_search_popup）
var search_popup: PopupBase = null
var search_title: Label = null
var search_grid: GridContainer = null
var search_hint: Label = null

## 上帧所见阶段（阶段变化时刷新按钮/容器实体态：RUN_INIT -> IN_RUN_LOCKED
## 等转移不发布事件，事件驱动的刷新会错过启用时机，导致局内按钮全禁用）
var _last_seen_phase: int = -1
## 底部背包格实例（携带物品按序填充）
var _backpack_cells: Array = []
## 搜索弹窗动画代际（新一次播放使旧动画的余留步骤失效）
var _popup_generation := 0


func _ready() -> void:
	_apply_styles()
	_build_bottom_grids()
	_build_search_popup()
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


## 按钮回调：搜索容器（自动选取下一个未完成容器，真实 Loot 域搜索 + 携带）。
func _on_search_button_pressed() -> void:
	if _orchestrator == null:
		return
	var entry := _next_container_entry()
	var result := _orchestrator.search_and_carry_container(
			str(entry.get("container_id", "")))
	_after_search(entry, result)


## 地图容器点击回调：搜索指定容器（AC-17 可操作容器实体）。
func _on_container_pressed(container_id: String) -> void:
	if _orchestrator == null:
		return
	var entry := _container_entry(container_id)
	var result := _orchestrator.search_and_carry_container(container_id)
	_after_search(entry, result)


## 搜索后的统一表现层刷新：HUD/容器态/按钮态 + 背包格 + 搜索弹窗动画。
func _after_search(entry: Dictionary, result: Dictionary) -> void:
	_apply_search_result(result)
	_refresh_backpack_grid()
	_play_search_popup(entry, result)


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


## ---- 搜索弹窗（容器内部空间可视化，纯表现层回放）----

## 组装搜索弹窗骨架（PopupBase 单一来源；格子由每次搜索动态填充）。
func _build_search_popup() -> void:
	search_popup = PopupBase.create(Vector2(620, 0))
	add_child(search_popup)
	search_title = Label.new()
	search_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	search_title.add_theme_color_override("font_color", PixelUiKit.COL_TEXT)
	search_title.add_theme_font_size_override("font_size", 28)
	search_popup.content.add_child(search_title)
	var wrap := HBoxContainer.new()
	wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	search_grid = GridContainer.new()
	search_grid.columns = 3
	search_grid.add_theme_constant_override("h_separation", 8)
	search_grid.add_theme_constant_override("v_separation", 8)
	wrap.add_child(search_grid)
	search_popup.content.add_child(wrap)
	search_hint = Label.new()
	search_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	search_hint.add_theme_color_override("font_color", PixelUiKit.COL_TEXT_DIM)
	search_hint.add_theme_font_size_override("font_size", 20)
	search_hint.text = "搜索中…"
	search_popup.content.add_child(search_hint)


## 逐格扫描动画 + 品质色揭晓；领域侧在点击瞬间已完成，此处只做视觉回放。
## 动画用 Tween（绑定本节点）驱动，代际号保证连续搜索（如测试连发）时
## 旧动画余留步骤自动失效。
func _play_search_popup(entry: Dictionary, result: Dictionary) -> void:
	if entry.is_empty():
		return
	_popup_generation += 1
	var gen := _popup_generation
	var w: int = maxi(int(entry.get("grid_width", 3)), 1)
	var h: int = maxi(int(entry.get("grid_height", 3)), 1)
	for child in search_grid.get_children():
		search_grid.remove_child(child)
		child.queue_free()
	search_grid.columns = w
	var cells: Array = []
	for i in w * h:
		var c := PixelUiKit.cell(false, SEARCH_CELL)
		search_grid.add_child(c)
		cells.append(c)
	search_title.text = "%s %dx%d" % [str(entry.get("display_name", "容器")), w, h]
	search_hint.text = "搜索中…"
	search_popup.open()
	var plain := PixelUiKit.inset_stylebox(PixelUiKit.COL_CELL_BG, PixelUiKit.COL_CELL_BORDER)
	var scanning := PixelUiKit.inset_stylebox(Color(0.85, 0.83, 0.75), Color(0.62, 0.68, 0.78))
	var tw := create_tween()
	for i in cells.size():
		var scan_cell: Panel = cells[i]
		tw.tween_callback(func():
			if gen == _popup_generation and is_instance_valid(scan_cell):
				scan_cell.add_theme_stylebox_override("panel", scanning)
		)
		tw.tween_interval(0.07)
		tw.tween_callback(func():
			if gen == _popup_generation and is_instance_valid(scan_cell):
				scan_cell.add_theme_stylebox_override("panel", plain)
		)
	tw.tween_callback(func(): _reveal_search_result(gen, cells, result))
	tw.tween_interval(0.9)
	tw.tween_callback(func():
		if gen == _popup_generation:
			search_popup.close()
	)


## 揭晓：随机一格亮起品质色（携带物品取本局最新一件的定义）。
func _reveal_search_result(gen: int, cells: Array, result: Dictionary) -> void:
	if gen != _popup_generation or cells.is_empty():
		return
	if result.get("carried_count", 0) > 0 and _orchestrator != null:
		var ids := _orchestrator.backpack_item_ids()
		if not ids.is_empty():
			var info := _item_info(str(ids[ids.size() - 1]))
			var reveal_cell: Panel = cells[randi() % cells.size()]
			var c: Color = PixelUiKit.RARITY_COLORS.get(info.rarity, PixelUiKit.COL_TEXT_DIM)
			reveal_cell.add_theme_stylebox_override("panel",
					PixelUiKit.inset_stylebox(c.darkened(0.55), c))
			search_hint.text = "获得 %s（%s）已携带入背包" % [info.name, info.rarity]
			return
	search_hint.text = "一无所获…"


## ---- 底部背包/安全箱格阵 ----

func _build_bottom_grids() -> void:
	for i in BOTTOM_COLS * BOTTOM_ROWS:
		var c := PixelUiKit.cell(false, BOTTOM_CELL)
		backpack_grid.add_child(c)
		_backpack_cells.append(c)
	for i in BOTTOM_ROWS:
		safe_grid.add_child(PixelUiKit.cell(true, BOTTOM_CELL))
	_refresh_backpack_grid()


## 携带物品按序填入背包格（品质色内嵌框 + 名称提示；安全箱格为视觉占位）。
func _refresh_backpack_grid() -> void:
	if _backpack_cells.is_empty():
		return
	var ids: Array = _orchestrator.backpack_item_ids() if _orchestrator != null else []
	for i in _backpack_cells.size():
		var c: Panel = _backpack_cells[i]
		if i < ids.size():
			var info := _item_info(str(ids[i]))
			var rarity: Color = PixelUiKit.RARITY_COLORS.get(info.rarity, PixelUiKit.COL_TEXT_DIM)
			c.add_theme_stylebox_override("panel",
					PixelUiKit.inset_stylebox(rarity.darkened(0.55), rarity))
			c.tooltip_text = "%s（%s）" % [info.name, info.rarity]
		else:
			c.add_theme_stylebox_override("panel",
					PixelUiKit.inset_stylebox(PixelUiKit.COL_CELL_BG, PixelUiKit.COL_CELL_BORDER))
			c.tooltip_text = ""


## 查询物品展示信息（名称/价值/品质；查不到回退 instanceId）。
func _item_info(instance_id: String) -> Dictionary:
	var info := {"name": instance_id, "value": 0, "rarity": ""}
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
