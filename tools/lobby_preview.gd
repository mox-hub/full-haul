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
			## 叠层物热点点击回放：命中货架 A → 仓库弹窗
			if _frames == 16 and lobby.visible:
				var canvas_pos: Vector2 = view.get_canvas_transform() * view.prop_center("shelf_a")
				view.try_activate_at(canvas_pos)
			if _frames >= 24 and lobby.visible:
				_save("lobby_preview_warehouse.png")
				(lobby.get_node("%StartButton") as Button).pressed.emit()
				(loadout.get_node("%ConfirmButton") as Button).pressed.emit()
				_stage = 1
		1:
			## 对局页就绪（阶段轮询已启用容器）
			if _frames >= 70 and match_page.visible:
				_save("match_preview_home.png")
				var containers := match_page.get_node("%MapContainers") as GridContainer
				if containers.get_child_count() > 0:
					(containers.get_child(0) as Button).pressed.emit()
				_stage = 2
		2:
			## 搜索弹窗动画中段
			if _frames >= 82:
				_save("match_preview_search.png")
				_stage = 3
		3:
			## 弹窗收尾后搜完剩余容器并开始撤离（读条 + 背包格填充）
			if _frames >= 200:
				var containers := match_page.get_node("%MapContainers") as GridContainer
				for i in containers.get_child_count():
					var b := containers.get_child(i) as Button
					if not b.disabled:
						b.pressed.emit()
				(match_page.get_node("%ExtractButton") as Button).pressed.emit()
				_stage = 4
		4:
			if _frames >= 215:
				_save("match_preview_extract.png")
				_stage = 5
		5:
			if _frames >= 225:
				quit()


func _save(filename: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("res://reports/" + filename)
	print("saved: ", filename)
