## run_flow_orchestrator.gd —— FullHaul 应用编排层：一局流程编排器
##
## 职责：
##   承载 V0.1 玩法验证闭环的用例编排（架构 §3 应用编排层、§6 切片 9 的
##   表现层接线前置）：持有顶层状态机，向表现层暴露「用例级」入口，
##   并通过事件总线广播领域事件驱动界面切换。
##
## 分层约定（架构 §3，WORD-26）：
##   - 表现层（页面/按钮）只调用本编排器的用例方法，不直接触碰领域层
##     状态机与 RunState（禁止表现层直改领域状态）。
##   - 本编排器只依赖领域层接口（IEventBus/IRunStateStore/IConfigLoader）
##     与 TopLevelStateMachine 的公开转移入口。
##
## V0.1 占位说明：
##   - 「完成容器」「总时间耗尽」在 V0.1 由占位用例直接触发转移；真实的
##     逐件揭晓计时由 Loot 域切片 6 接入，双计时并行推进由 Extract 域切片 7
##     接入（tick_extraction）。同刻计时优先级为规范 TBD-04，依赖处停工提问，
##     本层不私自补默认值。
##   - Loadout 域（购买/选择/扣款，切片 3）已接入：确认入场时经 LoadoutService
##     购买扣款（走 Transaction 域原子性）并落库局外账户；未注入 LoadoutService
##     时回退到占位行为（直接初始化对局），保证既有流程可运行。

extends RefCounted
class_name RunFlowOrchestrator

## 注入的事件总线（驱动界面切换的唯一通道）
var _bus: IEventBus = null
## 注入的局内状态存储
var _store: IRunStateStore = null
## 注入的配置加载器（单一来源 INV-16）
var _config_loader: IConfigLoader = null
## 注入的仓储集合（WORD-31 数据层接线；null 表示不接线，回退纯内存运行）
var _repos: RepositorySet = null
## 注入的入场装载服务（切片 3 Loadout 域；null 表示未接线，回退占位行为）
var _loadout_service: ILoadoutService = null
## 注入的局内会话服务（切片 4 RunSession 域；null 表示未接线，回退占位行为）
var _run_session_service: IRunSessionService = null
## 注入的物品与背包服务（切片 5 Item & Inventory 域；null 表示未接线，
## 回退占位行为）
var _item_inventory_service: IItemInventoryService = null
## 注入的容器搜索服务（切片 6 Loot / Container 域；null 表示未接线，
## 回退占位行为）
var _container_search_service: IContainerSearchService = null
## 注入的撤离服务（切片 7 Extract 域；null 表示未接线，回退占位行为）
var _extract_service: IExtractService = null
## 注入的结算服务（切片 8 Settlement 域；null 表示未接线，回退占位行为）
var _settlement_service: ISettlementService = null
## 注入的仓库服务（切片 8 Warehouse 域；null 表示未接线，回退占位行为）
var _warehouse_service: IWarehouseService = null
## 注入的遥测服务（切片 9 Telemetry 域；null 表示未接线，仅不埋点）
var _telemetry: ITelemetryService = null
## 顶层状态机（领域层，编排器内部持有）
var _sm: TopLevelStateMachine = null

## 运行序号（生成 runId，保证一局一 id，INV-14 多局隔离）
var _run_seq := 0

## 本次入场装载选定的背包档位 offerId（Loadout 页在 LOADOUT 阶段选择）
var _selected_offer_id := ""

## 局开始加载的配置数据（IConfigDataRepository 读取；供表现层只读查询）
var _loaded_config_data: Dictionary = {}

## 本局终局结果（RUN_SUCCEEDED/RUN_FAILED 转移时记录；结算时 SETTLED 已覆盖
## 阶段信息，故在此留存成败，供存档写入）
var _last_run_outcome := ""

## 占位搜索序号（切片 6：占位「完成容器」也走 Loot 域，登记占位容器，
## 使完成数统计与容器搜索域一致）
var _placeholder_seq := 0

## 本局地图容器计划（AC-17 核心搜刮图形化：对局场景内的可操作容器实体来源）。
## 每局入场时按配置生成 [{container_id, type_id, display_name, tier,
## grid_width, grid_height}]；容器数量读取 GameConfig（INV-16 单一来源）。
var _match_containers: Array = []

## 物品概率系统（搜索系统子系统：容器产出按品质×类型加权随机抽取）。
## 权重来自容器绑定（ContainerData.rarity_weights/category_weights），
## 未绑定时回退共享 tier 权重表；池/权重不可用时回退轮转选取。
var _loot := ItemProbabilitySystem.new()

## 物品概率系统的候选定义池（ItemDefinition 数组；懒加载自仓储，
## ItemData 资源优先、字典配置回退）
var _item_pool: Array = []

## 容器 Resource 注册态缓存（container_id -> ContainerData，懒加载）
var _container_data: Dictionary = {}

## 容器搜索分步流程的物品计划（container_id -> Array[Dictionary]：
## [{instance_id, definition_id, rarity, value, size, pos}]）。物品身份只在
## 编排器侧保管，表现层经 reveal/finish 用例逐件领取（INV-05 蒙版态不泄露）。
## 新一局开始时随容器计划一并重置。
var _container_item_plans: Dictionary = {}


func _init(bus: IEventBus, state_store: IRunStateStore, config_loader: IConfigLoader,
		repositories: RepositorySet = null, loadout_service: ILoadoutService = null,
		run_session_service: IRunSessionService = null,
		item_inventory_service: IItemInventoryService = null,
		container_search_service: IContainerSearchService = null,
		extract_service: IExtractService = null,
		settlement_service: ISettlementService = null,
		warehouse_service: IWarehouseService = null,
		telemetry_service: ITelemetryService = null) -> void:
	_bus = bus
	_store = state_store
	_config_loader = config_loader
	_repos = repositories
	_loadout_service = loadout_service
	_run_session_service = run_session_service
	_item_inventory_service = item_inventory_service
	_container_search_service = container_search_service
	_extract_service = extract_service
	_settlement_service = settlement_service
	_warehouse_service = warehouse_service
	_telemetry = telemetry_service
	_sm = TopLevelStateMachine.new(bus, state_store, config_loader,
		loadout_service, run_session_service, container_search_service, extract_service,
		settlement_service)


