## test_portrait_layout.gd —— FullHaul 表现层测试：竖屏布局边界（GdUnit4）
##
## 职责：
##   校验各基础页面在 9:16 竖屏设计画布（1080×1920，短边 1080）内
##   所有可见控件不出界、不溢出（WORD-26 竖屏适配回归守卫）。
##
## 说明：
##   - 使用独立 SubViewport 固定画布尺寸，不受运行窗口/无头模式影响。
##   - 容器布局在加入场景树两帧后完成计算，随后逐一检查控件全局矩形。
##   - 「撤离读条显示中」是 HUD 最高状态，单独覆盖（读条/标签为隐藏
##     控件，仅在撤离开始后可见）。
##
## 运行：
##   godot --headless --path . -s res://addons/gdUnit4/bin/GdUnitCmdTool.gd \
##        -a res://tests/presentation/test_portrait_layout.gd --ignoreHeadlessMode

extends GdUnitTestSuite

## 竖屏设计画布：9:16，短边 1080（project.godot viewport / GameConfig 视觉配置）
const CANVAS := Vector2i(1080, 1920)

const PAGES := [
	{ "tag": "lobby", "path": "res://scenes/lobby/lobby_page.tscn" },
	{ "tag": "loadout", "path": "res://scenes/lobby/loadout_page.tscn" },
	{ "tag": "match", "path": "res://scenes/match/match_page.tscn" },
	{ "tag": "hud", "path": "res://scenes/match/hud.tscn" },
	{ "tag": "settlement", "path": "res://scenes/ui/settlement_page.tscn" },
]


## [竖屏布局] 各页面全部可见控件均落在 1080×1920 画布内
func test_all_page_controls_within_portrait_canvas() -> void:
	for page in PAGES:
		var out: Array = await _check_in_canvas(page.tag, load(page.path))
		assert_that(out).override_failure_message(
			"%s 页面存在出界控件: %s" % [page.tag, ", ".join(out)]).is_empty()


## [竖屏布局] HUD 撤离读条显示中（最高状态）不出界
func test_hud_extraction_state_within_portrait_canvas() -> void:
	var packed: PackedScene = load("res://scenes/match/match_page.tscn")
	var out: Array = []
	var vp := _canvas_viewport()
	add_child(vp)
	var match_page := packed.instantiate()
	vp.add_child(match_page)
	var hud := match_page.get_node("%Hud")
	hud.call("set_objective", 5, 5, true)
	## 撤离读条展示动画入口（视觉占位），使读条/标签进入可见态
	hud.call("_on_extract_started", DomainEvents.ExtractStarted.new(15))
	await get_tree().process_frame
	await get_tree().process_frame
	out = _collect_out_of_canvas("match_extracting", match_page)
	match_page.queue_free()
	vp.queue_free()
	assert_that(out).override_failure_message(
		"撤离读条显示中存在出界控件: %s" % ", ".join(out)).is_empty()


## [竖屏布局] 结算页成功+已结算态（内容最高状态）不出界
func test_settlement_settled_state_within_portrait_canvas() -> void:
	var packed: PackedScene = load("res://scenes/ui/settlement_page.tscn")
	var vp := _canvas_viewport()
	add_child(vp)
	var settlement := packed.instantiate()
	vp.add_child(settlement)
	settlement.call("show_success", DomainEvents.RunSucceeded.new("run-0001", []))
	settlement.call("mark_settled")
	await get_tree().process_frame
	await get_tree().process_frame
	var out := _collect_out_of_canvas("settlement_settled", settlement)
	settlement.queue_free()
	vp.queue_free()
	assert_that(out).override_failure_message(
		"结算页已结算态存在出界控件: %s" % ", ".join(out)).is_empty()


## 在固定画布视口中实例化场景并收集出界控件。
func _check_in_canvas(tag: String, packed: PackedScene) -> Array:
	var vp := _canvas_viewport()
	add_child(vp)
	var page := packed.instantiate()
	vp.add_child(page)
	await get_tree().process_frame
	await get_tree().process_frame
	var out := _collect_out_of_canvas(tag, page)
	page.queue_free()
	vp.queue_free()
	return out


func _canvas_viewport() -> SubViewport:
	var vp := SubViewport.new()
	vp.size = CANVAS
	return vp


## 递归收集可见但超出画布的控件描述（tag:节点名 矩形）。
## 裁剪视图（clip_contents = true，如对局地图场 MapView）内部内容有意
## 大于画布、经平移查看，整棵子树豁免。
func _collect_out_of_canvas(tag: String, node: Node) -> Array:
	var out: Array = []
	_collect_into(tag, node, out, false)
	return out


func _collect_into(tag: String, node: Node, out: Array, in_clipped: bool) -> void:
	var clipped_here := in_clipped
	if node is Control and (node as Control).clip_contents:
		clipped_here = true
	for child in node.get_children():
		_collect_into(tag, child, out, clipped_here)
	if node is not Control:
		return
	var control := node as Control
	if not control.visible:
		return
	if clipped_here:
		return
	var rect := control.get_global_rect()
	if rect.position.x < -0.5 or rect.position.y < -0.5 \
			or rect.end.x > CANVAS.x + 0.5 or rect.end.y > CANVAS.y + 0.5:
		out.append("%s:%s%s" % [tag, control.name, rect])
