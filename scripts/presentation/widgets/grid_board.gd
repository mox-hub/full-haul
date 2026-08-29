## grid_board.gd —— FullHaul 表现层：通用格子画布（多格物品 / 蒙版 / 拖拽）
##
## 职责：
##   把一个 cols×rows 的格子储物空间渲染为画布，供搜索弹窗容器区、
##   页底背包/安全箱悬浮面板、仓库弹窗共用：
##   - 格底：每格 PixelUiKit inset 凸台（与既有格阵视觉一致）
##   - 物品块：占 w×h 的合并大块（品质色框 + 可选 3D 预览），可点击/可拖拽
##   - 蒙版块：占 w×h 的未知物品遮罩（灰底问号，可挂转圈指示器）
##   - 拖拽：Godot 原生 drag&drop——物品块为拖拽源，整板为放置目标；
##     落点合法性经注入的 drop_checker（Callable(at, size, instance_id)）
##     校验，放下时发 item_dropped 由使用方驱动领域用例
##
## 设计要点：
##   - 纯表现层：不触碰领域状态；领域校验经 drop_checker 注入
##   - 块定位手工绝对布局（GridContainer 无法跨格合并），板尺寸即格阵尺寸
##   - 蒙版块与物品块由使用方自行替换（先 remove 蒙版再 add 物品）

extends Control
class_name GridBoard

## 左键点击某物品块（instance_id）
signal item_clicked(instance_id: String)
## 一件物品被拖放到本板某格（顶左格坐标；合法性已过 drop_checker）
signal item_dropped(instance_id: String, at: Vector2i)


var cols := 0
var rows := 0
var cell := 64.0

## 落点校验（注入）：Callable(at: Vector2i, size: Vector2i, instance_id: String) -> bool；
## 未注入时拒绝一切放置。
var drop_checker := Callable()

## instance_id -> ItemBlock（当前物品块）
var _blocks: Dictionary = {}
## 蒙版块节点列表（index 与容器内物品序号一致）
var _masks: Array = []


## 创建一块 cols×rows 的格子画布（cell 为单格边长 design px）。
static func create(p_cols: int, p_rows: int, p_cell: float) -> GridBoard:
	var board := GridBoard.new()
	board.configure(p_cols, p_rows, p_cell)
	return board


## 配置板面并重建格底（已挂载的既有节点也可调用；会清空全部块）。
func configure(p_cols: int, p_rows: int, p_cell: float) -> void:
	cols = p_cols
	rows = p_rows
	cell = p_cell
	custom_minimum_size = Vector2(p_cols, p_rows) * p_cell
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_PASS
	for child in get_children():
		remove_child(child)
		child.queue_free()
	_blocks.clear()
	_masks.clear()
	for y in p_rows:
		for x in p_cols:
			var footer := Panel.new()
			footer.add_theme_stylebox_override("panel",
					PixelUiKit.inset_stylebox(PixelUiKit.COL_CELL_BG, PixelUiKit.COL_CELL_BORDER))
			footer.position = Vector2(x, y) * p_cell
			footer.size = Vector2.ONE * p_cell
			footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			add_child(footer)


## 格坐标 -> 板本地像素原点。
func block_origin(at: Vector2i) -> Vector2:
	return Vector2(at) * cell


## 本地像素 -> 顶左格坐标（夹取到板内合法范围）。
func cell_at(local_pos: Vector2) -> Vector2i:
	var x := clampi(int(floor(local_pos.x / cell)), 0, maxi(cols - 1, 0))
	var y := clampi(int(floor(local_pos.y / cell)), 0, maxi(rows - 1, 0))
	return Vector2i(x, y)


## 添加/替换一件物品块（品质色框 + 可选 3D 预览；tooltip 悬停提示）。
func put_item(instance_id: String, at: Vector2i, size: Vector2i, color: Color,
		definition_id := "", tooltip := "") -> void:
	remove_item(instance_id)
	var block := ItemBlock.new()
	block.instance_id = instance_id
	block.board = self
	block.position = block_origin(at)
	block.size = Vector2(size) * cell
	block.tooltip_text = tooltip
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel",
			PixelUiKit.inset_stylebox(color.darkened(0.55), color))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(panel)
	if not definition_id.is_empty():
		var preview := ModelPreviewView.create(definition_id, 0.0, true, color)
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		preview.offset_left = 8
		preview.offset_top = 8
		preview.offset_right = -8
		preview.offset_bottom = -8
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		block.add_child(preview)
	add_child(block)
	_blocks[instance_id] = block


