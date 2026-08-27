## warehouse_view.gd —— FullHaul 表现层：首页仓库场景视图（视觉升级 V1 / M3）
##
## 职责：
##   以「底图 plate + 叠层 props」呈现仓库内景：底图为整间房间贴图，
##   可交互单体（货架/卷帘门/托盘车等）为独立叠层节点，点击经
##   prop_activated 信号交回页面层；Camera2D 负责进场推拉与拖动平移，
##   Parallax2D 前后层微视差营造景深。纯表现组件，不接事件总线。
##
## 资产约定（docs/art/art-pipeline.md）：
##   - 底图：res://assets/art/plates/warehouse_plate.png（1080×760，2x 源降采样）
##   - 叠层：res://assets/art/props/<id>.png（带 alpha，尺寸见布局表）
##   文件缺失时以程序化占位图渲染（同构图/配色），正式资产就位即自动替换。
##
## 建造模式预留：
##   布局由 DEFAULT_LAYOUT 字典驱动，apply_layout()/current_layout() 为
##   将来「基地布置」玩法的存/载入口（本期只读，不做编辑器）。

extends Node2D
class_name WarehouseView

## 点击命中叠层物（action 由页面层解释：warehouse=开仓库弹窗 extract=撤离伏笔）
signal prop_activated(prop_id: String, action: String)

## 底图逻辑尺寸（design px；生成规格见 art-pipeline.md）
const PLATE_SIZE := Vector2(1080, 760)
## 相机进场推拉参数
const ZOOM_IN_STEP := 1.06
const PUSH_DURATION := 0.4

## 默认布局：pos/size 为世界坐标（plate 本地系）；layer 决定视差层；
## hotspot=false 的物件纯氛围。货架→仓库弹窗、卷帘门→撤离伏笔。
const DEFAULT_LAYOUT := {
	"plate": "res://assets/art/plates/warehouse_plate.png",
	"props": [
		{"id": "shelf_a", "pos": [270, 470], "size": [260, 300], "layer": "mid", "hotspot": true, "action": "warehouse", "hint": "货架 A"},
		{"id": "shelf_b", "pos": [810, 470], "size": [260, 300], "layer": "mid", "hotspot": true, "action": "warehouse", "hint": "货架 B"},
		{"id": "crate_stack", "pos": [540, 620], "size": [220, 150], "layer": "mid", "hotspot": true, "action": "warehouse", "hint": "地堆木箱"},
		{"id": "roll_door", "pos": [790, 205], "size": [200, 210], "layer": "mid", "hotspot": true, "action": "extract", "hint": "卷帘门"},
		{"id": "barrels", "pos": [930, 350], "size": [120, 140], "layer": "mid", "hotspot": false, "action": "", "hint": "油桶"},
		{"id": "plants", "pos": [150, 250], "size": [110, 120], "layer": "mid", "hotspot": false, "action": "", "hint": "盆栽"},
		{"id": "pallet_jack", "pos": [330, 700], "size": [170, 110], "layer": "fore", "hotspot": false, "action": "", "hint": "托盘车"},
	],
}

## 视差层运动系数（相对相机位移的倍率；1.0 = 随底图，>1 前景更快）
const LAYER_MOTION := {"back": 0.94, "mid": 1.0, "fore": 1.12}

# ---- 占位图配色（对齐 PixelUiKit 概念图调色板）----
const C_FLOOR := Color(0.851, 0.867, 0.878)
const C_FLOOR_LINE := Color(0.957, 0.753, 0.267)
const C_WALL := Color(0.231, 0.404, 0.784)
const C_WALL_HI := Color(0.357, 0.522, 0.855)
const C_WOOD := Color(0.808, 0.588, 0.333)
const C_WOOD_DK := Color(0.556, 0.384, 0.196)
const C_TEAL := Color(0.29, 0.69, 0.54)
const C_STEEL := Color(0.62, 0.66, 0.71)

var camera: Camera2D = null
## 相机平移偏移（相对居中home位；由页面层拖动驱动，受 pan_bounds 约束）
var _pan := Vector2.ZERO
var _props: Array[Dictionary] = []
var _layers: Dictionary = {}
var _back_layer: Parallax2D = null
var _plate_center := PLATE_SIZE / 2.0
var _pushed_in := false
var _t := 0.0
var _door_prop: Node2D = null


