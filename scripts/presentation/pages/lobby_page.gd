## lobby_page.gd —— FullHaul 表现层：局外主页（仓库场景视觉升级 V1）
##
## 职责：
##   首页布局与交互接线：
##   - 顶部三属性栏：货币 / 仓库（点按打开仓库格子弹窗）/ 背包档位
##   - 中部仓库场景（WarehouseView：底图+叠层物；可拖动平移、滚轮缩放，
##     点击货架等叠层物同样触发对应弹窗/伏笔提示）
##   - 背包格阵 + 安全箱格阵（红框列，视觉区）
##   - 快捷按钮：菜园/工坊/出击（开始一局）/市场/科技（占位）
##   功能链与切片 9 保持一致：货币展示、仓库出售（移入弹窗）、
##   「出击」= RunFlowOrchestrator.request_start_match。
##
## 分层约定：
##   按钮只调用应用编排层用例；界面状态由事件总线事件与编排器只读查询
##   驱动刷新，本页面不写任何领域状态。
##
## 显示时机：
##   由 PageRouter 订阅 OUT_OF_RUN_ENTERED 事件驱动显示/隐藏。

extends Control
class_name LobbyPage

## 背包/安全箱可见格阵（示意草图：6 列 = 5 列背包 + 1 列安全箱，4 行）
const GRID_COLS := 5
const GRID_ROWS := 4
const CELL_SIZE := 150.0
## 仓库格子画布（局外储物空间 8×6，与组合根 setup_warehouse 尺寸一致）
const WAREHOUSE_COLS := 8
const WAREHOUSE_ROWS := 6
const WAREHOUSE_CELL := 96.0
## 快捷按钮直径（虚拟像素，实际尺寸 = 虚拟 × PixelUiKit.PX）
const SMALL_BUTTON_D := 26
const BIG_BUTTON_D := 40
## HUD 顶栏：生命/氧气条内可填充最大宽度（200 - 两侧内距 14×2）
const HUD_BAR_FILL_W := 172.0
## HUD 右上圆形按钮直径（虚拟像素）
const HUD_CIRCLE_D := 16
## 生命/氧气当前百分比（占位常量；生命/属性域为未来方向，接入后由事件驱动）
const HUD_HP := 1.0
const HUD_O2 := 1.0
## 场景点击判定阈值（拖动位移低于此值视为点击叠层物）
const PROP_TAP_RADIUS := 8.0

## 应用编排层（组合根注入；仅调用其用例方法）
var _orchestrator: RunFlowOrchestrator = null
## 事件总线（组合根注入；订阅刷新事件）
var _bus: IEventBus = null
## Toast 隐藏定时器令牌（连点时只让最后一个定时器生效）
var _toast_token := 0
## 场景拖动状态
var _base_dragging := false
var _base_drag_mouse := Vector2.ZERO
var _base_drag_pan := Vector2.ZERO

@onready var currency_icon: TextureRect = $%CurrencyIcon
@onready var currency_value: Label = $%CurrencyValue
@onready var hp_icon: TextureRect = $%HpIcon
@onready var hp_bar: Panel = $%HpBar
@onready var hp_fill: ColorRect = $%HpFill
@onready var hp_pct: Label = $%HpPct
@onready var o2_icon: TextureRect = $%O2Icon
@onready var o2_bar: Panel = $%O2Bar
@onready var o2_fill: ColorRect = $%O2Fill
@onready var o2_pct: Label = $%O2Pct
@onready var warehouse_button: Button = $%WarehouseButton
@onready var warehouse_badge: Label = $%WarehouseBadge
@onready var warehouse_icon: TextureRect = $%WarehouseIcon
@onready var backpack_button: Button = $%BackpackButton
@onready var backpack_icon: TextureRect = $%BackpackIcon
@onready var backpack_grid: GridContainer = $%BackpackGrid
@onready var safe_grid: GridContainer = $%SafeGrid
@onready var grid_panel: Panel = $%GridPanel
@onready var garden_button: Button = $%GardenButton
@onready var workshop_button: Button = $%WorkshopButton
@onready var start_button: Button = $%StartButton
@onready var market_button: Button = $%MarketButton
@onready var tech_button: Button = $%TechButton
@onready var toast_label: Label = $%ToastLabel
@onready var base_area: Control = $BaseArea
@onready var warehouse_view: WarehouseView = $BaseArea/SceneViewportContainer/SceneViewport/WarehouseView

