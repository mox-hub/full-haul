## test_full_chain_loop.gd —— FullHaul 集成冒烟：强制功能链闭环（GdUnit4）
##
## 职责：
##   切片 9：通过工程主场景（真实 Autoload + 组合根装配）黑盒驱动
##   「进入一局 -> 搜刮 -> 携带 -> 撤离 -> 结算入库 -> 出售/购买」完整闭环，
##   验证：
##   - 搜刮携带：搜索容器后背包格内确实携带了产出的物品（携带闭环）
##   - 撤离解锁：完成 5 容器后撤离开放（INV-07）
##   - 结算入库：成功结算后携带物品进入仓库（INV-10）
##   - 出售：局外出售仓库物品货币增加（INV-12）
##   - 遥测：关键领域事件逐条留痕（切片 9 埋点，规范 6.4）
##
## 说明：
##   本用例与 test_main_flow_smoke 同为黑盒驱动（模拟按钮按压），但完整
##   覆盖到「出售/购买」环节，作为切片 9 强制功能链闭环的可操作验证记录。
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/integration/test_full_chain_loop.gd --ignoreHeadlessMode

extends GdUnitTestSuite

const MainScene := preload("res://scenes/main.tscn")


func _page(main: Node, path: String) -> Control:
	return main.get_node(path) as Control


func _button(page: Control, unique_name: String) -> Button:
	return page.get_node("%" + unique_name) as Button


## 组合根（main.gd）持有编排器，供黑盒测试经只读访问器断言领域状态。
func _orchestrator(main: Node) -> RunFlowOrchestrator:
	return main.get("_orchestrator") as RunFlowOrchestrator


func test_full_mandatory_chain_loop() -> void:
	var main: Node = auto_free(MainScene.instantiate())
	add_child(main)

	var lobby := _page(main, "UiRoot/LobbyPage")
	var loadout := _page(main, "UiRoot/LoadoutPage")
	var match_page := _page(main, "UiRoot/MatchPage")
	var settlement := _page(main, "UiRoot/SettlementPage")
	var orch := _orchestrator(main)
	assert_that(orch).is_not_null()

	## 启动完成：局外页可见，初始货币 100000（AC-21）
	assert_that(lobby.visible).is_true()
	assert_that(_orchestrator(main).current_profile().currency).is_equal(100000)

	## —— 进入一局（购买背包） ——
	_button(lobby, "StartButton").pressed.emit()
	assert_that(loadout.visible).is_true()
	## 选择并确认入场：购买 5x5 背包（2500），货币扣款
	assert_that(orch.select_backpack("backpack_5x5")).is_true()
	_button(loadout, "ConfirmButton").pressed.emit()
	assert_that(match_page.visible).is_true()
	assert_that(_orchestrator(main).current_profile().currency).is_equal(97500)

	## —— 搜刮 + 携带：5 个容器，每搜索一个即携带产出入背包 ——
	for i in 5:
		_button(match_page, "SearchButton").pressed.emit()
	assert_that(_button(match_page, "ExtractButton").disabled).is_false()  # INV-07 解锁
	assert_that(_orchestrator(main).carried_item_count()).is_equal(5)

	## —— 撤离成功 ——
	_button(match_page, "ExtractButton").pressed.emit()
	_button(match_page, "ExtractDoneButton").pressed.emit()
	assert_that(settlement.visible).is_true()
	assert_that((settlement.get_node("%ResultLabel") as Label).text).is_equal("撤离成功")

	## —— 结算入库：携带物品进入仓库（INV-10） ——
	_button(settlement, "SettleButton").pressed.emit()
	_button(settlement, "BackButton").pressed.emit()
	assert_that(lobby.visible).is_true()
	var profile := _orchestrator(main).current_profile()
	assert_that(profile.warehouse_item_ids.size()).is_equal(5)

	## —— 出售：局外出售仓库物品，货币增加（INV-12） ——
	var currency_before := profile.currency
	var sell_result := orch.sell_warehouse_item(str(profile.warehouse_item_ids[0]))
	assert_that(sell_result).is_greater_equal(1)
	assert_that(_orchestrator(main).current_profile().currency) \
		.is_equal(currency_before + sell_result)

	## —— 遥测埋点留痕（切片 9，规范 6.4：不构成产品规则来源） ——
	var telemetry: TelemetryService = orch.telemetry()
	assert_that(telemetry).is_not_null()
	assert_that(telemetry.count(DomainEvents.Events.OUT_OF_RUN_ENTERED)).is_greater_equal(2)
	assert_that(telemetry.count(DomainEvents.Events.RUN_INITIALIZED)).is_equal(1)
	assert_that(telemetry.count(DomainEvents.Events.BACKPACK_PURCHASED)).is_equal(1)
	assert_that(telemetry.count(DomainEvents.Events.CONTAINER_COMPLETED)).is_equal(5)
	assert_that(telemetry.count(DomainEvents.Events.EXTRACT_UNLOCKED)).is_equal(1)
	assert_that(telemetry.count(DomainEvents.Events.EXTRACT_STARTED)).is_equal(1)
	assert_that(telemetry.count(DomainEvents.Events.RUN_SUCCEEDED)).is_equal(1)
	assert_that(telemetry.count(DomainEvents.Events.RUN_SETTLED)).is_equal(1)
	assert_that(telemetry.count(DomainEvents.Events.WAREHOUSE_ITEM_ADDED)).is_equal(5)
	assert_that(telemetry.count(DomainEvents.Events.ITEM_SOLD)).is_equal(1)