func _ready() -> void:
	_build_layers()
	_apply_layout(DEFAULT_LAYOUT)
	_build_camera()
	## 视口尺寸由 SubViewportContainer(stretch) 就绪后才有意义，延迟一帧推拉
	call_deferred("play_push_in")


func _process(delta: float) -> void:
	_t += delta
	## 卷帘门提示灯呼吸（正式资产就位后同样生效，属轻量氛围）
	if _door_prop != null:
		_door_prop.modulate = Color(1, 1, 1, 0.9 + 0.1 * sin(_t * 2.2))


## ---- 对外接口 ----

## 相机允许的平移范围（±，design px）：底图超出视口的部分。
func pan_bounds() -> Vector2:
	var vp := get_viewport_rect().size
	return Vector2(maxf(PLATE_SIZE.x - vp.x, 0.0), maxf(PLATE_SIZE.y - vp.y, 0.0)) / 2.0


## 当前平移偏移（页面层在拖动起点的快照与点击判定用）。
func pan() -> Vector2:
	return _pan


## 页面层拖动入口：偏移量自动 clamp 到底图边界内。
func set_pan(offset: Vector2) -> void:
	_pan = offset.clamp(-pan_bounds(), pan_bounds())
	if camera != null:
		camera.position = _plate_center + _pan


## 命中测试：canvas（视口）坐标转世界坐标后自上而下找叠层物。
func try_activate_at(canvas_pos: Vector2) -> bool:
	var world := get_canvas_transform().affine_inverse() * canvas_pos
	for i in range(_props.size() - 1, -1, -1):
		var p := _props[i]
		var rect := Rect2(Vector2(p.pos) - Vector2(p.size) / 2.0, Vector2(p.size))
		if rect.has_point(world):
			if p.hotspot:
				prop_activated.emit(p.id, p.action)
			return true
	return false


## 某叠层物中心的世界坐标（测试/预览工具用）。
func prop_center(prop_id: String) -> Vector2:
	for p in _props:
		if p.id == prop_id:
			return Vector2(p.pos)
	return _plate_center


## 建造模式预留：替换布局并重建叠层。
func apply_layout(layout: Dictionary) -> void:
	_apply_layout(layout)


## 建造模式预留：当前布局快照（可序列化存档）。
func current_layout() -> Dictionary:
	return {"plate": DEFAULT_LAYOUT.plate,
		"props": _props.map(func(p: Dictionary) -> Dictionary: return p.duplicate())}


## ---- 内部构建 ----

func _build_layers() -> void:
	for key in LAYER_MOTION:
		var layer := Parallax2D.new()
		layer.scroll_scale = Vector2.ONE * LAYER_MOTION[key]
		add_child(layer)
		_layers[key] = layer
	_back_layer = _layers.back


func _build_camera() -> void:
	camera = Camera2D.new()
	camera.position = _plate_center
	add_child(camera)
	camera.make_current()


func _apply_layout(layout: Dictionary) -> void:
	for layer in _layers.values():
		for child in layer.get_children():
			child.queue_free()
	_props.clear()
	var plate := Sprite2D.new()
	plate.texture = _plate_texture(layout.get("plate", ""))
	plate.position = _plate_center
	_back_layer.add_child(plate)
	for prop_def in layout.get("props", []):
		var p: Dictionary = prop_def.duplicate()
		p.pos = Vector2(p.pos[0], p.pos[1])
		p.size = Vector2(p.size[0], p.size[1])
		var node := _make_prop_node(p)
		node.position = p.pos
		(_layers[p.layer] as Parallax2D).add_child(node)
		p.node_path = node.get_path()
		if p.id == "roll_door":
			_door_prop = node
		_props.append(p)


func _make_prop_node(p: Dictionary) -> Node2D:
	var holder := Node2D.new()
	var sprite := Sprite2D.new()
	sprite.texture = _prop_texture(p)
	holder.add_child(sprite)
	return holder


