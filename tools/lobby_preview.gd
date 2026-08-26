## 临时预览工具（不提交）：窗口模式实例化首页，截图到 reports/ 后退出。
extends SceneTree

var _frames := 0
var _page: Node = null
var _stage := 0


func _initialize() -> void:
	var packed := load("res://scenes/lobby/lobby_page.tscn") as PackedScene
	_page = packed.instantiate()
	root.add_child(_page)
	process_frame.connect(_on_frame)


func _on_frame() -> void:
	_frames += 1
	if _frames == 5:
		var bv := _page.get_node("BaseArea/BaseView") as Node2D
		print("BaseView global_position=", bv.global_position, " global_scale=", bv.global_scale,
				" scale=", bv.scale, " pos=", bv.position)
		var area := _page.get_node("BaseArea") as Control
		print("BaseArea global_rect=", area.get_global_rect())
		print("root size=", root.size, " content_scale_factor=", root.content_scale_factor,
				" content_scale_size=", root.content_scale_size)
	if _frames == 40 and _stage == 0:
		_save("lobby_preview_home.png")
		## 打开仓库弹窗（空态）
		var chip := _page.get_node("%WarehouseButton") as Button
		chip.pressed.emit()
		_stage = 1
	elif _frames == 80 and _stage == 1:
		_save("lobby_preview_popup.png")
		quit()


func _save(filename: String) -> void:
	var img := root.get_texture().get_image()
	img.save_png("res://reports/" + filename)
	print("saved: ", filename)
