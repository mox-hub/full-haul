## lobby_page.gd —— FullHaul 表现层：局外主页（首页视觉 V0.1，WORD-40）
##
## 职责：
##   按示意草图还原首页布局（像素化 2.5D 风格）：
##   - 顶部三属性栏：货币 / 仓库（点按打开仓库出售弹窗）/ 背包档位
##   - 中部 2.5D 俯视像素基地（BaseView，纯表现无业务）
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
## 基地视图长按拖动的活动范围（design px，相对初始位置）
const BASE_PAN_MAX := Vector2(110.0, 70.0)
## 基地视图初始位置（BaseArea 局部坐标，画布中心）
const BASE_VIEW_HOME := Vector2(540.0, 405.0)
## 像素风调色板/品质色统一取自 PixelUiKit（首页/局内共用单一来源）

## 应用编排层（组合根注入；仅调用其用例方法）
var _orchestrator: RunFlowOrchestrator = null
## 事件总线（组合根注入；订阅刷新事件）
var _bus: IEventBus = null
## Toast 隐藏定时器令牌（连点时只让最后一个定时器生效）
var _toast_token := 0
## 基地视图长按拖动状态
var _base_dragging := false
var _base_drag_mouse := Vector2.ZERO
var _base_drag_view := Vector2.ZERO

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
@onready var warehouse_popup: Control = $%WarehousePopup
@onready var warehouse_list: VBoxContainer = $%WarehouseList
@onready var popup_close: Button = $%PopupClose
@onready var popup_panel: PanelContainer = $%PopupPanel
@onready var base_area: Control = $BaseArea
@onready var base_view: Node2D = $BaseArea/BaseView


func _ready() -> void:
	_apply_styles()
	_build_grids()
	start_button.pressed.connect(_on_start_button_pressed)
	warehouse_button.pressed.connect(_on_warehouse_button_pressed)
	backpack_button.pressed.connect(_on_backpack_button_pressed)
	popup_close.pressed.connect(_on_popup_close_pressed)
	garden_button.pressed.connect(func(): _on_placeholder_pressed("菜园"))
	workshop_button.pressed.connect(func(): _on_placeholder_pressed("工坊"))
	market_button.pressed.connect(func(): _on_placeholder_pressed("市场"))
	tech_button.pressed.connect(func(): _on_placeholder_pressed("科技"))
	base_area.gui_input.connect(_on_base_area_gui_input)


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


## [出击] 开始一局：只调用应用编排层用例（同旧版「开始一局」）。
func _on_start_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.request_start_match()


## [仓库圆钮] 打开仓库出售弹窗。
func _on_warehouse_button_pressed() -> void:
	warehouse_popup.visible = true
	_rebuild_warehouse(_warehouse_ids())


## [背包圆钮] 轻提示当前背包档位。
func _on_backpack_button_pressed() -> void:
	var profile: PlayerProfile = _orchestrator.current_profile() if _orchestrator != null else null
	_show_toast("背包：%s" % _offer_size_text(profile))


func _on_popup_close_pressed() -> void:
	warehouse_popup.visible = false


## [快捷占位钮] 未开放玩法给轻提示。
func _on_placeholder_pressed(title: String) -> void:
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


## 重建仓库弹窗列表（每件一行：品质条 + 名称/价值 + 出售按钮）。
func _rebuild_warehouse(instance_ids: Array) -> void:
	if warehouse_list == null:
		return
	for child in warehouse_list.get_children():
		child.queue_free()
	if instance_ids.is_empty():
		var empty := Label.new()
		empty.text = "仓库空空如也，快去出击搜刮吧"
		empty.add_theme_color_override("font_color", PixelUiKit.COL_TEXT_DIM)
		empty.add_theme_font_size_override("font_size", 26)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		warehouse_list.add_child(empty)
		return
	for instance_id in instance_ids:
		warehouse_list.add_child(_make_warehouse_row(str(instance_id)))


