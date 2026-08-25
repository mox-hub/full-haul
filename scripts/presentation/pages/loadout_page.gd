## loadout_page.gd —— FullHaul 表现层：入场装载页面（占位 V0）
##
## 职责：
##   入场装载页骨架（WORD-26）：「确认入场」推进对局初始化、「取消」
##   返回局外；只调用应用编排层用例，不触碰领域层。
##
## 显示时机：
##   由 PageRouter 订阅 START_MATCH_REQUESTED 事件驱动显示。
##
## 占位说明：
##   背包购买/选择/扣款为架构 §7 切片 3（Profile + Loadout）内容，
##   V0.1 以占位说明代替；确认入场即以占位配置直接初始化对局。

extends Control
class_name LoadoutPage

## 应用编排层（组合根注入）
var _orchestrator: RunFlowOrchestrator = null

@onready var confirm_button: Button = $%ConfirmButton
@onready var cancel_button: Button = $%CancelButton


func _ready() -> void:
	confirm_button.pressed.connect(_on_confirm_button_pressed)
	cancel_button.pressed.connect(_on_cancel_button_pressed)


## 组合根（main.gd）注入编排器。
func setup(orchestrator: RunFlowOrchestrator) -> void:
	_orchestrator = orchestrator


func _on_confirm_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.confirm_loadout()


func _on_cancel_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.cancel_loadout()
