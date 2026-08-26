## lobby_page.gd —— FullHaul 表现层：局外页面
##
## 职责：
##   局外主页（WORD-26 + 切片 9 表现层接线）：
##   - 展示当前货币（CURRENCY_CHANGED / 进入局外刷新）
##   - 展示仓库物品列表并提供「出售」入口（切片 8 Warehouse 域，INV-12）
##   - 「开始一局」只调用应用编排层用例（RunFlowOrchestrator.request_start_match）
##
## 分层约定：
##   按钮只调用应用编排层用例；界面状态由事件总线事件与编排器只读查询
##   驱动刷新，本页面不写任何领域状态。
##
## 显示时机：
##   由 PageRouter 订阅 OUT_OF_RUN_ENTERED 事件驱动显示/隐藏。

extends Control
class_name LobbyPage

## 应用编排层（组合根注入；仅调用其用例方法）
var _orchestrator: RunFlowOrchestrator = null
## 事件总线（组合根注入；订阅刷新事件）
var _bus: IEventBus = null

@onready var start_button: Button = $%StartButton
@onready var currency_label: Label = $%CurrencyLabel
@onready var warehouse_list: VBoxContainer = $%WarehouseList


func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)


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


func _on_start_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.request_start_match()


## [OUT_OF_RUN_ENTERED] 每次进入局外刷新货币与仓库。
func _on_out_of_run_entered(_payload: RefCounted) -> void:
	_refresh()


## [CURRENCY_CHANGED] 货币变动刷新。
func _on_currency_changed(_payload: RefCounted) -> void:
	_refresh()


## [WAREHOUSE_ITEM_ADDED / ITEM_SOLD] 仓库变动刷新。
func _on_warehouse_changed(_payload: RefCounted) -> void:
	_refresh()


## 刷新货币与仓库列表（编排器只读查询 + 事件数据）。
func _refresh() -> void:
	if _orchestrator == null:
		return
	var profile: PlayerProfile = _orchestrator.current_profile()
	var currency := profile.currency if profile != null else 0
	if currency_label != null:
		currency_label.text = "货币：%d" % currency
	_rebuild_warehouse(profile.warehouse_item_ids if profile != null else [])


## 重建仓库物品列表（每件一行：名称/价值 + 出售按钮）。
func _rebuild_warehouse(instance_ids: Array) -> void:
	if warehouse_list == null:
		return
	for child in warehouse_list.get_children():
		child.queue_free()
	if instance_ids.is_empty():
		warehouse_list.add_child(_make_warehouse_row("仓库：空", ""))
		return
	for instance_id in instance_ids:
		var id_str := str(instance_id)
		var row := _make_warehouse_row(id_str, id_str)
		warehouse_list.add_child(row)


## 构造一行仓库条目：左侧描述文本 + 右侧出售按钮（仅注入服务的物品可售）。
func _make_warehouse_row(text: String, instance_id: String) -> Control:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, 64)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	if instance_id != "":
		var sell := Button.new()
		sell.text = "出售"
		sell.custom_minimum_size = Vector2(160, 56)
		sell.pressed.connect(func(): _on_sell_pressed(instance_id))
		row.add_child(sell)
	return row


## 按钮回调：出售一件仓库物品（INV-12 原子事务）。
func _on_sell_pressed(instance_id: String) -> void:
	if _orchestrator == null:
		return
	_orchestrator.sell_warehouse_item(instance_id)