## 启动：BOOT -> OUT_OF_RUN（主场景引导完成后调用一次）。
## WORD-31：接入数据层后，开局加载配置数据（IConfigDataRepository）。
## 切片 3：开局初始化局外账户（新档位档案写入初始货币，INV-16/AC-21）。
func start() -> void:
	_sm.boot()
	_sm.on_boot_ok()
	_load_config_data()
	_ensure_initial_profile()


## ---- 局外 / 入场装载 ----

## 用例：请求开始一局（OUT_OF_RUN -> LOADOUT）。
func request_start_match() -> void:
	_sm.on_start_match_requested()


## 用例：在 LOADOUT 阶段选择背包档位（切片 3 Loadout 域）。
## 注入 LoadoutService 时校验档位存在；未注入时仅记录选择。
## 返回是否选择成功。
func select_backpack(offer_id: String) -> bool:
	if _loadout_service != null:
		if _loadout_service.get_backpack_offer(offer_id).is_empty():
			return false
	_selected_offer_id = offer_id
	return true


## 用例：确认入场装载（LOADOUT -> RUN_INIT -> IN_RUN_LOCKED）。
## 返回是否入场成功（false 表示被拦截，留在 LOADOUT）。
## 切片 3：注入 LoadoutService 时，确认入场即购买/扣款所选背包（走 Transaction
## 域原子性，INV-12）并落库局外账户；扣款失败（余额不足等）则留在 LOADOUT。
## 修复（AC-02/AC-21）：入场购买为「每局一次」——事务引用使用本局 runId，
## 同一档位跨局入场各自扣款（连续购买与开局），余额不足一律不得入场；
## 同局重复确认被 LOADOUT 阶段守卫与事务防重双重拦截。此前「档案已持有
## 档位则跳过购买」的路径会绕过货币校验，已移除。
## 未注入时回退占位行为（直接初始化对局）。
## WORD-31：对局初始化后写入运行时快照（IRunSnapshotRepository）。
func confirm_loadout() -> bool:
	## 阶段守卫：仅在 LOADOUT 阶段可确认（重复确认/局外误调不重复扣款，AC-02）
	if _sm.current_phase() != RunState.Phase.LOADOUT:
		return false
	var run_id := "run-%04d" % (_run_seq + 1)
	if _loadout_service != null:
		var profile := _load_profile()
		if profile == null:
			return false
		## 每局入场强制购买扣款（ref=runId：跨局可购、同局防重，AC-02）
		if not _loadout_service.purchase_backpack(profile, _selected_offer_id, run_id):
			## 购买/扣款失败（余额不足等）：留在 LOADOUT，等待重新选择（AC-02）
			return false
		if _repos != null and _repos.profile != null:
			_repos.profile.save(profile)
	_run_seq += 1
	## 切片 6：新一局开始清空上局容器登记（INV-14 多局隔离）
	if _container_search_service != null:
		_container_search_service.reset()
	## 生成本局地图容器计划（须先于 RUN_INITIALIZED 事件：表现层在事件回调中
	## 依此重建地图容器实体，AC-17）
	_build_match_containers()
	## 切片 5：绑定本局背包 + 安全箱格子（尺寸单一来源 INV-16）。
	## 须先于 RUN_INITIALIZED 事件：事件回调里表现层按领域格子重建背包/
	## 安全箱画布，事件后才建格会让页面拿到 null 空过刷新（格底不显示）。
	_setup_inventory_grids()
	_sm.on_loadout_confirmed(run_id)
	if _loadout_service != null:
		## 确认绑定本局背包（购买已成功；绑定校验应通过）
		_loadout_service.confirm_loadout(_store.read(), _selected_offer_id, run_id)
	## V0.1 对局初始化为同步完成（无异步加载），立即进入局内锁定态
	_sm.on_run_init_ok()
	_persist_run_snapshot()
	return true


## 用例：取消入场装载（LOADOUT -> OUT_OF_RUN）。
func cancel_loadout() -> void:
	_sm.on_loadout_cancelled()


## ---- 局内（探索搜集 / 撤离）----

## 用例：推进本局全局计时（总时间，切片 4 RunSession 域双计时之一）。
## 全局计时耗尽（总时间=0）时转移到 RUN_FAILED（INV-07/08）。
## 返回是否本次发生了全局计时耗尽（已进入 RUN_FAILED）。
## 注：表现层计时循环（_process/timer）只调用本用例推进，不直改领域状态。
func tick_match_time(delta_seconds: float) -> bool:
	var state: RunState = _store.read()
	if state != null and float(state.remaining_match_time) - delta_seconds <= 0.0:
		## 本帧即将超时：先快照背包/安全箱两份清单再转移（状态机在转移瞬间
		## 即发布 RUN_FAILED，payload 需带上安全箱清单，INV-11）
		_snapshot_inventory_both()
	return _sm.tick_match_time(delta_seconds)


## 用例（占位）：完成一个必搜容器（IN_RUN_* 内有效）。
## 返回完成后累计的完成容器数（供 HUD 展示）；局外调用返回 -1。
## 切片 6：注入 ContainerSearchService 时，占位搜索同样走 Loot 域——登记并
## 完成一个占位容器，使完成数统计（INV-06 幂等）与容器搜索域保持一致。
func complete_container_placeholder() -> int:
	var state: RunState = _store.read()
	if state == null:
		return -1
	if not _in_run_phase():
		return -1
	if _container_search_service != null:
		_placeholder_seq += 1
		var ph_container := "placeholder-%03d" % _placeholder_seq
		var ph_item := "ph-%03d" % _placeholder_seq
		_container_search_service.open_container(ph_container, 1, [ph_item])
		_container_search_service.start_reveal(ph_container, ph_item, "common")
		_container_search_service.complete_reveal(ph_container, ph_item,
			"placeholder-def", "common", 10, Vector2i.ONE)
	_sm.on_container_completed()
	_persist_run_snapshot()
	return _store.read().completed_container_count


## ---- 局内（容器搜索 / Loot 域，切片 6）----

## 用例：打开一个容器进入搜索（IN_RUN_* 内有效，INV-05）。
## 注入 ContainerSearchService 时打开容器（item_instance_ids 可选）；
## 返回是否打开成功。
func open_container(container_id: String, item_count: int, item_instance_ids: Array = []) -> bool:
	if _container_search_service == null:
		return false
	if not _in_run_phase():
		return false
	return _container_search_service.open_container(container_id, item_count, item_instance_ids)


## 用例：开始揭晓容器内一件物品（品质决定耗时）。
func start_reveal(container_id: String, instance_id: String, rarity: String) -> bool:
	if _container_search_service == null:
		return false
	if not _in_run_phase():
		return false
	return _container_search_service.start_reveal(container_id, instance_id, rarity)