## 底图贴图：正式资产存在则加载，否则程序化占位（同构图：地坪+导引线+后墙带）。
func _plate_texture(path: String) -> Texture2D:
	if path != "" and ResourceLoader.exists(path):
		return load(path) as Texture2D
	var img := PixelArtKit.canvas(int(PLATE_SIZE.x) * 2, int(PLATE_SIZE.y) * 2)
	var wall_h := 300
	PixelArtKit.rect(img, 0, 0, img.get_width(), wall_h * 2, C_WALL)
	## 后墙竖框与采光带（概念图钢构节奏的抽象）
	for x in range(90, img.get_width() - 60, 240):
		PixelArtKit.rect(img, x, 0, 26, wall_h * 2, C_WALL_HI)
	PixelArtKit.rect(img, 0, wall_h * 2 - 22, img.get_width(), 22, Color(0.145, 0.26, 0.51))
	## 地坪与黄色导引线
	PixelArtKit.rect(img, 0, wall_h * 2, img.get_width(), img.get_height() - wall_h * 2, C_FLOOR)
	PixelArtKit.rect(img, 300, 880, 1200, 26, C_FLOOR_LINE)
	PixelArtKit.rect(img, 300, 880, 26, 620, C_FLOOR_LINE)
	PixelArtKit.rect(img, 1494, 880, 26, 620, C_FLOOR_LINE)
	## 卷帘门底色块（占位构图中的门位）
	PixelArtKit.rect(img, 1380, 120, 400, 460, Color(0.82, 0.83, 0.85))
	for y in range(140, 560, 40):
		PixelArtKit.hline(img, 1384, 1776, y, Color(0.7, 0.72, 0.75))
	img.resize(int(PLATE_SIZE.x), int(PLATE_SIZE.y), Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


## 叠层贴图：正式资产 res://assets/art/props/<id>.png 优先，否则占位色块。
func _prop_texture(p: Dictionary) -> Texture2D:
	var path := "res://assets/art/props/%s.png" % p.id
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var w := int(p.size.x)
	var h := int(p.size.y)
	var img := PixelArtKit.canvas(w * 2, h * 2)
	var base := C_WOOD
	var edge := C_WOOD_DK
	match String(p.id):
		"barrels":
			base = C_STEEL
			edge = base.darkened(0.35)
		"plants":
			base = C_TEAL
			edge = base.darkened(0.35)
		"roll_door":
			base = Color(0.82, 0.83, 0.85)
			edge = Color(0.45, 0.47, 0.52)
		"pallet_jack":
			base = C_FLOOR_LINE
			edge = base.darkened(0.4)
	match String(p.layer):
		"fore":
			edge = edge.darkened(0.08)
	_round_rect(img, Rect2i(4, 4, w * 2 - 8, h * 2 - 8), base, edge)
	if String(p.id).begins_with("shelf"):
		for y in range(14, h * 2 - 10, 34):
			PixelArtKit.hline(img, 12, w * 2 - 12, y, edge)
	img.resize(w, h, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


## 圆角矩形占位（外描边 + 受光顶边），替代旧版像素凸台语言。
static func _round_rect(img: Image, r: Rect2i, base: Color, edge: Color) -> void:
	PixelArtKit.rect(img, r.position.x, r.position.y + 2, r.size.x, r.size.y - 4, base)
	PixelArtKit.rect(img, r.position.x, r.position.y, r.size.x, 4, base.lightened(0.14))
	var b := 3
	for y in range(r.position.y, r.end.y):
		PixelArtKit.hline(img, r.position.x, r.position.x + b - 1, y, edge)
		PixelArtKit.hline(img, r.end.x - b, r.end.x - 1, y, edge)
	PixelArtKit.hline(img, r.position.x, r.end.x - 1, r.position.y, edge)
	PixelArtKit.hline(img, r.position.x, r.end.x - 1, r.end.y - 1, edge)


## 进场推拉（zoom 预留为建造模式的手动缩放通道）。
func play_push_in() -> void:
	if _pushed_in or camera == null:
		return
	_pushed_in = true
	camera.zoom = Vector2.ONE * ZOOM_IN_STEP
	var tw := create_tween()
	tw.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_property(camera, "zoom", Vector2.ONE, PUSH_DURATION)