## 仓库出售弹窗（PopupBase 程序化构建，见 _build_warehouse_popup）
var warehouse_popup: PopupBase = null
## 仓库格子画布（8×6；物品按定义尺寸合并大块 + 3D 预览，可拖拽重排、
## 点击开大图出售）
var warehouse_board: GridBoard = null
var _warehouse_empty: Label = null
## 物品 3D 大图弹窗（点击仓库物品块预览打开，复用释放）
var _model_popup: PopupBase = null


func _ready() -> void:
	_apply_styles()
	_build_grids()
	_build_warehouse_popup()
	start_button.pressed.connect(_on_start_button_pressed)
	warehouse_button.pressed.connect(_on_warehouse_button_pressed)
	backpack_button.pressed.connect(_on_backpack_button_pressed)
	garden_button.pressed.connect(func(): _on_placeholder_pressed("菜园"))
	workshop_button.pressed.connect(func(): _on_placeholder_pressed("工坊"))
	market_button.pressed.connect(func(): _on_placeholder_pressed("市场"))
	tech_button.pressed.connect(func(): _on_placeholder_pressed("科技"))
	base_area.gui_input.connect(_on_base_area_gui_input)
	warehouse_view.prop_activated.connect(_on_warehouse_prop_activated)


## 组合根（main.gd）注入编排器与事件总线。
func setup(bus: IEventBus, orchestrator: RunFlowOrchestrator) -> void:
	_bus = bus
	_orchestrator = orchestrator
	if _bus != null:
		_bus.subscribe(DomainEvents.Events.OUT_OF_RUN_ENTERED, _on_out_of_run_entered)
		_bus.subscribe(DomainEvents.Events.CURRENCY_CHANGED, _on_currency_changed)
		_bus.subscribe(DomainEvents.Events.WAREHOUSE_ITEM_ADDED, _on_warehouse_changed)
		_bus.subscribe(DomainEvents.Events.ITEM_SOLD, _on_warehouse_changed)
	_refresh()


## [UI_INTERACTED] 表现层交互留痕：按钮点击/弹窗开合/拖拽落格等统一发布
## 到事件总线（遥测 console_echo 开启时同步打印控制台日志）。
func _log_ui(action: String, target := "", detail := "") -> void:
	if _bus == null:
		return
	_bus.publish(DomainEvents.Events.UI_INTERACTED,
			DomainEvents.UiInteracted.new("lobby", action, target, detail))


## [叠层物点击] 货架/地堆 → 仓库弹窗；卷帘门 → 撤离伏笔提示。
func _on_warehouse_prop_activated(_prop_id: String, action: String) -> void:
	_log_ui("prop_click", str(_prop_id), action)
	match action:
		"warehouse":
			_on_warehouse_button_pressed()
		"extract":
			_show_toast("出车准备中，敬请期待")


## [出击] 开始一局：只调用应用编排层用例（同旧版「开始一局」）。
func _on_start_button_pressed() -> void:
	if _orchestrator == null:
		return
	_log_ui("start_button")
	_orchestrator.request_start_match()


## [仓库圆钮] 打开仓库出售弹窗。
func _on_warehouse_button_pressed() -> void:
	_log_ui("warehouse_button")
	warehouse_popup.open()
	_rebuild_warehouse(_warehouse_ids())