## 用例：一件物品揭晓完成。
## 返回是否本次揭晓使容器首次完成（INV-06）：首次完成时经顶层状态机
## 更新完成数并做撤离解锁阈值判定（INV-07）。
func complete_reveal(container_id: String, instance_id: String, definition_id: String,
		rarity: String, value: int, size: Vector2i) -> bool:
	if _container_search_service == null:
		return false
	if not _in_run_phase():
		return false
	var newly_completed := _container_search_service.complete_reveal(
		container_id, instance_id, definition_id, rarity, value, size)
	if newly_completed:
		_sm.on_container_completed()
		_persist_run_snapshot()
	return newly_completed


## 用例：把一件已揭晓物品携带入背包格子（切片 9 表现层接线「携带」）。
## 经 ItemInventoryService 创建物品实例并放置到背包格子首个空位
## （INV-01 唯一归属 / INV-04 格子合法；尺寸单一来源 INV-16）。
## 返回是否成功携带；未注入 ItemInventoryService / 背包格未初始化 / 背包满
## 时返回 false（不影响容器完成计数）。
func carry_revealed_item(instance_id: String, definition_id: String,
		size: Vector2i) -> bool:
	if _item_inventory_service == null:
		return false
	if not _in_run_phase():
		return false
	var item: ItemInstance = _item_inventory_service.create_item(instance_id, definition_id)
	if item == null:
		return false
	var grid: GridInventory = _item_inventory_service.get_grid(GridInventory.OwnerType.BACKPACK)
	if grid == null:
		return false
	var at := _first_free_slot(grid, size)
	if at == Vector2i(-1, -1):
		return false
	return _item_inventory_service.place_item(instance_id, GridInventory.OwnerType.BACKPACK, at)


## 用例（占位→真携带）：完成一个必搜容器并把产出物品携带入背包（IN_RUN_* 内有效）。
## container_id 指定要搜索的地图容器（来自本局容器计划 match_containers）；
## 留空则自动选取计划中下一个未完成容器；无可用计划时回退占位容器。
## 已完成的容器不重复搜索、不重复携带物品（INV-06 幂等，返回当前计数）。
## 切片 9 表现层接线：搜索不再只是「完成计数」，而是登记容器 -> 打开 ->
## 逐件揭晓 -> 把揭晓物品携带入背包格子 -> 完成容器计数。
## 未注入 ContainerSearchService / ItemInventoryService 时回退到纯计数占位
## （既有流程不受影响）。
## V2：容器内物品多件化（数量/形状来自配置与物品定义，first-fit 摆入容器
## 网格），内部改走 container_search_plan -> reveal/finish -> carry 链，
## 对外返回契约不变（completed_count / carried_count）。
func search_and_carry_container(container_id: String = "") -> Dictionary:
	var state: RunState = _store.read()
	if state == null:
		return {}
	if not _in_run_phase():
		return {}
	if _container_search_service == null or _item_inventory_service == null:
		var count := complete_container_placeholder()
		return {"completed_count": count, "carried_count": 0}
	var target := container_id
	if target == "":
		target = _next_uncompleted_container()
		if target == "":
			_placeholder_seq += 1
			target = "search-%03d" % _placeholder_seq
	## 已完成容器：不重复搜索/携带（幂等 INV-06）
	if _container_search_service.is_container_completed(target):
		return {"completed_count": _store.read().completed_container_count,
			"carried_count": 0}
	var plan := container_search_plan(target)
	if plan.is_empty():
		return {"completed_count": _store.read().completed_container_count,
			"carried_count": 0}
	var carried := 0
	for it: Dictionary in _container_item_plans.get(target, []):
		var revealed := reveal_container_item(target, str(it.get("instance_id", "")))
		if revealed.is_empty():
			continue
		var size: Vector2i = it.get("size", Vector2i.ONE)
		if carry_revealed_item(str(it.get("instance_id", "")),
				str(it.get("definition_id", "")), size):
			carried += 1
		finish_reveal_container_item(target, str(it.get("instance_id", "")))
	return {"completed_count": _store.read().completed_container_count, "carried_count": carried}


## ---- 容器搜索分步用例（搜索弹窗：蒙版 -> 按品质转速揭晓 -> 手动搬运）----
## 身份信息（definition_id/rarity/value）只在编排器侧计划表保管；表现层经
## reveal（拿品质与耗时定转速）/ finish（揭晓身份）逐步领取，蒙版态不泄露
## （INV-05）。未搬运的物品实例不注册，关闭弹窗即废弃（不入背包/安全箱）。

## 用例：打开容器进入搜索（MASKED）。返回给表现层的计划摘要：
## {container_id, item_count, instance_ids, blocks: [{pos, size}]}——只含
## 数量与占格形状/位置，不含身份。已完成/重复打开返回既有计划的摘要
## （表现层重开弹窗内容一致）。
func container_search_plan(container_id: String) -> Dictionary:
	var state: RunState = _store.read()
	if state == null or not _in_run_phase():
		return {}
	if _container_search_service == null:
		return {}
	if container_id == "":
		container_id = _next_uncompleted_container()
	if container_id == "" or _container_search_service.is_container_completed(container_id):
		return {}
	if _container_item_plans.has(container_id):
		return _container_plan_summary(container_id)
	var entry := _container_plan_entry(container_id)
	if entry.is_empty():
		return {}
	var items := _plan_container_items(entry, state)
	if items.is_empty():
		return {}
	var ids: Array = []
	var sizes: Array = []
	for it: Dictionary in items:
		ids.append(it.get("instance_id", ""))
		sizes.append(it.get("size", Vector2i.ONE))
	_container_search_service.register_container(container_id, _container_type_id(container_id))
	_container_search_service.open_container(container_id, items.size(), ids, sizes)
	_container_item_plans[container_id] = items
	return _container_plan_summary(container_id)


## 用例：开始揭晓一件物品（REVEALING）。返回 {rarity, wait_time}——品质
## 决定揭晓耗时（配置单一来源 INV-16），表现层据此确定转圈速度。
func reveal_container_item(container_id: String, instance_id: String) -> Dictionary:
	if _container_search_service == null or not _in_run_phase():
		return {}
	var info := _plan_item_info(container_id, instance_id)
	if info.is_empty():
		return {}
	if not _container_search_service.start_reveal(container_id, instance_id,
			str(info.get("rarity", "common"))):
		return {}
	return {"rarity": info.get("rarity", "common"),
		"wait_time": _reveal_wait_seconds(str(info.get("rarity", "common")))}


