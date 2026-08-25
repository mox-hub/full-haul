## test_main_flow_smoke.gd —— FullHaul 集成冒烟：主场景最小流程（GdUnit4）
##
## 职责：
##   实例化工程主场景 res://scenes/main.tscn（真实 Autoload：EventBus/
##   ConfigLoader + 真实组合根装配），通过模拟按钮按压黑盒驱动
##   「进入一局 -> 界面切换 -> 结算 -> 返回局外」最小流程
##   （WORD-26 验收标准 1 的无头等价验证）。
##
## 断言只读页面可见性与文案（黑盒），不触达被测对象内部字段。
##
## 注意：本用例会向全局 EventBus 订阅（页面/路由随主场景实例订阅），
## 因此全程只用一个主场景实例跑完整流程，避免跨用例订阅残留。
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/integration/test_main_flow_smoke.gd --ignoreHeadlessMode

extends GdUnitTestSuite

const MainScene := preload("res://scenes/main.tscn")


## 按路径取节点（集成测试不依赖被测脚本内部结构，仅按场景树路径取控件）
func _page(main: Node, path: String) -> Control:
	return main.get_node(path) as Control


func _button(page: Control, unique_name: String) -> Button:
	return page.get_node("%" + unique_name) as Button


func test_main_scene_minimal_flow() -> void:
	var main: Node = auto_free(MainScene.instantiate())
	add_child(main)

	## 启动完成：局外页可见，其余页面隐藏
	var lobby := _page(main, "UiRoot/LobbyPage")
	var loadout := _page(main, "UiRoot/LoadoutPage")
	var match_page := _page(main, "UiRoot/MatchPage")
	var settlement := _page(main, "UiRoot/SettlementPage")
	assert_that(lobby.visible).is_true()
	assert_that(loadout.visible).is_false()
	assert_that(match_page.visible).is_false()
	assert_that(settlement.visible).is_false()

	## —— 第一局：成功撤离 ——
	_button(lobby, "StartButton").pressed.emit()
	assert_that(loadout.visible).is_true()

	_button(loadout, "ConfirmButton").pressed.emit()
	assert_that(match_page.visible).is_true()

	for i in 5:
		_button(match_page, "SearchButton").pressed.emit()
	assert_that(_button(match_page, "ExtractButton").disabled).is_false()

	_button(match_page, "ExtractButton").pressed.emit()
	assert_that(_button(match_page, "ExtractDoneButton").disabled).is_false()

	_button(match_page, "ExtractDoneButton").pressed.emit()
	assert_that(settlement.visible).is_true()
	assert_that((settlement.get_node("%ResultLabel") as Label).text).is_equal("撤离成功")
	assert_that((settlement.get_node("%DetailLabel") as Label).text).contains("run-0001")

	_button(settlement, "SettleButton").pressed.emit()
	assert_that(_button(settlement, "BackButton").disabled).is_false()

	_button(settlement, "BackButton").pressed.emit()
	assert_that(lobby.visible).is_true()

	## —— 第二局：本局时间耗尽（失败结算分支 + 多局 runId 递增） ——
	_button(lobby, "StartButton").pressed.emit()
	_button(loadout, "ConfirmButton").pressed.emit()
	assert_that(match_page.visible).is_true()

	_button(match_page, "TimeoutButton").pressed.emit()
	assert_that(settlement.visible).is_true()
	assert_that((settlement.get_node("%ResultLabel") as Label).text).is_equal("撤离失败（本局时间耗尽）")
	assert_that((settlement.get_node("%DetailLabel") as Label).text).contains("run-0002")

	_button(settlement, "SettleButton").pressed.emit()
	_button(settlement, "BackButton").pressed.emit()
	assert_that(lobby.visible).is_true()
