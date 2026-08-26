## test_page_router.gd —— FullHaul 接线测试：表现层页面路由（GdUnit4）
##
## 职责：
##   以 GdUnit4 用例覆盖 WORD-26 新增的表现层接线：
##   PageRouter 依据领域事件切换页面，页面按钮经应用编排层驱动
##   状态机，全程不出现「表现层直改领域状态」（WORD-26 验收标准 2）。
##
## 覆盖映射：
##   - 事件驱动页面切换：OUT_OF_RUN/LOADOUT/RUN_INITIALIZED/结算事件
##   - 成功/失败结算页展示与按钮态流转（RUN_SETTLED 后开放返回）
##   - HUD 撤离目标提示随完成数/解锁事件更新
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/presentation/test_page_router.gd --ignoreHeadlessMode

extends GdUnitTestSuite

const EventBusScript := preload("res://autoload/EventBus.gd")
const LobbyScene := preload("res://scenes/lobby/lobby_page.tscn")
const LoadoutScene := preload("res://scenes/lobby/loadout_page.tscn")
const MatchScene := preload("res://scenes/match/match_page.tscn")
const SettlementScene := preload("res://scenes/ui/settlement_page.tscn")

## 本地事件总线适配器
class _LocalBusAdapter:
	extends IEventBus

	var _bus: Node = null

	func _init(bus: Node) -> void:
		_bus = bus

	func publish(event_id: int, payload: RefCounted = null) -> void:
		_bus.call("publish", event_id, payload)

	func subscribe(event_id: int, callback: Callable) -> int:
		return _bus.call("subscribe", event_id, callback)

	func unsubscribe(event_id: int, sub_id: int) -> void:
		_bus.call("unsubscribe", event_id, sub_id)


## 内存态状态存储
class _InMemoryStateStore:
	extends IRunStateStore
	var _state: RunState = null

	func read() -> RunState:
		return _state

	func write(state: RunState) -> void:
		_state = state


## 假配置加载器
class _FakeConfigLoader:
	extends IConfigLoader

	func get_config() -> GameConfig:
		return GameConfig.new()


## 已装配的整棵表现层子树（页面 + 路由 + 编排器 + 本地总线）
class _Wired:
	var bus: Node = null
	var bus_adapter: _LocalBusAdapter = null
	var store: _InMemoryStateStore = null
	var orchestrator: RunFlowOrchestrator = null
	var router: PageRouter = null
	var lobby: LobbyPage = null
	var loadout: LoadoutPage = null
	var match: MatchPage = null
	var settlement: SettlementPage = null


## 装配表现层子树并挂入测试树（触发 _ready / @onready 解析）。
func _wire(suite: GdUnitTestSuite) -> _Wired:
	var w := _Wired.new()
	w.bus = suite.auto_free(EventBusScript.new())
	w.bus.call("_ready")
	w.bus_adapter = _LocalBusAdapter.new(w.bus)
	w.store = _InMemoryStateStore.new()
	w.orchestrator = RunFlowOrchestrator.new(w.bus_adapter, w.store, _FakeConfigLoader.new())

	w.lobby = suite.auto_free(LobbyScene.instantiate())
	w.loadout = suite.auto_free(LoadoutScene.instantiate())
	w.match = suite.auto_free(MatchScene.instantiate())
	w.settlement = suite.auto_free(SettlementScene.instantiate())
	suite.add_child(w.lobby)
	suite.add_child(w.loadout)
	suite.add_child(w.match)
	suite.add_child(w.settlement)

	w.lobby.setup(w.bus_adapter, w.orchestrator)
	w.loadout.setup(w.bus_adapter, w.orchestrator)
	w.match.setup(w.bus_adapter, w.orchestrator)
	w.settlement.setup(w.orchestrator)

	w.router = suite.auto_free(PageRouter.new())
	suite.add_child(w.router)
	w.router.setup(w.bus_adapter, {
		PageRouter.PAGE_LOBBY: w.lobby,
		PageRouter.PAGE_LOADOUT: w.loadout,
		PageRouter.PAGE_MATCH: w.match,
		PageRouter.PAGE_SETTLEMENT: w.settlement,
	}, w.settlement)
	return w