## 用例：一件物品揭晓完成（表现层转圈计时结束后调用）。返回该物品的完整
## 展示信息（definition_id/rarity/value/size/newly_completed），表现层据此刻
## 把蒙版替换为 3D 物品；首次完成时内部推进容器计数与撤离解锁（INV-06/07）。
func finish_reveal_container_item(container_id: String, instance_id: String) -> Dictionary:
	if _container_search_service == null or not _in_run_phase():
		return {}
	var info := _plan_item_info(container_id, instance_id)
	if info.is_empty():
		return {}
	var newly := complete_reveal(container_id, instance_id,
		str(info.get("definition_id", "")), str(info.get("rarity", "common")),
		int(info.get("value", 0)), info.get("size", Vector2i.ONE))
	info["newly_completed"] = newly
	## 补展示名（表现层揭晓块 tooltip 用；定义来自配置单一来源 INV-16）
	var defs: Dictionary = _loaded_config_data.get("item_definitions", {})
	var def: Dictionary = defs.get(str(info.get("definition_id", "")), {})
	info["name"] = str(def.get("name", ""))
	return info


## 用例：把一件已揭晓物品放入背包/安全箱格子（搜索弹窗拖拽搬运）。
## 实例未注册时先按计划注册（未搬运的物品到此才落地）；已放置的走跨格移动
## （INV-04 校验，失败保持原状）。
func stow_revealed_item(instance_id: String, owner: GridInventory.OwnerType,
		at: Vector2i) -> bool:
	if _item_inventory_service == null or not _in_run_phase():
		return false
	var info := _pending_item_info(instance_id)
	if info.is_empty():
		return false
	var item: ItemInstance = _item_inventory_service.get_item(instance_id)
	if item == null:
		item = _item_inventory_service.create_item(instance_id, str(info.get("definition_id", "")))
		if item == null:
			return false
	if item.location == ItemInstance.Location.NONE:
		return _item_inventory_service.place_item(instance_id, owner, at)
	return _item_inventory_service.move_item(instance_id, owner, at)


## 查询容器计划摘要（表现层刷新复读；无计划返回空）。
func container_plan_summary(container_id: String) -> Dictionary:
	if not _container_item_plans.has(container_id):
		return {}
	return _container_plan_summary(container_id)


## 查询一件待搬运物品的展示信息（跨容器扫计划表；无返回空）。
func pending_item_info(instance_id: String) -> Dictionary:
	return _pending_item_info(instance_id)


## 撤离落定/结算后把入库物品摆入仓库格子（first-fit；仓库格未初始化或
## 放不下时跳过位置记录——物品账本仍以 warehouse_item_ids 为准）。
func deposit_items_to_warehouse(instance_ids: Array) -> void:
	for instance_id: String in instance_ids:
		ensure_warehouse_placement(str(instance_id))


## 用例：确保一件仓库物品已摆入仓库格子（结算入库时逐件调用；账本里已有
## 但缺位置的——如外部登记的种子物品——渲染时惰性补位）。返回顶左格坐标；
## 仓库格未初始化/放不下返回 (-1,-1)。实例未知（无实例/定义）只给 1x1 坐标
## 供表现层画占位块，不落实例。
func ensure_warehouse_placement(instance_id: String) -> Vector2i:
	if _item_inventory_service == null:
		return Vector2i(-1, -1)
	var grid: GridInventory = _item_inventory_service.get_grid(GridInventory.OwnerType.WAREHOUSE)
	if grid == null:
		return Vector2i(-1, -1)
	var item: ItemInstance = _item_inventory_service.get_item(instance_id)
	var size := Vector2i.ONE
	if item != null:
		var def := _item_inventory_service.get_definition(item.definition_id)
		if def != null:
			size = def.size()
	if item != null and item.location == ItemInstance.Location.WAREHOUSE:
		return grid.position_of(instance_id)
	var at := _first_free_slot(grid, size)
	if at == Vector2i(-1, -1):
		return at
	if item == null:
		return at
	if item.location == ItemInstance.Location.NONE:
		_item_inventory_service.place_item(instance_id, GridInventory.OwnerType.WAREHOUSE, at)
	else:
		_item_inventory_service.move_item(instance_id, GridInventory.OwnerType.WAREHOUSE, at)
	return at


## 用例：仓库内拖拽重排一件物品（INV-04 校验，失败保持原位）。
## 仓库为局外空间，不做局内阶段守卫。
func move_warehouse_item(instance_id: String, at: Vector2i) -> bool:
	if _item_inventory_service == null:
		return false
	var item: ItemInstance = _item_inventory_service.get_item(instance_id)
	if item == null or item.location != ItemInstance.Location.WAREHOUSE:
		return false
	return _item_inventory_service.move_item(instance_id, GridInventory.OwnerType.WAREHOUSE, at)


## 为容器生成物品计划：经物品概率系统（搜索系统子系统）按「品质 × 类型」
## 权重加权随机抽取——权重取容器绑定（ContainerData），未绑定回退共享 tier
## 权重表；池/权重不可用时回退按本局进度轮转（确定性）。数量读配置
## container_item_count_range（INV-16），逐件 first-fit 摆入容器网格（临时
## GridInventory 承载校验）；放不下的物品截断（蒙版块与最终揭晓逐件一致）。
func _plan_container_items(entry: Dictionary, state: RunState) -> Array:
	var gw := maxi(int(entry.get("grid_width", 3)), 1)
	var gh := maxi(int(entry.get("grid_height", 3)), 1)
	var container_id := str(entry.get("container_id", ""))
	var grid := GridInventory.new("plan-%s" % container_id, GridInventory.OwnerType.SAFE, gw, gh)
	var items: Array = []
	var start_index := _container_search_service.completed_container_count()
	var weights := _loot_weights_for(entry)
	for i in _container_item_count(start_index):
		var def := _loot_pick_definition(entry, weights, start_index + i)
		var size := Vector2i(maxi(int(def.get("width", 1)), 1), maxi(int(def.get("height", 1)), 1))
		var pos := _first_free_slot(grid, size)
		if pos == Vector2i(-1, -1):
			break
		grid.place("plan-%d" % i, size, pos)
		items.append({
			"instance_id": "%s-%s-item-%d" % [state.run_id, container_id, i + 1],
			"definition_id": str(def.get("definition_id", "item_0001")),
			"rarity": str(def.get("rarity", "common")),
			"value": int(def.get("value", 40)),
			"size": size,
			"pos": pos,
		})
	return items


