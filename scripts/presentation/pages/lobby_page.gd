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
const CELL_SIZE := 132.0

## 品质色（仓库条目色条）
const RARITY_COLORS := {
	"common": Color(0.58, 0.62, 0.70),
	"uncommon": Color(0.42, 0.72, 0.38),
	"rare": Color(0.38, 0.60, 0.90),
	"epic": Color(0.66, 0.44, 0.88),
	"legendary": Color(0.95, 0.78, 0.32),
}

# ---- 像素风扁平调色板（面板/描边/强调色）----
const COL_PANEL := Color(0.125, 0.149, 0.204)
const COL_BORDER := Color(0.227, 0.259, 0.341)
const COL_CHIP_BG := Color(0.149, 0.176, 0.239)
const COL_TEXT := Color(0.91, 0.925, 0.957)
const COL_TEXT_DIM := Color(0.604, 0.647, 0.741)
const COL_GOLD := Color(0.949, 0.757, 0.306)
const COL_RED := Color(0.788, 0.31, 0.275)
const COL_RED_BORDER := Color(1.0, 0.565, 0.525)
const COL_CELL_BG := Color(0.102, 0.122, 0.169)
const COL_CELL_BORDER := Color(0.235, 0.267, 0.349)
const COL_SAFE_BG := Color(0.169, 0.102, 0.118)
const COL_SAFE_BORDER := Color(0.69, 0.283, 0.239)

## 应用编排层（组合根注入；仅调用其用例方法）
var _orchestrator: RunFlowOrchestrator = null
## 事件总线（组合根注入；订阅刷新事件）
var _bus: IEventBus = null
## Toast 隐藏定时器令牌（连点时只让最后一个定时器生效）
var _toast_token := 0

@onready var currency_chip: Button = $%CurrencyChip
@onready var warehouse_chip: Button = $%WarehouseChip
@onready var backpack_chip: Button = $%BackpackChip
@onready var currency_value: Label = $%CurrencyValue
@onready var warehouse_value: Label = $%WarehouseValue
@onready var backpack_value: Label = $%BackpackValue
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


func _ready() -> void:
	_apply_styles()
	_build_grids()
	start_button.pressed.connect(_on_start_button_pressed)
	warehouse_chip.pressed.connect(_on_warehouse_chip_pressed)
	popup_close.pressed.connect(_on_popup_close_pressed)
	garden_button.pressed.connect(func(): _on_placeholder_pressed("菜园"))
	workshop_button.pressed.connect(func(): _on_placeholder_pressed("工坊"))
	market_button.pressed.connect(func(): _on_placeholder_pressed("市场"))
	tech_button.pressed.connect(func(): _on_placeholder_pressed("科技"))


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


## [仓库属性栏] 打开仓库出售弹窗。
func _on_warehouse_chip_pressed() -> void:
	warehouse_popup.visible = true
	_rebuild_warehouse(_warehouse_ids())


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


## 刷新三属性与仓库弹窗列表（编排器只读查询 + 事件驱动）。
func _refresh() -> void:
	var profile: PlayerProfile = _orchestrator.current_profile() if _orchestrator != null else null
	if currency_value != null:
		currency_value.text = str(profile.currency if profile != null else 0)
	if warehouse_value != null:
		warehouse_value.text = str(profile.warehouse_item_ids.size() if profile != null else 0)
	if backpack_value != null:
		backpack_value.text = _offer_size_text(profile)
	if warehouse_popup != null and warehouse_popup.visible:
		_rebuild_warehouse(_warehouse_ids())


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
		empty.add_theme_color_override("font_color", COL_TEXT_DIM)
		empty.add_theme_font_size_override("font_size", 26)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		warehouse_list.add_child(empty)
		return
	for instance_id in instance_ids:
		warehouse_list.add_child(_make_warehouse_row(str(instance_id)))


## 构造一行仓库条目。
func _make_warehouse_row(instance_id: String) -> Control:
	var info := _item_info(instance_id)
	var row := PanelContainer.new()
	row.add_theme_stylebox_override("panel", _sb(Color(0.114, 0.137, 0.188), COL_BORDER, 2, 12))
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
	## 品质色条
	var rarity_bar := Panel.new()
	var rarity_color: Color = RARITY_COLORS.get(info.rarity, COL_TEXT_DIM)
	rarity_bar.add_theme_stylebox_override("panel", _sb(rarity_color, rarity_color, 0, 6))
	rarity_bar.custom_minimum_size = Vector2(14, 44)
	rarity_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(rarity_bar)
	var label := Label.new()
	label.text = "%s　价值 %d" % [info.name, info.value]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 28)
	box.add_child(label)
	var sell := Button.new()
	sell.text = "出售"
	sell.custom_minimum_size = Vector2(150, 58)
	sell.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_style_button(sell, COL_RED, COL_RED_BORDER, 12, 26, Color(1, 0.96, 0.94))
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


## ---- 像素风扁平样式 ----

func _apply_styles() -> void:
	for chip in [currency_chip, warehouse_chip, backpack_chip]:
		_style_button(chip, COL_CHIP_BG, COL_BORDER, 16, 20, COL_TEXT_DIM)
	for btn in [garden_button, workshop_button, market_button, tech_button]:
		_style_button(btn, COL_CHIP_BG, COL_BORDER, 75, 30, COL_TEXT)
	_style_button(start_button, COL_RED, COL_RED_BORDER, 120, 46, Color(1, 0.96, 0.94))
	_style_button(popup_close, COL_CHIP_BG, COL_BORDER, 14, 30, COL_TEXT)
	grid_panel.add_theme_stylebox_override("panel", _sb(COL_PANEL, COL_BORDER, 4, 20))
	popup_panel.add_theme_stylebox_override("panel", _sb(COL_PANEL, COL_BORDER, 4, 20))


func _style_button(btn: Button, bg: Color, border: Color, radius: int,
		font_size: int, font_color: Color) -> void:
	btn.add_theme_stylebox_override("normal", _sb(bg, border, 3, radius))
	btn.add_theme_stylebox_override("hover", _sb(bg.lightened(0.06), border.lightened(0.08), 3, radius))
	btn.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.12), border.darkened(0.1), 3, radius))
	btn.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	for color_key in ["font_color", "font_hover_color", "font_focus_color", "font_pressed_color"]:
		btn.add_theme_color_override(color_key, font_color)
	btn.add_theme_font_size_override("font_size", font_size)


func _sb(bg: Color, border: Color, border_w: int, radius: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.anti_aliasing = false
	return sb


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
		cell.add_theme_stylebox_override("panel", _sb(COL_SAFE_BG, COL_SAFE_BORDER, 3, 10))
	else:
		cell.add_theme_stylebox_override("panel", _sb(COL_CELL_BG, COL_CELL_BORDER, 3, 10))
	return cell