## [PageRouter] 事件驱动页面切换 + 成功结算流程（WORD-26 验收 1/2）
func test_event_driven_page_switching_success() -> void:
	var w := _wire(self)

	## 启动 -> 局外页可见
	w.orchestrator.start()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_LOBBY)

	## 局外页按钮 -> 请求开始 -> 装载页
	w.lobby.start_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_LOADOUT)

	## 装载页确认 -> 局内主页（RUN_INITIALIZED 事件驱动）
	w.loadout.confirm_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_MATCH)
	assert_that(w.match.hud.objective_label.text).contains("0/5")

	## 局内搜索（占位）x5 -> 撤离解锁，撤离按钮开放，HUD 提示更新
	for i in 5:
		w.match.search_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_MATCH)
	assert_that(w.match.extract_button.disabled).is_false()
	assert_that(w.match.hud.objective_label.text).contains("已解锁")

	## 开始撤离 -> 撤离读条（视觉）可见，成功按钮开放
	w.match.extract_button.pressed.emit()
	assert_that(w.match.hud.extract_bar.visible).is_true()
	assert_that(w.match.extract_done_button.disabled).is_false()

	## 撤离读条完成（占位） -> 结算页（成功）
	w.match.extract_done_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_SETTLEMENT)
	assert_that(w.settlement.result_label.text).is_equal("撤离成功")
	assert_that(w.settlement.settle_button.disabled).is_false()
	assert_that(w.settlement.back_button.disabled).is_true()

	## 完成结算 -> 已结算态，返回局外开放
	w.settlement.settle_button.pressed.emit()
	assert_that(w.settlement.settle_button.disabled).is_true()
	assert_that(w.settlement.back_button.disabled).is_false()

	## 返回局外 -> 局外页（事件驱动）
	w.settlement.back_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_LOBBY)


## [PageRouter] 失败结算分支：局内超时 -> 失败结算页
func test_event_driven_page_switching_failure() -> void:
	var w := _wire(self)

	w.orchestrator.start()
	w.lobby.start_button.pressed.emit()
	w.loadout.confirm_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_MATCH)

	## 本局时间耗尽（占位） -> 结算页（失败）
	w.match.timeout_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_SETTLEMENT)
	assert_that(w.settlement.result_label.text).is_equal("撤离失败（本局时间耗尽）")

	w.settlement.settle_button.pressed.emit()
	w.settlement.back_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_LOBBY)
	assert_that(w.orchestrator.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)


## [PageRouter] 取消装载返回局外由事件驱动（OUT_OF_RUN_ENTERED 二次广播）
func test_loadout_cancel_returns_to_lobby() -> void:
	var w := _wire(self)

	w.orchestrator.start()
	w.lobby.start_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_LOADOUT)

	w.loadout.cancel_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_LOBBY)
	assert_that(w.orchestrator.current_phase()).is_equal(RunState.Phase.OUT_OF_RUN)


## [PageRouter] 多局复位：第二局回到局内页时 HUD 目标提示复位（INV-14）
func test_second_run_hud_reset() -> void:
	var w := _wire(self)

	## 第一局走完
	w.orchestrator.start()
	w.lobby.start_button.pressed.emit()
	w.loadout.confirm_button.pressed.emit()
	for i in 5:
		w.match.search_button.pressed.emit()
	w.match.extract_button.pressed.emit()
	w.match.extract_done_button.pressed.emit()
	w.settlement.settle_button.pressed.emit()
	w.settlement.back_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_LOBBY)

	## 第二局：HUD 提示复位为 0/5，撤离按钮重新锁定
	w.lobby.start_button.pressed.emit()
	w.loadout.confirm_button.pressed.emit()
	assert_that(w.router.current_page()).is_equal(PageRouter.PAGE_MATCH)
	assert_that(w.match.hud.objective_label.text).contains("0/5")
	assert_that(w.match.extract_button.disabled).is_true()
	assert_that(w.match.hud.extract_bar.visible).is_false()