## 解析容器产出权重：容器 Resource（ContainerData）显式绑定优先；空表回退
## 共享 tier 权重表（container_tier_config，INV-16）。返回 {rarity, category}。
func _loot_weights_for(entry: Dictionary) -> Dictionary:
	var type_id := str(entry.get("type_id", ""))
	var rarity_weights: Dictionary = {}
	var category_weights: Dictionary = {}
	var cdata: ContainerData = _container_resources().get(type_id, null)
	if cdata != null:
		rarity_weights = cdata.rarity_weights
		category_weights = cdata.category_weights
	if rarity_weights.is_empty():
		var tier := str(entry.get("tier", "C1"))
		rarity_weights = _loaded_config_data.get("container_tier_weights", {}).get(tier, {})
	return {"rarity": rarity_weights, "category": category_weights}


## 概率抽取一件（ItemDefinition -> 计划字典）；池空/未抽中回退轮转定义。
func _loot_pick_definition(entry: Dictionary, weights: Dictionary,
		round_index: int) -> Dictionary:
	var pool := _item_definitions_pool()
	var def: ItemDefinition = _loot.pick(pool, weights.get("rarity", {}),
		weights.get("category", {}))
	if def != null:
		return {
			"definition_id": def.definition_id, "rarity": def.rarity,
			"value": def.value, "width": def.width, "height": def.height,
		}
	return _nth_item_definition(round_index)


## 候选定义池（懒加载）：ItemData 资源优先，字典配置回退。
func _item_definitions_pool() -> Array:
	if not _item_pool.is_empty():
		return _item_pool
	if _repos != null and _repos.config_data != null:
		if _repos.config_data.has_method("load_item_data"):
			var data_dict: Dictionary = _repos.config_data.load_item_data()
			for key in data_dict:
				var def := ItemDefinition.from_resource(data_dict[key])
				if def != null:
					_item_pool.append(def)
	if _item_pool.is_empty():
		var defs: Dictionary = _loaded_config_data.get("item_definitions", {})
		for key in defs:
			var def := ItemDefinition.from_config(defs[key])
			if def != null:
				_item_pool.append(def)
	return _item_pool


## 容器 Resource 注册态（懒加载；未提供时返回空表）。
func _container_resources() -> Dictionary:
	if _container_data.is_empty() and _repos != null and _repos.config_data != null:
		if _repos.config_data.has_method("load_container_data"):
			_container_data = _repos.config_data.load_container_data()
	return _container_data


## 注入物品概率系统随机种子（负值随机化）；测试确定性用。
func set_loot_seed(seed_value: int) -> void:
	_loot.set_seed(seed_value)


## 容器内物品数量（配置 container_item_count_range [min,max] 单一来源 INV-16；
## 按本局进度确定性轮动、首容器从 min+1 起步，未加载配置回退 1）。
func _container_item_count(index: int) -> int:
	var range_v := Vector2i(1, 1)
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			range_v = cfg.container_item_count_range
	var lo := maxi(range_v.x, 1)
	var hi := maxi(range_v.y, lo)
	return lo + ((index + 1) % (hi - lo + 1))


## 在 gw×gh 网格中为 size 找 first-fit 位置（occ 为已占格集合）；放不下
## 返回 (-1,-1)。
func _first_fit_in_grid(gw: int, gh: int, size: Vector2i, occ: Dictionary) -> Vector2i:
	for y in gh:
		for x in gw:
			var at := Vector2i(x, y)
			if at.x + size.x > gw or at.y + size.y > gh:
				continue
			var blocked := false
			for dx in size.x:
				for dy in size.y:
					if occ.has(at + Vector2i(dx, dy)):
						blocked = true
						break
				if blocked:
					break
			if not blocked:
				return at
	return Vector2i(-1, -1)


## 计划表的对外摘要（只含数量/实例 id/占格位置与形状/已揭晓标记，不含身份
## INV-05）；blocks 元素为 {pos, size, revealed}。
func _container_plan_summary(container_id: String) -> Dictionary:
	var items: Array = _container_item_plans.get(container_id, [])
	var blocks: Array = []
	var ids: Array = []
	var csm: ContainerSearchStateMachine = _container_search_service.container(container_id) \
		if _container_search_service != null else null
	for it: Dictionary in items:
		ids.append(it.get("instance_id", ""))
		blocks.append({
			"pos": it.get("pos", Vector2i.ZERO),
			"size": it.get("size", Vector2i.ONE),
			"revealed": csm != null and csm.is_instance_revealed(str(it.get("instance_id", ""))),
		})
	return {"container_id": container_id, "item_count": items.size(),
		"instance_ids": ids, "blocks": blocks}


## 查容器计划中某件物品的完整信息（身份仅此处可见）。
func _plan_item_info(container_id: String, instance_id: String) -> Dictionary:
	for it: Dictionary in _container_item_plans.get(container_id, []):
		if str(it.get("instance_id", "")) == instance_id:
			return it.duplicate()
	return {}


## 跨容器查一件待搬运物品的完整信息。
func _pending_item_info(instance_id: String) -> Dictionary:
	for container_id in _container_item_plans:
		var info := _plan_item_info(str(container_id), instance_id)
		if not info.is_empty():
			return info
	return {}


## 品质揭晓耗时（秒，配置单一来源 INV-16；未加载回退 1）。
func _reveal_wait_seconds(rarity: String) -> float:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			return cfg.get_reveal_duration(rarity)
	return 1.0


## 本局地图容器计划（AC-17：表现层地图容器实体的数据来源；只读副本）。
func match_containers() -> Array:
	return _match_containers.duplicate()


## 生成本局地图容器计划（每局入场时调用，INV-14 多局隔离）。
## 容器类型取配置数据 container_types（kind=="container"，排除撤离点等），
## 依次轮转生成 match_container_count 个；配置缺失时回退等量通用容器。
func _build_match_containers() -> void:
	_match_containers = []
	_container_item_plans.clear()
	var types: Array = []
	var container_types: Dictionary = _loaded_config_data.get("container_types", {})
	for type_id in container_types:
		var entry: Dictionary = container_types[type_id]
		if str(entry.get("kind", "container")) != "container":
			continue
		types.append(entry)
	var count := _match_container_count()
	for i in count:
		if types.is_empty():
			_match_containers.append({
				"container_id": "map-c-%02d" % (i + 1), "type_id": "",
				"display_name": "容器", "tier": "C1", "grid_width": 3, "grid_height": 3})
			continue
		var entry: Dictionary = types[i % types.size()]
		_match_containers.append({
			"container_id": "map-c-%02d" % (i + 1),
			"type_id": str(entry.get("type_id", "")),
			"display_name": str(entry.get("display_name", "容器")),
			"tier": str(entry.get("tier", "C1")),
			"grid_width": int(entry.get("grid_width", 3)),
			"grid_height": int(entry.get("grid_height", 3))})


