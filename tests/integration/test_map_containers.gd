## test_map_containers.gd —— FullHaul 集成测试：对局地图容器实体（GdUnit4）
##
## 职责：
##   修复回归（AC-17 核心搜刮图形化）：对局场景内必须有可操作的容器实体——
##   此前地图为空白占位矩形，用户无从进行容器搜索操作。验证：
##   - 进入一局后地图按本局容器计划生成容器按钮（数量一致、可点击）
##   - 点击容器完成搜索并携带产出（完成数/携带数 +1）
##   - 已完成容器按钮禁用并标记，不重复搜索
##
## 说明：
##   与 test_main_flow_smoke / test_full_chain_loop 同为黑盒驱动（真实主场景 +
##   Autoload）。全局 EventBus 为进程级单例，主场景用例需一局一套件隔离，
##   避免上一用例释放节点的悬空订阅被后续用例触发。
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/integration/test_map_containers.gd --ignoreHeadlessMode

extends GdUnitTestSuite

const MainScene := preload("res://scenes/main.tscn")

## 揭晓时长备份（测试内加速揭晓动画，after_test 恢复）
var _saved_durations: Dictionary = {}


## 加速揭晓动画（须在主场景 boot 之后调用——boot 会重新 load_config 覆盖）。
func _accelerate_reveals() -> void:
	var cfg: GameConfig = ConfigLoader.get_config()
	if cfg == null:
		return
	_saved_durations = cfg.rarity_reveal_durations.duplicate()
	var fast := {}
	for k in cfg.rarity_reveal_durations:
		fast[k] = 0.05
	cfg.rarity_reveal_durations = fast


func after_test() -> void:
	if not _saved_durations.is_empty():
		ConfigLoader.get_config().rarity_reveal_durations = _saved_durations


func _page(main: Node, path: String) -> Control:
	return main.get_node(path) as Control


func _button(page: Control, unique_name: String) -> Button:
	return page.get_node("%" + unique_name) as Button


## 组合根（main.gd）持有编排器，供黑盒测试经只读访问器断言领域状态。
func _orchestrator(main: Node) -> RunFlowOrchestrator:
	return main.get("_orchestrator") as RunFlowOrchestrator


func test_map_container_entities_clickable() -> void:
	var main: Node = auto_free(MainScene.instantiate())
	add_child(main)
	## V2 搜索弹窗：容器完成要等逐件揭晓动画跑完；压到 0.05s 让序列亚秒完成
	_accelerate_reveals()

	var lobby := _page(main, "UiRoot/LobbyPage")
	var loadout := _page(main, "UiRoot/LoadoutPage")
	var match_page := _page(main, "UiRoot/MatchPage")
	var orch := _orchestrator(main)
	assert_that(orch).is_not_null()

	## 进入一局（默认选择首个档位并购买扣款）
	_button(lobby, "StartButton").pressed.emit()
	_button(loadout, "ConfirmButton").pressed.emit()
	assert_that(match_page.visible).is_true()
	## 等一帧：页面 _process 捕获 IN_RUN_LOCKED 阶段变化，启用容器按钮
	## （RUN_INIT -> IN_RUN_LOCKED 无事件，按钮态由每帧阶段轮询刷新）
	await get_tree().process_frame

	## 地图上生成容器实体（随机刷新：类型+位置），数量与本局容器计划一致
	## （配置单一来源 INV-16）；实体挂在地图场画布 %MapContainers 下
	var containers: Control = match_page.get_node("%MapContainers") as Control
	assert_that(containers).is_not_null()
	assert_that(containers.get_child_count()).is_equal(orch.match_containers().size())
	assert_that(containers.get_child_count()).is_greater_equal(
		orch.required_container_count())

	## 点击第一个容器：完成该容器搜索并携带产出（HUD 目标 1/5）
	var first: Button = containers.get_child(0) as Button
	assert_that(first.disabled).is_false()
	first.pressed.emit()
	## 新流程：点击打开搜索弹窗（蒙版），自动逐件揭晓后容器才完成计数
	var deadline := Time.get_ticks_msec() + 8000
	while Time.get_ticks_msec() < deadline and orch.completed_container_count() < 1:
		await get_tree().process_frame
	assert_that(orch.completed_container_count()).is_equal(1)
	## 揭晓 ≠ 搬运：未拖拽入背包/安全箱前不携带（V2 分步语义）
	assert_that(orch.carried_item_count()).is_equal(0)

	## 已完成的容器按钮被禁用并标记（不重复搜索，INV-06）
	assert_that(first.disabled).is_true()
	assert_that(first.text).contains("已搜索")
