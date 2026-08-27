## settlement_page.gd —— FullHaul 表现层：结算页面（成功/失败，占位 V0）
##
## 职责：
##   结算页骨架（WORD-26 交付项 3）：
##     - RUN_SUCCEEDED / RUN_FAILED 事件驱动展示成败结果与物品去向
##       （成功携带物品 / 失败安全箱物品）
##     - RUN_SETTLED 事件驱动切换为「已结算」态（幂等 INV-09），
##       并开放「返回局外」
##
## 分层约定：
##   结果数据来自事件 payload（不读领域内部）；按钮只调用应用编排层用例。
##
## 占位说明：
##   结算明细（入库/出售/货币变动）为架构 §7 切片 8 内容，V0.1 仅展示
##   物品 id 列表（当前切片内列表为空属预期）。

extends Control
class_name SettlementPage

## 应用编排层（组合根注入）
var _orchestrator: RunFlowOrchestrator = null

@onready var result_label: Label = $%ResultLabel
@onready var result_block: ColorRect = $%ResultBlock
@onready var detail_label: Label = $%DetailLabel
@onready var settle_button: Button = $%SettleButton
@onready var back_button: Button = $%BackButton


func _ready() -> void:
	_apply_styles()
	settle_button.pressed.connect(_on_settle_button_pressed)
	back_button.pressed.connect(_on_back_button_pressed)


## 统一卡通风样式（PixelUiKit 单一来源；结算为红色主行动）。
func _apply_styles() -> void:
	PixelUiKit.style_rect_button(settle_button, PixelUiKit.COL_RED,
			PixelUiKit.COL_RED_BORDER, 30, Color(1, 0.96, 0.94))
	PixelUiKit.style_rect_button(back_button, PixelUiKit.COL_CHIP_BG,
			PixelUiKit.COL_BORDER, 30, PixelUiKit.COL_TEXT)


## 组合根（main.gd）注入编排器。
func setup(orchestrator: RunFlowOrchestrator) -> void:
	_orchestrator = orchestrator


## [RUN_SUCCEEDED] 展示撤离成功（INV-10）。
func show_success(payload: RefCounted) -> void:
	var evt := payload as DomainEvents.RunSucceeded
	result_label.text = "撤离成功"
	result_block.color = Color(0.2, 0.7, 0.3)
	if evt != null:
		detail_label.text = "对局：%s\n携带带出物品 %d 件：%s" % [
			evt.run_id, evt.carried_item_ids.size(), _format_ids(evt.carried_item_ids)]
	settle_button.disabled = false
	back_button.disabled = true


## [RUN_FAILED] 展示撤离失败（INV-11）。
func show_failure(payload: RefCounted) -> void:
	var evt := payload as DomainEvents.RunFailed
	result_label.text = "撤离失败（本局时间耗尽）"
	result_block.color = Color(0.8, 0.25, 0.25)
	if evt != null:
		detail_label.text = "对局：%s\n安全箱返回物品 %d 件：%s" % [
			evt.run_id, evt.safe_item_ids.size(), _format_ids(evt.safe_item_ids)]
	settle_button.disabled = false
	back_button.disabled = true


## [RUN_SETTLED] 切换为已结算态（幂等 INV-09）。
func mark_settled() -> void:
	settle_button.disabled = true
	back_button.disabled = false
	detail_label.text += "\n（已结算：携带/安全箱物品已入库仓库，可在局外出售）"


## 按钮回调：完成结算（RUN_SUCCEEDED/RUN_FAILED -> SETTLED）。
func _on_settle_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.settle()


## 按钮回调：返回局外（SETTLED -> OUT_OF_RUN，开启下一局）。
func _on_back_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.confirm_settled()


## 物品 id 列表展示（空列表显示占位说明）。
func _format_ids(ids: Array) -> String:
	if ids.is_empty():
		return "（本局未携带/未返回物品）"
	return "、".join(ids.map(func(id): return str(id)))