## 本局地图容器数量（配置单一来源 INV-16；未加载/非法时回退 6）。
func _match_container_count() -> int:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null and cfg.match_container_count > 0:
			return cfg.match_container_count
	return 6


## 计划中下一个未完成容器 id；全部完成/无计划返回 ""。
func _next_uncompleted_container() -> String:
	if _container_search_service == null:
		return ""
	for entry in _match_containers:
		var cid := str(entry.get("container_id", ""))
		if cid != "" and not _container_search_service.is_container_completed(cid):
			return cid
	return ""


## 查容器计划中的 type_id；不在计划中返回 ""。
func _container_type_id(container_id: String) -> String:
	for entry in _match_containers:
		if str(entry.get("container_id", "")) == container_id:
			return str(entry.get("type_id", ""))
	return ""


## 查容器计划条目（含 display_name/grid_width/grid_height）；不在计划中返回空。
func _container_plan_entry(container_id: String) -> Dictionary:
	for entry in _match_containers:
		if str(entry.get("container_id", "")) == container_id:
			return entry
	return {}


## 挑选一件物品定义用于搜索产出（配置数据单一来源 INV-16）。
## 按已完成容器数轮转配置数据中的定义（确定性，不引入随机）；配置未加载时
## 回退内置 item_0001（物品注册表首条）。
func _nth_item_definition(index: int) -> Dictionary:
	var defs: Dictionary = _loaded_config_data.get("item_definitions", {})
	if not defs.is_empty():
		var keys: Array = defs.keys()
		return defs[keys[index % keys.size()]]
	return {"definition_id": "item_0001", "rarity": "legendary",
		"value": 15846000, "width": 1, "height": 1}


## 用例：开始撤离读条（IN_RUN_EXTRACTABLE -> EXTRACTING）。
## 切片 7：注入 ExtractService 时，撤离域重置读条（撤离时长单一来源 INV-16）
## 并进入 EXTRACTING；未注入时回退占位行为（仅转移）。
func start_extraction() -> void:
	_sm.on_extract_started()
	_persist_run_snapshot()


## 用例：推进撤离读条与总计时（并行，INV-08；切片 7 Extract 域）。
## 返回是否本次推进使撤离阶段落定（已进入 RUN_SUCCEEDED 或 RUN_FAILED）。
## 注：表现层计时循环（_process/timer）只调用本用例推进，不直改领域状态。
func tick_extraction(delta_seconds: float) -> bool:
	## 状态机在转移瞬间即发布终局事件（payload 携带清单），先备好两份清单：
	## 读条先归零取背包（INV-10）、总时间先归零取安全箱（INV-11），落定帧
	## 之前哪份被取用未知，两份同时快照互不干扰。
	_snapshot_inventory_both()
	var resolved := _sm.tick_extraction(delta_seconds)
	if resolved:
		## 读条先归零 -> 成功；总时间先归零 -> 失败（INV-08）
		_last_run_outcome = "success" \
			if _sm.current_phase() == RunState.Phase.RUN_SUCCEEDED else "failure"
		_persist_run_snapshot()
	return resolved


## 用例（占位）：撤离读条完成（EXTRACTING -> RUN_SUCCEEDED）。
## 真实读条计时由 Extract 域切片 7 接入（TBD-04 同刻优先级停工红线）。
func complete_extraction_placeholder() -> void:
	_snapshot_inventory_both()
	_sm.on_extraction_complete()
	_last_run_outcome = "success"
	_persist_run_snapshot()


## 用例（占位）：本局总时间耗尽（IN_RUN_* / EXTRACTING -> RUN_FAILED）。
func timeout_placeholder() -> void:
	_snapshot_inventory_both()
	_sm.on_timeout()
	_last_run_outcome = "failure"
	_persist_run_snapshot()


## ---- 结算 ----

## 用例：完成结算（RUN_SUCCEEDED/RUN_FAILED -> SETTLED，幂等 INV-09）。
## 切片 8：注入 SettlementService 时，经结算域完成物品入库（成功携带物品
## INV-10 / 失败安全箱物品 INV-11）并落库局外账户；结算幂等（INV-09，已结算
## 则跳过状态机转移，不重复广播 RUN_SETTLED）。未注入时回退占位行为。
## WORD-31：结算后写入存档（IRunResultRepository 结算记录 + IProfileRepository
## 局外账户），数据变更仍由既有领域事件（RUN_SETTLED 等）经总线广播。
func settle() -> void:
	var state: RunState = _store.read()
	var profile := _load_profile()
	var should_settle := true
	if _settlement_service != null and state != null and profile != null:
		var is_success := _run_is_success(state)
		should_settle = _settlement_service.settle_success(state, profile) \
			if is_success else _settlement_service.settle_failure(state, profile)
		if should_settle and _repos != null and _repos.profile != null:
			_repos.profile.save(profile)
	if should_settle:
		_sm.on_settled()
	_persist_settlement()
	## 切片 9 表现层接线：入库物品逐件广播 WAREHOUSE_ITEM_ADDED（结果流转处，
	## 与 Warehouse 域「不重复发布」约定一致），驱动局外仓库/遥测更新。
	var returned_ids: Array = state.carried_item_ids \
		if state != null and _run_is_success(state) \
		else (state.safe_item_ids if state != null else [])
	for instance_id in returned_ids:
		_bus.publish(DomainEvents.Events.WAREHOUSE_ITEM_ADDED,
			DomainEvents.WarehouseItemAdded.new(str(instance_id)))
	## 入库物品摆入仓库格子（first-fit；位置为运行时状态，跨重启重排）
	deposit_items_to_warehouse(returned_ids)