## [背包圆钮] 轻提示当前背包档位。
func _on_backpack_button_pressed() -> void:
	_log_ui("backpack_button")
	var profile: PlayerProfile = _orchestrator.current_profile() if _orchestrator != null else null
	_show_toast("背包：%s" % _offer_size_text(profile))


## 组装仓库出售弹窗（统一 PopupBase 骨架：格子画布 + 空态提示 + 内建关闭）。
func _build_warehouse_popup() -> void:
	warehouse_popup = PopupBase.create(Vector2(920, 1160), "仓库（出售换货币）", true)
	add_child(warehouse_popup)
	warehouse_board = GridBoard.create(WAREHOUSE_COLS, WAREHOUSE_ROWS, WAREHOUSE_CELL)
	warehouse_board.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	warehouse_board.drop_checker = _can_drop_warehouse
	warehouse_board.item_dropped.connect(_on_warehouse_drop)
	warehouse_board.item_clicked.connect(_on_warehouse_item_clicked)
	warehouse_popup.content.add_child(warehouse_board)
	_warehouse_empty = Label.new()
	_warehouse_empty.text = "仓库空空如也，快去出击搜刮吧"
	_warehouse_empty.add_theme_color_override("font_color", PixelUiKit.COL_TEXT_DIM)
	_warehouse_empty.add_theme_font_size_override("font_size", 26)
	_warehouse_empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	warehouse_popup.content.add_child(_warehouse_empty)


## 仓库拖拽重排落点校验（同件移动忽略自身占格）。
func _can_drop_warehouse(at: Vector2i, size: Vector2i, instance_id: String) -> bool:
	var inv := _orchestrator.item_inventory() if _orchestrator != null else null
	var grid: GridInventory = inv.get_grid(GridInventory.OwnerType.WAREHOUSE) if inv != null else null
	return grid != null and grid.can_place(size, at, instance_id)


## [仓库拖拽放下] 经编排器重排（INV-04 校验）；成功更新块位置。
func _on_warehouse_drop(instance_id: String, at: Vector2i) -> void:
	var moved := _orchestrator != null and _orchestrator.move_warehouse_item(instance_id, at)
	_log_ui("item_move", instance_id, "(%d,%d) %s" % [at.x, at.y, "ok" if moved else "fail"])
	if moved:
		warehouse_board.move_item(instance_id, at)


## [仓库物品点击] 打开 3D 大图弹窗（带出售按钮）。
func _on_warehouse_item_clicked(instance_id: String) -> void:
	_log_ui("item_click", instance_id)
	if _model_popup != null:
		_model_popup.queue_free()
	_model_popup = ModelPreviewPopup.create(_item_info(instance_id),
			func(): _on_sell_pressed(instance_id))
	add_child(_model_popup)
	_model_popup.open()


## [快捷占位钮] 未开放玩法给轻提示。
func _on_placeholder_pressed(title: String) -> void:
	_log_ui("placeholder_button", title)
	_show_toast("「%s」建设中，敬请期待" % title)


## [OUT_OF_RUN_ENTERED] 每次进入局外刷新属性与仓库。
func _on_out_of_run_entered(_payload: RefCounted) -> void:
	_refresh()


## [CURRENCY_CHANGED] 货币变动刷新。
func _on_currency_changed(_payload: RefCounted) -> void:
	_refresh()


## [WAREHOUSE_ITEM_ADDED / ITEM_SOLD] 仓库变动刷新。
func _on_warehouse_changed(_payload: RefCounted) -> void:
	_refresh()


## 刷新 HUD 属性与仓库弹窗列表（编排器只读查询 + 事件驱动）。
func _refresh() -> void:
	var profile: PlayerProfile = _orchestrator.current_profile() if _orchestrator != null else null
	if currency_value != null:
		currency_value.text = str(profile.currency if profile != null else 0)
	if warehouse_badge != null:
		warehouse_badge.text = str(profile.warehouse_item_ids.size() if profile != null else 0)
	_refresh_hud()
	if warehouse_popup != null and warehouse_popup.visible:
		_rebuild_warehouse(_warehouse_ids())