## 移除一件物品块（不存在时忽略）。
func remove_item(instance_id: String) -> void:
	var block: ItemBlock = _blocks.get(instance_id, null)
	if block != null:
		block.queue_free()
		_blocks.erase(instance_id)


## 是否有指定物品块（蒙版态的未揭晓物品不算，供一键搬运只挑已揭晓物品）。
func has_item(instance_id: String) -> bool:
	return _blocks.has(instance_id)


## 更新一件物品块的位置（同板内拖拽重排；不存在时忽略）。
func move_item(instance_id: String, at: Vector2i) -> void:
	var block: ItemBlock = _blocks.get(instance_id, null)
	if block != null:
		block.position = block_origin(at)


func clear_items() -> void:
	for block in _blocks.values():
		block.queue_free()
	_blocks.clear()


## 放一个蒙版块（未知物品遮罩；index 供后续定位/替换）。
func put_mask(index: int, at: Vector2i, size: Vector2i) -> void:
	remove_mask(index)
	var block := Panel.new()
	block.position = block_origin(at)
	block.size = Vector2(size) * cell - Vector2(4, 4)
	block.add_theme_stylebox_override("panel",
			PixelUiKit.inset_stylebox(Color(0.22, 0.25, 0.30), Color(0.45, 0.50, 0.58)))
	block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mark := Label.new()
	mark.text = "?"
	mark.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mark.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	mark.add_theme_color_override("font_color", Color(0.62, 0.66, 0.74))
	mark.add_theme_font_size_override("font_size", int(minf(block.size.x, block.size.y) * 0.5))
	mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	block.add_child(mark)
	add_child(block)
	_masks.append({"index": index, "node": block})


## 取蒙版块节点（不存在返回 null；供使用方挂 spinner / 替换揭晓块）。
func mask_node(index: int) -> Panel:
	for entry in _masks:
		if int(entry.get("index", -1)) == index:
			return entry.get("node")
	return null


func remove_mask(index: int) -> void:
	for i in _masks.size():
		if int(_masks[i].get("index", -1)) == index:
			var node: Node = _masks[i].get("node")
			if node != null:
				node.queue_free()
			_masks.remove_at(i)
			return


func clear_masks() -> void:
	for entry in _masks:
		var node: Node = entry.get("node")
		if node != null:
			node.queue_free()
	_masks.clear()


## Godot 拖拽协议：本板为放置目标。落在格子上且过注入校验才接受。
func _can_drop_data(at_position: Vector2, data: Variant) -> bool:
	if data is Dictionary and str(data.get("instance_id", "")) != "":
		var size: Vector2i = data.get("size", Vector2i.ONE)
		if drop_checker.is_valid():
			return drop_checker.call(cell_at(at_position), size, str(data.get("instance_id", "")))
	return false


func _drop_data(at_position: Vector2, data: Variant) -> void:
	if data is Dictionary:
		item_dropped.emit(str(data.get("instance_id", "")), cell_at(at_position))


## 物品块：拖拽源 + 点击（内嵌类；拖拽数据由板/使用方消费）。
class ItemBlock:
	extends Control

	var instance_id := ""
	var board: GridBoard = null
	var _press_pos := Vector2.ZERO

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_press_pos = event.position
			elif event.position.distance_to(_press_pos) < 8.0:
				board.item_clicked.emit(instance_id)

	func _get_drag_data(_at_position: Vector2) -> Variant:
		if board == null:
			return null
		var preview := Panel.new()
		preview.size = size * 0.6
		preview.add_theme_stylebox_override("panel",
				PixelUiKit.inset_stylebox(Color(0.16, 0.19, 0.24, 0.9), Color(0.8, 0.84, 0.9)))
		var tip := Label.new()
		tip.text = "?"
		tip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview.add_child(tip)
		set_drag_preview(preview)
		return {"instance_id": instance_id, "size": Vector2i(
			roundi(size.x / board.cell), roundi(size.y / board.cell))}


## 转圈指示器：画一段圆弧持续旋转（speed 为弧度/秒），用于蒙版搜索中。
class Spinner:
	extends Control

	## 旋转角速度（弧度/秒）：按品质揭晓耗时换算（越稀有越慢）
	var speed := 3.0
	var _angle := 0.0

	func _process(delta: float) -> void:
		_angle = fmod(_angle + delta * speed, TAU)
		queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		draw_arc(c, r, _angle, _angle + PI * 1.2, 24, Color(0.85, 0.88, 0.95), 4.0, true)