## 用例：出售一件仓库物品（切片 8 Warehouse 域，INV-12 原子事务）。
## 经 WarehouseService.sell_item 完成货币加款（走 Transaction 域防重）并从
## 仓库移除；成功后落库局外账户。返回成交价格（失败返回 0）。
## 切片 9：成交后广播 ITEM_SOLD / CURRENCY_CHANGED（结果流转处发布，
## 与 Warehouse 域约定一致），驱动局外货币/仓库/遥测更新。
## 未注入 WarehouseService 时返回 0（回退占位，既有流程不受影响）。
func sell_warehouse_item(instance_id: String) -> int:
	if _warehouse_service == null:
		return 0
	var profile := _load_profile()
	if profile == null:
		return 0
	var balance_before := profile.currency
	var price := _warehouse_service.sell_item(profile, instance_id)
	if price > 0 and _repos != null and _repos.profile != null:
		_repos.profile.save(profile)
	if price > 0:
		## 同步清掉仓库格子上的摆放（账本与格子位置一致）
		if _item_inventory_service != null:
			var grid: GridInventory = _item_inventory_service.get_grid(
				GridInventory.OwnerType.WAREHOUSE)
			if grid != null:
				grid.remove(instance_id)
		_bus.publish(DomainEvents.Events.ITEM_SOLD, DomainEvents.ItemSold.new(
			instance_id, price, balance_before, profile.currency))
		_bus.publish(DomainEvents.Events.CURRENCY_CHANGED, DomainEvents.CurrencyChanged.new(
			price, balance_before, profile.currency))
	return price


## 用例：确认结算并返回局外（SETTLED -> OUT_OF_RUN）。
func confirm_settled() -> void:
	_sm.on_settled_confirmed()


## ---- 只读查询（供表现层展示，经接口/状态机公开入口读取）----

## 当前阶段。
func current_phase() -> RunState.Phase:
	return _sm.current_phase()


## 撤离解锁所需完成容器数（配置单一来源 INV-16）。
func required_container_count() -> int:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			return cfg.required_completed_containers
	return 5


## 当前完成容器数。
func completed_container_count() -> int:
	var state: RunState = _store.read()
	return state.completed_container_count if state != null else 0


## 局开始加载的配置数据（WORD-31；供表现层只读查询）。
## 未接线数据层或加载失败时返回空 Dictionary。
func loaded_config_data() -> Dictionary:
	return _loaded_config_data


## 当前局外账户（切片 3；供表现层展示货币/仓库/已选背包）。
## 未接线数据层或加载失败时返回 null。
func current_profile() -> PlayerProfile:
	return _load_profile()


## 当前物品与背包服务（切片 5；供表现层/后续切片经接口访问）。
## 未接线时返回 null。
func item_inventory() -> IItemInventoryService:
	return _item_inventory_service


## 当前容器搜索服务（切片 6；供表现层/后续切片经接口访问）。
## 未接线时返回 null。
func container_search() -> IContainerSearchService:
	return _container_search_service


## 当前撤离服务（切片 7；供表现层/后续切片经接口访问）。
## 未接线时返回 null。
func extract_service() -> IExtractService:
	return _extract_service


## 当前结算服务（切片 8；供表现层/后续切片经接口访问）。
## 未接线时返回 null。
func settlement_service() -> ISettlementService:
	return _settlement_service


## 当前仓库服务（切片 8；供表现层/后续切片经接口访问）。
## 未接线时返回 null。
func warehouse_service() -> IWarehouseService:
	return _warehouse_service


## 当前遥测服务（切片 9；供表现层展示/测试断言埋点）。
## 未接线时返回 null。
func telemetry() -> ITelemetryService:
	return _telemetry


## 当前已携带入背包的物品数（切片 9 表现层接线「携带」展示）。
## 未注入 ItemInventoryService / 背包格未初始化时返回 0。
func carried_item_count() -> int:
	if _item_inventory_service == null:
		return 0
	var grid: GridInventory = _item_inventory_service.get_grid(GridInventory.OwnerType.BACKPACK)
	return grid.item_count() if grid != null else 0


## 本局背包格内的物品实例 id 列表（按放置顺序的只读副本；供表现层背包格
## 渲染品质/名称，展示信息经 ItemInventoryService 物品定义解析，
## 不耦合实例 id 命名）。
func backpack_item_ids() -> Array:
	if _item_inventory_service == null:
		return []
	var grid: GridInventory = _item_inventory_service.get_grid(GridInventory.OwnerType.BACKPACK)
	return grid.placements.keys() if grid != null else []


## 本局剩余总时间（秒；供 HUD 展示）。
func remaining_match_time() -> int:
	var state: RunState = _store.read()
	return state.remaining_match_time if state != null else 0


## 本局剩余撤离读条时间（秒；供 HUD 展示）。
func remaining_extraction_time() -> int:
	var state: RunState = _store.read()
	return state.remaining_extraction_time if state != null else 0


## 撤离读条时长（配置单一来源 INV-16；供 HUD 读条按总量归一展示）。
func extraction_duration() -> int:
	if _config_loader != null:
		var cfg := _config_loader.get_config()
		if cfg != null:
			return cfg.extraction_duration
	return 15


## 当前已选背包档位 offerId（表现层展示选中态用）。
func selected_backpack_offer() -> String:
	return _selected_offer_id


## ---- WORD-31 数据层接线辅助（应用层编排侧，领域/表现层不感知）----

## 切片 5：确认入场后按选定档位初始化本局背包格子 + 安全箱格子
## （INV-04 背包/安全箱语义分离；尺寸单一来源 INV-16）。
## 未注入 ItemInventoryService 时跳过（回退占位，既有流程不受影响）。
func _setup_inventory_grids() -> void:
	if _item_inventory_service == null:
		return
	var offer := _loadout_service.get_backpack_offer(_selected_offer_id) \
		if _loadout_service != null else {}
	if offer.is_empty():
		var cfg := _config_loader.get_config() if _config_loader != null else null
		offer = cfg.get_backpack_offer(_selected_offer_id) if cfg != null else {}
	if offer.is_empty():
		return
	var grid_width: int = offer.get("grid_width", 0)
	var grid_height: int = offer.get("grid_height", 0)
	_item_inventory_service.setup_backpack(grid_width, grid_height)
	var safe := _config_loader.get_config().safe_container \
		if _config_loader != null and _config_loader.get_config() != null else {}
	_item_inventory_service.setup_safe(
		int(safe.get("grid_width", 2)), int(safe.get("grid_height", 2)))