## 刷新生命/氧气百分比条（当前为占位常量，未来由属性域事件驱动）。
func _refresh_hud() -> void:
	if hp_fill != null:
		hp_fill.size = Vector2(HUD_BAR_FILL_W * HUD_HP, hp_fill.size.y)
	if o2_fill != null:
		o2_fill.size = Vector2(HUD_BAR_FILL_W * HUD_O2, o2_fill.size.y)
	if hp_pct != null:
		hp_pct.text = "%d%%" % roundi(HUD_HP * 100.0)
	if o2_pct != null:
		o2_pct.text = "%d%%" % roundi(HUD_O2 * 100.0)


## 已选背包档位的尺寸文案（如「5×5」；未购返回「未购」）。
func _offer_size_text(profile: PlayerProfile) -> String:
	var offer_id := profile.selected_backpack_offer_id if profile != null else ""
	if offer_id.is_empty():
		return "未购"
	if _orchestrator == null:
		return "已购"
	var offers: Dictionary = _orchestrator.loaded_config_data().get("backpack_offers", {})
	if offers.has(offer_id):
		var offer: Dictionary = offers[offer_id]
		return "%d×%d" % [int(offer.get("grid_width", 0)), int(offer.get("grid_height", 0))]
	return "已购"


func _warehouse_ids() -> Array:
	if _orchestrator == null:
		return []
	var profile := _orchestrator.current_profile()
	return profile.warehouse_item_ids if profile != null else []


## 重建仓库格子画布（账本物品逐件确保摆放：多格物品合并大块 + 3D 预览，
## 可拖拽重排、点击开大图出售）。
func _rebuild_warehouse(instance_ids: Array) -> void:
	if warehouse_board == null:
		return
	warehouse_board.clear_items()
	_warehouse_empty.visible = instance_ids.is_empty()
	warehouse_board.visible = not instance_ids.is_empty()
	for instance_id in instance_ids:
		var iid := str(instance_id)
		var at := Vector2i(-1, -1)
		if _orchestrator != null:
			at = _orchestrator.ensure_warehouse_placement(iid)
		if at == Vector2i(-1, -1):
			continue
		var info := _item_info(iid)
		var size := Vector2i.ONE
		if not str(info.definition_id).is_empty():
			var def := _orchestrator.item_inventory().get_definition(str(info.definition_id))
			if def != null:
				size = def.size()
		var color: Color = PixelUiKit.RARITY_COLORS.get(info.rarity, PixelUiKit.COL_TEXT_DIM)
		warehouse_board.put_item(iid, at, size, color, str(info.definition_id),
				"%s（%s）" % [info.name, info.rarity])


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


## 按钮回调：出售一件仓库物品（INV-12 原子事务）。
func _on_sell_pressed(instance_id: String) -> void:
	if _orchestrator == null:
		return
	_log_ui("sell_button", instance_id)
	_orchestrator.sell_warehouse_item(instance_id)


## 轻提示：1.4 秒后自动隐藏（连点时只保留最后一次）。
func _show_toast(text: String) -> void:
	toast_label.text = text
	toast_label.visible = true
	_toast_token += 1
	var token := _toast_token
	get_tree().create_timer(1.4).timeout.connect(func():
		if token == _toast_token:
			toast_label.visible = false)


## ---- 卡通风样式（统一管线：PixelUiKit 扁平圆角面板）----

