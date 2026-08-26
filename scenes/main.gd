## main.gd —— FullHaul 启动入口（组合根 / 表现层装配）
##
## 职责：
##   作为工程主场景与「组合根」，负责基础框架的启动引导与装配
##   （架构 §6 切片 1、WORD-26 表现层接线）：
##     1. 初始化配置加载（ConfigLoader，单一来源）；失败 -> ERROR 态展示
##     2. 组装应用编排层（RunFlowOrchestrator）与表现层（页面/路由）
##     3. 启动顶层状态机（BOOT -> OUT_OF_RUN），由事件驱动页面切换
##
## 分层约定（WORD-26）：
##   - 页面/路由只持有 RunFlowOrchestrator 与 IEventBus（适配 Autoload），
##     不触碰领域层状态机与 RunState（禁止表现层直改领域状态）。
##   - 本文件只做「装配」：依赖注入与事件接线，不含业务逻辑。

extends Node

## 应用编排层（一局流程用例入口）
var _orchestrator: RunFlowOrchestrator = null

@onready var lobby_page: LobbyPage = $%LobbyPage
@onready var loadout_page: LoadoutPage = $%LoadoutPage
@onready var match_page: MatchPage = $%MatchPage
@onready var settlement_page: SettlementPage = $%SettlementPage
@onready var router: PageRouter = $PageRouter
@onready var error_panel: Control = $%ErrorPanel
@onready var error_message: Label = $%ErrorMessage


func _ready() -> void:
	_boot_framework()


## 基础框架启动引导 + 表现层装配。
func _boot_framework() -> void:
	## 1. 加载并校验全局配置；失败 -> ERROR 态展示（规范 4.2）
	var ok := ConfigLoader.load_config()
	if not ok:
		push_error("FullHaul 启动失败：%s" % ConfigLoader.last_error)
		_show_boot_error(ConfigLoader.last_error)
		return

	print("FullHaul 基础框架启动：配置加载成功（matchDuration=%d）" % ConfigLoader.config.match_duration)

	## 2. 组装：共享一个事件总线适配器（全部事件经全局 EventBus 流转）
	var bus := EventBusAdapter.new()
	## WORD-31：数据层经 RepositoryProvider 按配置装配（memory/sqlite）；
	## 注入 RunFlowOrchestrator，表现层仍只依赖领域接口/事件总线。
	var repos := RepositoryProvider.create_set()
	## 切片 4：注入局内会话服务（RunSession 域，AC-03 双计时/完成数）。
	## 一局一实例，经共享的局内状态存储读写（禁止全局单例承载运行态，P1-3）。
	var run_state_store := _InMemoryRunStateStore.new()
	var run_session := RunSessionService.new(run_state_store, bus, ConfigLoaderAdapter.new())
	## 切片 5：注入物品与背包服务（Item & Inventory 域，AC-07/AC-08）。
	## 物品定义来自配置数据仓储（数据驱动单一来源 INV-16）；背包/安全箱
	## 两格在确认入场时按档位尺寸初始化。
	var item_inventory := ItemInventoryService.new(repos.config_data, bus)
	## 切片 6：注入容器搜索服务（Loot / Container 域，AC-04/05/06/17/18）。
	## 容器搜索子状态机驱动单个容器从 UNOPENED 到 COMPLETED；完成计数
	## 幂等（INV-06）。品质揭晓耗时读取配置单一来源（INV-16）。
	var container_search := ContainerSearchService.new(bus, ConfigLoaderAdapter.new())
	## 切片 7：注入撤离服务（Extract 域，AC-09/10/11，INV-07/08）。
	## 撤离锁定/解锁（完成数阈值）、15 秒撤离读条与总计时并行推进、
	## 成功/失败判定；撤离时长与解锁阈值读取配置单一来源（INV-16）。
	var extract_service := ExtractService.new(run_state_store, ConfigLoaderAdapter.new())
	_orchestrator = RunFlowOrchestrator.new(bus, run_state_store, ConfigLoaderAdapter.new(), repos,
		null, run_session, item_inventory, container_search, extract_service)

	## 3. 表现层注入（页面只拿编排器；需要事件的页面/路由另拿总线）
	lobby_page.setup(_orchestrator)
	loadout_page.setup(_orchestrator)
	match_page.setup(bus, _orchestrator)
	settlement_page.setup(_orchestrator)
	router.setup(bus, {
		PageRouter.PAGE_LOBBY: lobby_page,
		PageRouter.PAGE_LOADOUT: loadout_page,
		PageRouter.PAGE_MATCH: match_page,
		PageRouter.PAGE_SETTLEMENT: settlement_page,
	}, settlement_page)

	## 4. 启动顶层状态机：BOOT -> OUT_OF_RUN（事件驱动显示局外页）
	_orchestrator.start()
	print("FullHaul 基础框架就绪：进入 OUT_OF_RUN（当前页面 %s）" % router.current_page())


## 配置加载/校验失败：展示 ERROR 态页面。
func _show_boot_error(message: String) -> void:
	error_message.text = message
	error_panel.visible = true


## ---- 适配器：把领域层接口桥接到全局 Autoload 基础设施 ----

## 事件总线适配器：领域层/表现层通过它发布/订阅到全局 EventBus
class EventBusAdapter:
	extends IEventBus

	func publish(event_id: int, payload: RefCounted = null) -> void:
		EventBus.publish(event_id, payload)

	func subscribe(event_id: int, callback: Callable) -> int:
		return EventBus.subscribe(event_id, callback)

	func unsubscribe(event_id: int, sub_id: int) -> void:
		EventBus.unsubscribe(event_id, sub_id)


## 配置加载适配器：领域层通过它读取全局配置
class ConfigLoaderAdapter:
	extends IConfigLoader

	func get_config() -> GameConfig:
		return ConfigLoader.get_config()


## 内存版局内状态存储（V0.1 运行周期内；跨重启持久化按 TBD-12）
class _InMemoryRunStateStore:
	extends IRunStateStore

	var _state: RunState = null

	func read() -> RunState:
		return _state

	func write(state: RunState) -> void:
		_state = state
