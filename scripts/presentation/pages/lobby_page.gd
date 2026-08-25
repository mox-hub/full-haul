## lobby_page.gd —— FullHaul 表现层：局外页面（占位 V0）
##
## 职责：
##   局外主页面骨架（WORD-26）：展示入口与占位信息，「开始一局」按钮
##   只调用应用编排层用例（RunFlowOrchestrator.request_start_match），
##   不触碰领域层。
##
## 显示时机：
##   由 PageRouter 订阅 OUT_OF_RUN_ENTERED 事件驱动显示/隐藏。
##
## 占位说明：
##   局外玩法（购买/选择背包、仓库、货币等）为架构 §7 切片 3/8 内容，
##   V0.1 仅保留入口按钮与占位说明。

extends Control
class_name LobbyPage

## 应用编排层（组合根注入；仅调用其用例方法）
var _orchestrator: RunFlowOrchestrator = null

@onready var start_button: Button = $%StartButton


func _ready() -> void:
	start_button.pressed.connect(_on_start_button_pressed)


## 组合根（main.gd）注入编排器。
func setup(orchestrator: RunFlowOrchestrator) -> void:
	_orchestrator = orchestrator


func _on_start_button_pressed() -> void:
	if _orchestrator == null:
		return
	_orchestrator.request_start_match()