func _apply_styles() -> void:
	## HUD：图标与百分比条
	currency_icon.texture = PixelUiKit.icon_texture("coin")
	hp_icon.texture = PixelUiKit.icon_texture("heart")
	o2_icon.texture = PixelUiKit.icon_texture("bubble")
	hp_bar.add_theme_stylebox_override("panel",
			PixelUiKit.inset_stylebox(Color(0.961, 0.898, 0.882), Color(0.757, 0.325, 0.302)))
	o2_bar.add_theme_stylebox_override("panel",
			PixelUiKit.inset_stylebox(Color(0.894, 0.937, 0.965), Color(0.16, 0.52, 0.66)))
	## 顶条直接压在深色页面背景上，文字用亮色保证可读
	currency_value.add_theme_color_override("font_color", PixelUiKit.COL_TEXT_BRIGHT)
	warehouse_badge.add_theme_color_override("font_color", PixelUiKit.COL_TEXT_BRIGHT)
	## HUD 右上圆形按钮（仓库/背包）
	warehouse_icon.texture = PixelUiKit.icon_texture("crate")
	backpack_icon.texture = PixelUiKit.icon_texture("backpack")
	PixelUiKit.style_circle_button(warehouse_button, HUD_CIRCLE_D,
			PixelUiKit.COL_CHIP_BG, PixelUiKit.COL_BORDER, 16, PixelUiKit.COL_TEXT)
	PixelUiKit.style_circle_button(backpack_button, HUD_CIRCLE_D,
			PixelUiKit.COL_CHIP_BG, PixelUiKit.COL_BORDER, 16, PixelUiKit.COL_TEXT)
	for btn in [garden_button, workshop_button, market_button, tech_button]:
		PixelUiKit.style_circle_button(btn, SMALL_BUTTON_D,
				PixelUiKit.COL_CHIP_BG, PixelUiKit.COL_BORDER, 30, PixelUiKit.COL_TEXT)
	PixelUiKit.style_circle_button(start_button, BIG_BUTTON_D,
			PixelUiKit.COL_RED, PixelUiKit.COL_RED_BORDER, 46, Color(1, 0.96, 0.94))
	grid_panel.add_theme_stylebox_override("panel",
			PixelUiKit.frame_stylebox(PixelUiKit.COL_PANEL, PixelUiKit.COL_BORDER))


## 生成背包/安全箱格阵（示意草图：5 列背包 + 1 列安全箱 × 4 行）。
func _build_grids() -> void:
	for i in GRID_COLS * GRID_ROWS:
		backpack_grid.add_child(_make_cell(false))
	for i in GRID_ROWS:
		safe_grid.add_child(_make_cell(true))


func _make_cell(is_safe: bool) -> Control:
	var cell := Panel.new()
	cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	if is_safe:
		cell.add_theme_stylebox_override("panel", PixelUiKit.inset_stylebox(PixelUiKit.COL_SAFE_BG, PixelUiKit.COL_SAFE_BORDER))
	else:
		cell.add_theme_stylebox_override("panel", PixelUiKit.inset_stylebox(PixelUiKit.COL_CELL_BG, PixelUiKit.COL_CELL_BORDER))
	return cell


## ---- 仓库场景拖动 / 滚轮缩放 / 叠层物点击（坐标为 BaseArea 本地 = 视口系）----

func _on_base_area_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed \
			and ((event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP
				or (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_DOWN):
		var zoom_in := (event as InputEventMouseButton).button_index == MOUSE_BUTTON_WHEEL_UP
		warehouse_view.set_zoom(WarehouseView.WHEEL_ZOOM_STEP if zoom_in
				else 1.0 / WarehouseView.WHEEL_ZOOM_STEP)
		_log_ui("scene_zoom", "", "%.2f" % warehouse_view.zoom())
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_base_dragging = event.pressed
		if _base_dragging:
			_base_drag_mouse = (event as InputEventMouseButton).position
			_base_drag_pan = warehouse_view.pan()
		elif warehouse_view.pan().distance_to(_base_drag_pan) <= PROP_TAP_RADIUS:
			warehouse_view.try_activate_at(event.position)
	elif event is InputEventMouseMotion and _base_dragging:
		var motion := event as InputEventMouseMotion
		warehouse_view.set_pan(_base_drag_pan + motion.position - _base_drag_mouse)