## 构造一行仓库条目。
func _make_warehouse_row(instance_id: String) -> Control:
	var info := _item_info(instance_id)
	var row := PanelContainer.new()
	row.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	row.add_theme_stylebox_override("panel", PixelUiKit.inset_stylebox(PixelUiKit.COL_ROW_BG, PixelUiKit.COL_BORDER))
	row.custom_minimum_size = Vector2(0, 76)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 18)
	for side in ["margin_top", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	row.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)
	## 品质色条（纯色小块，随行内像素风直角呈现）
	var rarity_bar := Panel.new()
	var rarity_color: Color = PixelUiKit.RARITY_COLORS.get(info.rarity, PixelUiKit.COL_TEXT_DIM)
	var bar_sb := StyleBoxFlat.new()
	bar_sb.bg_color = rarity_color
	bar_sb.anti_aliasing = false
	rarity_bar.add_theme_stylebox_override("panel", bar_sb)
	rarity_bar.custom_minimum_size = Vector2(14, 44)
	rarity_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(rarity_bar)
	var label := Label.new()
	label.text = "%s　价值 %d" % [info.name, info.value]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	label.add_theme_font_size_override("font_size", 28)
	box.add_child(label)
	var sell := Button.new()
	sell.text = "出售"
	sell.custom_minimum_size = Vector2(150, 58)
	sell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	PixelUiKit.style_rect_button(sell, PixelUiKit.COL_RED, PixelUiKit.COL_RED_BORDER, 26, Color(1, 0.96, 0.94))
	sell.pressed.connect(func(): _on_sell_pressed(instance_id))
	box.add_child(sell)
	return row


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


## 按钮回调：出售一件仓库物品（INV-12 原子事务）。
func _on_sell_pressed(instance_id: String) -> void:
	if _orchestrator == null:
		return
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


## ---- 像素风样式（统一管线：PixelUiKit 低分辨率框架 -> 最近邻放大）----

func _apply_styles() -> void:
	## HUD：图标与百分比条（像素管线）
	currency_icon.texture = PixelUiKit.icon_texture("coin")
	hp_icon.texture = PixelUiKit.icon_texture("heart")
	o2_icon.texture = PixelUiKit.icon_texture("bubble")
	for bar in [hp_bar, o2_bar]:
		bar.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	hp_bar.add_theme_stylebox_override("panel",
			PixelUiKit.inset_stylebox(Color(0.07, 0.09, 0.12), Color(0.55, 0.22, 0.2)))
	o2_bar.add_theme_stylebox_override("panel",
			PixelUiKit.inset_stylebox(Color(0.07, 0.09, 0.12), Color(0.16, 0.42, 0.5)))
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
	PixelUiKit.style_rect_button(popup_close,
			PixelUiKit.COL_CHIP_BG, PixelUiKit.COL_BORDER, 30, PixelUiKit.COL_TEXT)
	for panel in [grid_panel, popup_panel]:
		panel.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		panel.add_theme_stylebox_override("panel",
				PixelUiKit.frame_stylebox(PixelUiKit.COL_PANEL, PixelUiKit.COL_BORDER))


## 生成背包/安全箱格阵（示意草图：5 列背包 + 1 列安全箱 × 4 行）。
func _build_grids() -> void:
	for i in GRID_COLS * GRID_ROWS:
		backpack_grid.add_child(_make_cell(false))
	for i in GRID_ROWS:
		safe_grid.add_child(_make_cell(true))


func _make_cell(is_safe: bool) -> Control:
	var cell := Panel.new()
	cell.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
	if is_safe:
		cell.add_theme_stylebox_override("panel", PixelUiKit.inset_stylebox(PixelUiKit.COL_SAFE_BG, PixelUiKit.COL_SAFE_BORDER))
	else:
		cell.add_theme_stylebox_override("panel", PixelUiKit.inset_stylebox(PixelUiKit.COL_CELL_BG, PixelUiKit.COL_CELL_BORDER))
	return cell


## ---- 基地视图长按拖动 ----

func _on_base_area_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_base_dragging = event.pressed
		if _base_dragging:
			_base_drag_mouse = (event as InputEventMouseButton).position
			_base_drag_view = base_view.position
	elif event is InputEventMouseMotion and _base_dragging:
		var motion := event as InputEventMouseMotion
		var target: Vector2 = _base_drag_view + motion.position - _base_drag_mouse
		target.x = clampf(target.x, BASE_VIEW_HOME.x - BASE_PAN_MAX.x, BASE_VIEW_HOME.x + BASE_PAN_MAX.x)
		target.y = clampf(target.y, BASE_VIEW_HOME.y - BASE_PAN_MAX.y, BASE_VIEW_HOME.y + BASE_PAN_MAX.y)
		base_view.position = target