## 开局初始化局外账户（切片 3）：全新档案写入初始货币（INV-16 单一来源，
## AC-21 入场货币校验），仓库初始为空（架构 §5 PlayerProfile）。
## 已初始化（有货币/已有选择/已有仓库物品）的档案不重复写入。
func _ensure_initial_profile() -> void:
	if _repos == null or _repos.profile == null:
		return
	var profile: PlayerProfile = _repos.profile.load()
	if profile == null:
		return
	var is_fresh: bool = profile.currency == 0 \
		and profile.selected_backpack_offer_id == "" \
		and profile.warehouse_item_ids.is_empty()
	if not is_fresh:
		return
	var cfg := _config_loader.get_config() if _config_loader != null else null
	var initial := cfg.initial_currency if cfg != null else 100000
	profile.currency = initial
	_repos.profile.save(profile)

## 开局加载配置数据（道具/藏品、容器/撤离点、背包档位、产出权重）。
func _load_config_data() -> void:
	if _repos == null or _repos.config_data == null:
		return
	_loaded_config_data = {
		"item_definitions": _repos.config_data.load_item_definitions(),
		"container_types": _repos.config_data.load_container_types(),
		"backpack_offers": _repos.config_data.load_backpack_offers(),
		"container_tier_weights": _repos.config_data.load_container_tier_weights(),
	}


## 局内状态变更后写运行时快照（IRunSnapshotRepository，可选）。
func _persist_run_snapshot() -> void:
	if _repos == null or _repos.run_snapshot == null:
		return
	var state: RunState = _store.read()
	if state != null:
		_repos.run_snapshot.upsert_run_snapshot(state)


## 结算后写入存档：结算记录（幂等 run_id 唯一，INV-09）+ 局外账户落库。
## 撤离成功携带物品入仓库（INV-10）；撤离失败安全箱物品入仓库（INV-11）。
func _persist_settlement() -> void:
	if _repos == null:
		return
	var state: RunState = _store.read()
	if state == null:
		return
	if _repos.run_result != null:
		var profile := _load_profile()
		var currency_before := profile.currency if profile != null else 0
		var outcome := _last_run_outcome if _last_run_outcome != "" else \
			("success" if state.phase == RunState.Phase.RUN_SUCCEEDED else "failure")
		_repos.run_result.insert_settlement({
			"record_id": "settle-%s" % state.run_id,
			"run_id": state.run_id,
			"profile_id": "local",
			"result": outcome,
			"currency_before": currency_before,
			"currency_after": currency_before,
			"carried_item_ids": state.carried_item_ids,
			"safe_item_ids": state.safe_item_ids,
		})
	if _repos.profile != null:
		var profile := _load_profile()
		if profile != null:
			var is_success := _last_run_outcome == "success" \
				or (_last_run_outcome == "" and state.phase == RunState.Phase.RUN_SUCCEEDED)
			var returned_ids: Array = state.carried_item_ids if is_success else state.safe_item_ids
			for instance_id in returned_ids:
				if not profile.warehouse_item_ids.has(instance_id):
					profile.warehouse_item_ids.append(instance_id)
			_repos.profile.save(profile)


## 读取局外账户（加载失败时回退默认账户）。
func _load_profile() -> PlayerProfile:
	if _repos == null or _repos.profile == null:
		return null
	return _repos.profile.load()


## 是否处于局内阶段（IN_RUN_LOCKED / IN_RUN_EXTRACTABLE）。
## 容器搜索用例仅在本局内有效（局外调用不污染领域状态）。
func _in_run_phase() -> bool:
	var state: RunState = _store.read()
	if state == null:
		return false
	return state.phase == RunState.Phase.IN_RUN_LOCKED \
		or state.phase == RunState.Phase.IN_RUN_EXTRACTABLE


## 从背包格子找首个可放置空位（INV-04 格子合法）；无空位返回 (-1,-1)。
## 自左上向右逐行扫描，第一个 can_place 通过的位置即为放置点。
func _first_free_slot(grid: GridInventory, size: Vector2i) -> Vector2i:
	if grid == null:
		return Vector2i(-1, -1)
	for y in grid.height:
		for x in grid.width:
			var at := Vector2i(x, y)
			if grid.can_place(size, at):
				return at
	return Vector2i(-1, -1)


## 撤离落定「前」把背包与安全箱两份清单同时快照到 RunState（carried/safe）。
## 状态机在转移瞬间即发布 RUN_SUCCEEDED/RUN_FAILED（payload 携带清单），
## 快照必须先于转移，否则结算页事件回调收到空列表（「带出 0 件」缺陷）。
## 成功取背包（INV-10）、失败取安全箱（INV-11）的取舍由结算/持久化按
## 终局阶段判定，两份同时备好互不干扰。
func _snapshot_inventory_both() -> void:
	if _item_inventory_service == null:
		return
	var state: RunState = _store.read()
	if state == null:
		return
	var backpack: GridInventory = _item_inventory_service.get_grid(
		GridInventory.OwnerType.BACKPACK)
	var safe: GridInventory = _item_inventory_service.get_grid(GridInventory.OwnerType.SAFE)
	state.carried_item_ids = backpack.placements.keys() if backpack != null else []
	state.safe_item_ids = safe.placements.keys() if safe != null else []
	_store.write(state)


## 撤离落定后快照本局携带/安全箱物品到 RunState（切片 9 表现层接线）。
## 撤离成功（RUN_SUCCEEDED）：背包格内物品 -> carried_item_ids（INV-10）；
## 撤离失败（RUN_FAILED）：安全箱格内物品 -> safe_item_ids（INV-11）。
## 未注入 ItemInventoryService 时跳过（回退占位，既有流程不受影响）。
func _snapshot_inventory_to_run() -> void:
	if _item_inventory_service == null:
		return
	var state: RunState = _store.read()
	if state == null:
		return
	var is_success := state.phase == RunState.Phase.RUN_SUCCEEDED
	var grid: GridInventory = _item_inventory_service.get_grid(
		GridInventory.OwnerType.BACKPACK if is_success else GridInventory.OwnerType.SAFE)
	if grid == null:
		return
	var ids: Array = []
	for instance_id in grid.placements:
		ids.append(str(instance_id))
	if is_success:
		state.carried_item_ids = ids
	else:
		state.safe_item_ids = ids
	_store.write(state)


## 结算时判定本局成败（切片 8）：以终局阶段为准；阶段信息缺失时回退
## _last_run_outcome（与 _persist_settlement 的存档判定保持一致）。
func _run_is_success(state: RunState) -> bool:
	if state == null:
		return _last_run_outcome == "success"
	if state.phase == RunState.Phase.RUN_SUCCEEDED:
		return true
	if state.phase == RunState.Phase.RUN_FAILED:
		return false
	return _last_run_outcome == "success"
