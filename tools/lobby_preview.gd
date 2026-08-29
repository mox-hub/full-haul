## 临时预览工具（不提交进游戏流程）：窗口模式实例化主场景，黑盒驱动
## 「入场 -> 对局 -> 搜索弹窗 -> 撤离读条」并分阶段截图到 reports/ 后退出。
extends SceneTree

var _frames := 0
var _main: Node = null
var _stage := 0


func _initialize() -> void:
	_main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	root.add_child(_main)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	var lobby := _main.get_node("UiRoot/LobbyPage")
	var loadout := _main.get_node("UiRoot/LoadoutPage")
	var match_page := _main.get_node("UiRoot/MatchPage")
	var view := lobby.get_node("BaseArea/SceneViewportContainer/SceneViewport/WarehouseView")
	match _stage:
		0:
			if _frames == 12 and lobby.visible:
				_save("lobby_preview_home.png")
			## 仓库 3D 预览验证：开弹窗前直接造「气动扳手(han_gun 演示模型) + 瓶装水 + 鎏金雕像」塞入仓库
			if _frames == 14 and lobby.visible:
				_seed_warehouse_preview()
			## 叠层物热点点击回放：命中货架 A → 仓库弹窗
			if _frames == 16 and lobby.visible:
				var canvas_pos: Vector2 = view.prop_center("shelf_a")
				view.try_activate_at(canvas_pos)
			if _frames >= 24 and lobby.visible:
				_save("lobby_preview_warehouse.png")
				_click_first_model_preview(lobby)
				_stage = 10
		10:
			## 仓库行缩略图点击 → 3D 大图弹窗
			if _frames >= 34 and lobby.visible:
				_save("lobby_preview_model_popup.png")
				if lobby._model_popup != null:
					lobby._model_popup.close()
				(lobby.get_node("%StartButton") as Button).pressed.emit()
				(loadout.get_node("%ConfirmButton") as Button).pressed.emit()
				_stage = 1
		1:
			## 对局页就绪（阶段轮询已启用容器）：提前一帧种子（3D 视口下一帧
			## 才出图），随后截图并点开首容器搜索弹窗
			if _frames == 69 and match_page.visible:
				_seed_backpack_preview(match_page)
			if _frames >= 72 and match_page.visible:
				_save("match_preview_home.png")
				var containers := match_page.get_node("%MapContainers") as GridContainer
				if containers.get_child_count() > 0:
					(containers.get_child(0) as Button).pressed.emit()
				_stage = 2
		2:
			## 搜索弹窗蒙版/转圈揭晓中段（首个容器 1 件 common，0.5s 内完成）
			if _frames >= 82:
				_save("match_preview_search.png")
				_stage = 3
		3:
			## 揭晓收尾后关闭弹窗（未搬运物品废弃），其余容器经旧用例同步
			## 搜完并携带，随即开始撤离（读条 + 背包格填充）
			if _frames >= 200:
				match_page.search_popup.close()
				var orch: RunFlowOrchestrator = _main._orchestrator
				if orch != null:
					for entry in orch.match_containers():
						orch.search_and_carry_container(str(entry.get("container_id", "")))
				(match_page.get_node("%ExtractButton") as Button).pressed.emit()
				_stage = 4
		4:
			if _frames >= 215:
				_save("match_preview_extract.png")
				## 读条中直接完成撤离 → RUN_SUCCEEDED → 结算页（带出物品格子清单）
				(match_page.get_node("%ExtractDoneButton") as Button).pressed.emit()
				_stage = 5
		5:
			## 结算页：携带带出物品逐件格子展示（数量与清单正确性人工比对）
			if _frames >= 232:
				_save("settlement_preview.png")
				_stage = 6
		6:
			if _frames >= 242:
				quit()


func _save(filename: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("res://reports/" + filename)
	print("saved: ", filename)


## 仓库 3D 预览验证种子：直接造实例塞仓库（正常流程应经对局搜刮→撤离结算）。
func _seed_warehouse_preview() -> void:
	var orch: RunFlowOrchestrator = _main._orchestrator
	if orch == null:
		return
	var inv := orch.item_inventory()
	var profile := orch.current_profile()
	if inv == null or profile == null:
		return
	inv.create_item("preview_pistol_w", "item_0057")
	inv.create_item("preview_battery_w", "item_0115")
	inv.create_item("preview_ammobox_w", "item_0006")
	for id in ["preview_pistol_w", "preview_battery_w", "preview_ammobox_w"]:
		if not profile.warehouse_item_ids.has(id):
			profile.warehouse_item_ids.append(id)
	## current_profile() 返回仓储副本（load 即 duplicate），必须 save 回写才生效
	orch._repos.profile.save(profile)


## 仓库块点击回放：直接触发仓库画布首个物品（气动扳手）的点击 → 3D 大图。
func _click_first_model_preview(lobby: Node) -> void:
	(lobby.warehouse_board as GridBoard).item_clicked.emit("preview_pistol_w")


## 局内背包格 3D 预览验证种子：造实例放入背包格 (0,0) 并强制刷新展示。
func _seed_backpack_preview(match_page: Node) -> void:
	var orch: RunFlowOrchestrator = _main._orchestrator
	if orch == null:
		return
	var inv := orch.item_inventory()
	if inv == null:
		return
	if inv.get_item("preview_pistol_b") == null:
		inv.create_item("preview_pistol_b", "item_0057")
	var placed: bool = inv.place_item("preview_pistol_b",
			GridInventory.OwnerType.BACKPACK, Vector2i.ZERO)
	print("backpack preview placed: ", placed)
	match_page._refresh_backpack_grid()
