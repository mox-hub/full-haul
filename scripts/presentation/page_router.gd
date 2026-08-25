## page_router.gd —— FullHaul 表现层：页面路由器
##
## 职责：
##   订阅领域事件并驱动页面切换（WORD-26 交付项 1/3）：
##     - OUT_OF_RUN_ENTERED  -> 局外页
##     - START_MATCH_REQUESTED -> 入场装载页
##     - RUN_INITIALIZED     -> 局内主页
##     - RUN_SUCCEEDED / RUN_FAILED -> 结算页（成功/失败）
##     - RUN_SETTLED         -> 结算页（已结算态）
##
## 分层约定：
##   页面切换完全由事件总线上的领域事件驱动（架构 §2.3 / §3），
##   路由器不调用状态机、不读写 RunState。
##
## 事件 -> 页面映射说明：
##   状态机的全部「页面可见」阶段入口均有对应事件（BOOT->OUT_OF_RUN、
##   取消装载/结算确认返回局外同样广播 OUT_OF_RUN_ENTERED，见
##   top_level_state_machine.gd WORD-26 注记）；RUN_INIT 紧随
##   RUN_INITIALIZED 事件同步完成初始化，局内页由该事件切入。

extends Node
class_name PageRouter

## 页面表：key -> Control（组合根注入，见 PAGE_* 常量）
var _pages: Dictionary = {}
## 事件总线（组合根注入）
var _bus: IEventBus = null
## 结算页引用（事件 payload 转发用）
var _settlement_page: SettlementPage = null


const PAGE_LOBBY := "lobby"
const PAGE_LOADOUT := "loadout"
const PAGE_MATCH := "match"
const PAGE_SETTLEMENT := "settlement"


## 组合根（main.gd）注入页面表并订阅事件。
func setup(bus: IEventBus, pages: Dictionary, settlement_page: SettlementPage) -> void:
	_bus = bus
	_pages = pages
	_settlement_page = settlement_page
	_bus.subscribe(DomainEvents.Events.OUT_OF_RUN_ENTERED, _on_out_of_run_entered)
	_bus.subscribe(DomainEvents.Events.START_MATCH_REQUESTED, _on_start_match_requested)
	_bus.subscribe(DomainEvents.Events.RUN_INITIALIZED, _on_run_initialized)
	_bus.subscribe(DomainEvents.Events.RUN_SUCCEEDED, _on_run_succeeded)
	_bus.subscribe(DomainEvents.Events.RUN_FAILED, _on_run_failed)
	_bus.subscribe(DomainEvents.Events.RUN_SETTLED, _on_run_settled)
	_hide_all()


## 当前显示的页面 key（测试断言用）。
func current_page() -> String:
	for key in _pages:
		var page: Control = _pages[key]
		if page.visible:
			return key
	return ""


## [OUT_OF_RUN_ENTERED] -> 局外页
func _on_out_of_run_entered(_payload: RefCounted) -> void:
	show_page(PAGE_LOBBY)


## [START_MATCH_REQUESTED] -> 入场装载页
func _on_start_match_requested(_payload: RefCounted) -> void:
	show_page(PAGE_LOADOUT)


## [RUN_INITIALIZED] -> 局内主页
func _on_run_initialized(_payload: RefCounted) -> void:
	show_page(PAGE_MATCH)


## [RUN_SUCCEEDED] -> 结算页（成功）
func _on_run_succeeded(payload: RefCounted) -> void:
	if _settlement_page != null:
		_settlement_page.show_success(payload)
	show_page(PAGE_SETTLEMENT)


## [RUN_FAILED] -> 结算页（失败）
func _on_run_failed(payload: RefCounted) -> void:
	if _settlement_page != null:
		_settlement_page.show_failure(payload)
	show_page(PAGE_SETTLEMENT)


## [RUN_SETTLED] -> 结算页（已结算态）
func _on_run_settled(_payload: RefCounted) -> void:
	if _settlement_page != null:
		_settlement_page.mark_settled()
	show_page(PAGE_SETTLEMENT)


## 显示指定页面（其余隐藏）。
func show_page(key: String) -> void:
	for page_key in _pages:
		var page: Control = _pages[page_key]
		page.visible = (page_key == key)


func _hide_all() -> void:
	for page_key in _pages:
		var page: Control = _pages[page_key]
		page.visible = false
