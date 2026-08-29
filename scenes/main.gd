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
	## 物品 3D 预览模型解析：表现层经注入的回调解耦地读取物品注册态绑定
	## （ItemData.model / model_scale，INV-16 单一来源；缓存避免重复装载）
	var _item_data_cache: Dictionary = repos.config_data.load_item_data()
	ModelPreviewView.set_item_data_resolver(func(definition_id: String) -> ItemData:
		return _item_data_cache.get(definition_id, null))
	## 切片 4：注入局内会话服务（RunSession 域，AC-03 双计时/完成数）。
	## 一局一实例，经共享的局内状态存储读写（禁止全局单例承载运行态，P1-3）。
	var run_state_store := _InMemoryRunStateStore.new()
	var run_session := RunSessionService.new(run_state_store, bus, ConfigLoaderAdapter.new())
	## 切片 5：注入物品与背包服务（Item & Inventory 域，AC-07/AC-08）。
	## 物品定义来自配置数据仓储（数据驱动单一来源 INV-16）；背包/安全箱
	## 两格在确认入场时按档位尺寸初始化。
	var item_inventory := ItemInventoryService.new(repos.config_data, bus)
	## 仓库格子（局外储物空间）：8×6 运行时格子，入库物品按定义尺寸 first-fit
	## 摆放；位置为运行时状态，跨重启按入库顺序重排（位置持久化 TBD）。
	item_inventory.setup_warehouse(8, 6)
	## 切片 6：注入容器搜索服务（Loot / Container 域，AC-04/05/06/17/18）。
	## 容器搜索子状态机驱动单个容器从 UNOPENED 到 COMPLETED；完成计数
	## 幂等（INV-06）。品质揭晓耗时读取配置单一来源（INV-16）。
	var container_search := ContainerSearchService.new(bus, ConfigLoaderAdapter.new())
	## 切片 7：注入撤离服务（Extract 域，AC-09/10/11，INV-07/08）。
	## 撤离锁定/解锁（完成数阈值）、15 秒撤离读条与总计时并行推进、
	## 成功/失败判定；撤离时长与解锁阈值读取配置单一来源（INV-16）。
	var extract_service := ExtractService.new(run_state_store, ConfigLoaderAdapter.new())
	## 切片 8：注入仓库服务（Warehouse 域，AC-14/INV-12）与结算服务
	## （Settlement 域，AC-12/13，INV-09/10/11）。
	## 仓库出售走 Transaction 域原子性与防重（INV-12）；物品价值经
	## item_inventory 数据驱动定义解析（单一来源 INV-16）。
	var warehouse_service := WarehouseService.new(
		TransactionService.new(repos.run_result),
		func(instance_id: String) -> int:
			var item := item_inventory.get_item(instance_id) if item_inventory != null else null
			if item == null:
				return 0
			var def := item_inventory.get_definition(item.definition_id) if item_inventory != null else null
			return def.value if def != null else 0)
	var settlement_service := SettlementService.new(warehouse_service)
	## 切片 9：注入遥测服务（Telemetry 域，架构 §1.1 Config & Telemetry）。
	## 订阅全部领域事件做埋点（规范 6.4：不构成产品规则来源），供诊断/验证。
	## console_echo：每条事件（含表现层 UI_INTERACTED 交互）同步打印控制台日志。
	var telemetry := TelemetryService.new(bus)
	telemetry.console_echo = true
	telemetry.start()
	## 切片 3：注入入场装载服务（Loadout 域）。购买/扣款走 Transaction 域
	## 原子性（INV-12）；初始货币由编排器开局初始化（AC-21）。
	var loadout_service := LoadoutService.new(ConfigLoaderAdapter.new(),
		TransactionService.new(repos.run_result), bus)
	_orchestrator = RunFlowOrchestrator.new(bus, run_state_store, ConfigLoaderAdapter.new(), repos,
		loadout_service, run_session, item_inventory, container_search, extract_service,
		settlement_service, warehouse_service, telemetry)

	## 3. 表现层注入（页面只拿编排器；需要事件的页面/路由另拿总线）
	lobby_page.setup(bus, _orchestrator)
	loadout_page.setup(bus, _orchestrator)
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
