## loadout_page.gd —— FullHaul 表现层：入场装载页面
##
## 职责：
##   入场装载页（WORD-26 + 切片 3/9 表现层接线）：
##   - 展示背包档位（BackpackOffer，数据驱动单一来源 INV-16）与当前货币
##   - 选择档位（select_backpack）、「确认入场」触发购买扣款并初始化对局
##     （Loadout 域，走 Transaction 原子性 INV-12，AC-02）
##   - 「取消」返回局外
##
## 分层约定：
##   按钮只调用应用编排层用例；货币展示经编排器只读查询 + 事件刷新。

extends Control
class_name LoadoutPage

## 应用编排层（组合根注入）
var _orchestrator: RunFlowOrchestrator = null
## 事件总线（组合根注入；货币变动刷新）
var _bus: IEventBus = null

@onready var confirm_button: Button = $%ConfirmButton
@onready var cancel_button: Button = $%CancelButton
@onready var currency_label: Label = $%CurrencyLabel
@onready var offer_list: VBoxContainer = $%OfferList

## 当前选中档位 offerId
var _selected_offer := ""


func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm_button_pressed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)


## 组合根（main.gd）注入编排器与事件总线，并加载档位列表。
func setup(bus: IEventBus, orchestrator: RunFlowOrchestrator) -> void:
	_bus = bus
	_orchestrator = orchestrator
	if _bus != null:
		_bus.subscribe(DomainEvents.Events.CURRENCY_CHANGED, _on_currency_changed)
	_rebuild_offers()
	_refresh_currency()


## 重建背包档位选择列表（读配置数据/配置加载器，单一来源 INV-16）。
func _rebuild_offers() -> void:
	if offer_list == null or _orchestrator == null:
		return
	for child in offer_list.get_children():
		child.queue_free()
	var offers := _load_offers()
	for offer_id in offers:
		var offer: Dictionary = offers[offer_id]
		var id_str := str(offer_id)
		var price := int(offer.get("price", 0))
		var size_text := "%sx%s" % [offer.get("grid_width", 0), offer.get("grid_height", 0)]
		var row := HBoxContainer.new()
		row.custom_minimum_size = Vector2(0, 88)
		var label := Label.new()
		label.text = "%s  %s（%d 货币）" % [offer.get("display_name", id_str), size_text, price]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var pick := Button.new()
		pick.text = "选择"
		pick.custom_minimum_size = Vector2(150, 72)
		pick.pressed.connect(func(): _on_offer_pressed(id_str))
		row.add_child(pick)
		offer_list.add_child(row)


## 读取背包档位（优先编排器加载的配置数据，回退 GameConfig 单一来源）。
func _load_offers() -> Dictionary:
	var loaded: Dictionary = _orchestrator.loaded_config_data()
	var offers: Dictionary = loaded.get("backpack_offers", {})
	if offers.is_empty():
		var cfg := ConfigLoader.get_config()
		offers = cfg.backpack_offers if cfg != null else {}
	return offers


## 按钮回调：选择背包档位（LOADOUT 阶段）。
func _on_offer_pressed(offer_id: String) -> void:
	if _orchestrator == null:
		return
	if _orchestrator.select_backpack(offer_id):
		_selected_offer = offer_id
		_refresh_currency()


## 按钮回调：确认入场（购买扣款 + 初始化对局）。
## 入场被拦截（余额不足等，AC-02 余额不足不得入场）时留在装载页并提示原因。
func _on_confirm_button_pressed() -> void:
	if _orchestrator == null:
		return
	## 未手动选择时：若编排器已有选择（外部/测试注入）则沿用；
	## 否则默认选择首个档位（保证既有流程可运行）
	if _selected_offer == "":
		if _orchestrator.selected_backpack_offer() == "":
			var offers := _load_offers()
			if not offers.is_empty():
				_orchestrator.select_backpack(str(offers.keys()[0]))
	var confirmed := _orchestrator.confirm_loadout()
	if not confirmed:
		_show_purchase_blocked_hint()


## 入场被拦截提示（余额不足为主因，AC-02：扣款失败留在 LOADOUT 等待重选）。
func _show_purchase_blocked_hint() -> void:
	if _orchestrator == null or currency_label == null:
		return
	var offer_id := _selected_offer \
		if _selected_offer != "" else _orchestrator.selected_backpack_offer()
	var offer: Dictionary = _load_offers().get(offer_id, {})
	var price := int(offer.get("price", 0))
	var profile: PlayerProfile = _orchestrator.current_profile()
	var currency := profile.currency if profile != null else 0
	currency_label.text = "当前货币：%d —— 余额不足，购买该背包需 %d，无法入场" \
		% [currency, price]


func _on_cancel_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.cancel_loadout()


## [CURRENCY_CHANGED] 货币变动刷新。
func _on_currency_changed(_payload: RefCounted) -> void:
	_refresh_currency()


## 刷新货币展示（编排器只读查询）。
func _refresh_currency() -> void:
	if _orchestrator == null:
		return
	var profile: PlayerProfile = _orchestrator.current_profile()
	var currency := profile.currency if profile != null else 0
	if currency_label != null:
		currency_label.text = "当前货币：%d（选择后确认即扣款）" % currency